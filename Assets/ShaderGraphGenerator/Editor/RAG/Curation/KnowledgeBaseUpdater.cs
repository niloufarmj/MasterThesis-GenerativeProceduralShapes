using System;
using System.Collections.Generic;
using System.IO;
using System.Threading.Tasks;
using UnityEditor;
using UnityEngine;
using UnityEngine.Networking;
using Newtonsoft.Json;
using ShaderGraphGenerator.Editor;
using ShaderGraphGenerator.KnowledgeBase;

namespace ShaderGraphGenerator.RAG
{
    /// <summary>
    /// Adds a successfully generated RAG shape (score > 8) back into the knowledge base.
    ///
    /// Steps:
    ///   1. Copy HLSL → SuccessfulResults/
    ///   2. Ask OpenAI Vision to write a visual description comment (like existing library files)
    ///   3. Append that comment block to the saved HLSL file
    ///   4. Ask Gemini to analyse the HLSL and produce full metadata JSON
    ///      (same flow as MetadataExtractor / KnowledgeBaseLLMService)
    ///   5. Build ShapeMetadata, generate embedding, update shape_metadata.json
    ///   6. Append the user prompt to final-shape-list.txt
    /// </summary>
    public static class KnowledgeBaseUpdater
    {
        // ─── paths ────────────────────────────────────────────────────────────
        private const string SUCCESSFUL_RESULTS_FOLDER = "Assets/ShaderGraphs/SuccessfulResults";
        private const string KB_JSON_PATH              = "Assets/ShaderGraphGenerator/KnowledgeBase/shape_metadata.json";
        private const string PROMPT_LIST_PATH          = "Assets/final-shape-list.txt";

        public const int AUTO_LEARN_THRESHOLD = 8;

        // ─── public entry points ──────────────────────────────────────────────

        /// <summary>
        /// Auto-learn path: called after RAG pipeline. Checks score threshold, then
        /// delegates to the shared ingestion pipeline.
        /// </summary>
        public static async Task<bool> TryAddToLibraryAsync(
            RAGPipelineResult result,
            string geminiKey,
            string openAIKey)
        {
            if (result.vmlScore <= AUTO_LEARN_THRESHOLD)
            {
                Debug.Log($"[KB Updater] Score {result.vmlScore}/10 ≤ threshold ({AUTO_LEARN_THRESHOLD}). Skipping.");
                return false;
            }

            if (string.IsNullOrEmpty(result.hlslCode) || string.IsNullOrEmpty(result.fileName))
            {
                Debug.LogWarning("[KB Updater] Missing HLSL code or file name — cannot add to library.");
                return false;
            }

            // Write HLSL to disk first so AddToLibraryAsync can read it from a path
            if (!Directory.Exists(SUCCESSFUL_RESULTS_FOLDER))
                Directory.CreateDirectory(SUCCESSFUL_RESULTS_FOLDER);

            string destPath = Path.Combine(SUCCESSFUL_RESULTS_FOLDER, $"{result.fileName}.hlsl");
            File.WriteAllText(destPath, result.hlslCode);
            AssetDatabase.Refresh();

            return await AddToLibraryAsync(
                hlslPath:       destPath,
                imagePath:      result.previewImagePath,
                userPrompt:     result.userRequest,
                verifyScore:    result.vmlScore,
                fallbackDesc:   result.vmlFeedback,
                geminiKey:      geminiKey,
                openAIKey:      openAIKey);
        }

        /// <summary>
        /// Manual path: called from the manual-add tool (2.5).
        /// hlslPath must already exist on disk (anywhere — will be copied to SuccessfulResults).
        /// imagePath is the screenshot; userPrompt is what the shape represents.
        /// </summary>
        public static async Task<bool> AddToLibraryAsync(
            string hlslPath,
            string imagePath,
            string userPrompt,
            string geminiKey,
            string openAIKey,
            int    verifyScore  = 10,
            string fallbackDesc = null)
        {
            if (!File.Exists(hlslPath))
            {
                Debug.LogError($"[KB Updater] HLSL file not found: {hlslPath}");
                return false;
            }

            string fileName = Path.GetFileNameWithoutExtension(hlslPath);

            // ── 1. Copy HLSL to SuccessfulResults (skip if it is already there) ──
            if (!Directory.Exists(SUCCESSFUL_RESULTS_FOLDER))
                Directory.CreateDirectory(SUCCESSFUL_RESULTS_FOLDER);

            string destPath = Path.Combine(SUCCESSFUL_RESULTS_FOLDER, $"{fileName}.hlsl");
            if (!string.Equals(Path.GetFullPath(hlslPath), Path.GetFullPath(destPath),
                               StringComparison.OrdinalIgnoreCase))
            {
                File.Copy(hlslPath, destPath, overwrite: true);
                AssetDatabase.Refresh();
            }
            Debug.Log($"[KB Updater] HLSL at: {destPath}");

            string hlslCode = File.ReadAllText(destPath);

            // ── 2. Generate visual description via OpenAI Vision ──────────────
            string visualDescription = null;
            if (!string.IsNullOrEmpty(imagePath) && File.Exists(imagePath))
            {
                Debug.Log("[KB Updater] Requesting visual description from OpenAI Vision...");
                visualDescription = await GenerateVisualDescriptionAsync(
                    imagePath, userPrompt, hlslCode, openAIKey);
            }

            if (string.IsNullOrEmpty(visualDescription))
            {
                visualDescription = !string.IsNullOrEmpty(fallbackDesc)
                    ? fallbackDesc
                    : $"A procedurally generated {fileName} shape.";
                Debug.LogWarning("[KB Updater] Vision call failed or skipped — using fallback description.");
            }

            // ── 3. Append visual description comment to HLSL ──────────────────
            // Only append if the comment block is not already present
            if (!hlslCode.Contains("Visual Result (High-level"))
            {
                AppendVisualDescriptionComment(destPath, visualDescription);
                Debug.Log("[KB Updater] Visual description comment appended to HLSL.");
            }

            // ── 4. LLM metadata analysis ──────────────────────────────────────
            Debug.Log("[KB Updater] Requesting LLM metadata analysis...");
            string hlslWithComment = File.ReadAllText(destPath);
            var analysis = await KnowledgeBaseLLMService.AnalyzeShapeAsync(
                hlslWithComment, userPrompt, geminiKey);

            // ── 5. Build ShapeMetadata ────────────────────────────────────────
            var localMeta = HLSLParser.ParseHLSLFileLocal(destPath);

            var metadata = new ShapeMetadata
            {
                id                = Guid.NewGuid().ToString(),
                fileName          = fileName,
                filePath          = destPath,
                functionName      = localMeta?.functionName ?? $"{fileName}_float",
                originalPrompt    = userPrompt,
                visualDescription = visualDescription,
                category          = ParseCategory(analysis?.category),
                complexity        = ParseComplexity(analysis?.complexity),
                symmetry          = ParseSymmetry(analysis?.symmetry),
                tags              = analysis?.tags ?? new List<string> { "manually-added" },
                parameters        = localMeta?.parameters ?? new List<ShapeParameter>(),
                dateAdded         = DateTime.Now.ToString("yyyy-MM-dd"),
                verificationScore = verifyScore
            };

            // Prefer the LLM's richer visual_description when available
            if (analysis != null && !string.IsNullOrEmpty(analysis.visual_description))
                metadata.visualDescription = analysis.visual_description;

            // ── 6. Generate embedding ─────────────────────────────────────────
            string embeddingText = ShapeEmbeddingService.CreateSearchableText(metadata);
            metadata.embedding = await ShapeEmbeddingService.GenerateEmbeddingAsync(embeddingText, openAIKey);
            if (metadata.embedding == null)
                Debug.LogWarning("[KB Updater] Embedding generation failed — shape added without embedding.");

            // ── 7. Update knowledge-base JSON ─────────────────────────────────
            ShapeKnowledgeBase kb = LoadKnowledgeBase();
            kb.shapes.RemoveAll(s => s.fileName == fileName);
            kb.shapes.Add(metadata);
            kb.totalShapes = kb.shapes.Count;
            SaveKnowledgeBase(kb);
            Debug.Log($"[KB Updater] ✓ '{fileName}' added to KB. Total: {kb.totalShapes}");

            // ── 8. Append user prompt to final-shape-list.txt ─────────────────
            AppendToPromptList(userPrompt);

            return true;
        }

        // ─── visual description via OpenAI Vision ─────────────────────────────

        private static async Task<string> GenerateVisualDescriptionAsync(
            string imagePath,
            string userRequest,
            string hlslCode,
            string apiKey)
        {
            const string url = "https://api.openai.com/v1/chat/completions";

            byte[] imageBytes = File.ReadAllBytes(imagePath);
            string base64 = Convert.ToBase64String(imageBytes);
            string dataUrl = $"data:image/png;base64,{base64}";

            string textContent =
                "You are documenting a procedural 2D shape shader for a developer knowledge base.\n\n" +
                "User request that produced this shape:\n" + userRequest + "\n\n" +
                "Analyse the rendered preview image and the HLSL code below, then write a " +
                "detailed, parameter-invariant visual description exactly like the example:\n\n" +
                "Example format:\n" +
                "This function produces a **2D bat silhouette** constructed from analytic SDFs.\n" +
                "The resulting shape is composed of:\n" +
                "- A central elliptical segment (body)\n" +
                "- Two triangular segments (ears) positioned on top\n" +
                "- Two symmetric wing segments with arched upper curves and scalloped bottom edges\n" +
                "These parts are combined using smooth unions to create a single continuous organic silhouette.\n\n" +
                "Rules:\n" +
                "- Describe what the shape IS visually, not how it is coded.\n" +
                "- List the main visual sub-parts using bullet points.\n" +
                "- Mention key visual qualities (smooth, sharp, symmetric, organic, etc.).\n" +
                "- Do NOT mention parameter values or variable names.\n" +
                "- 4-8 sentences total.\n" +
                "- Return ONLY the plain-text description, no JSON, no markdown headers.\n\n" +
                "HLSL code:\n" + hlslCode;

            var bodyObject = new
            {
                model = "gpt-4o",
                messages = new object[]
                {
                    new {
                        role = "user",
                        content = new object[]
                        {
                            new { type = "text", text = textContent },
                            new { type = "image_url", image_url = new { url = dataUrl } }
                        }
                    }
                },
                max_tokens = 400
            };

            string jsonBody = JsonConvert.SerializeObject(bodyObject);
            byte[] bodyRaw = System.Text.Encoding.UTF8.GetBytes(jsonBody);

            using (var www = new UnityWebRequest(url, "POST"))
            {
                www.uploadHandler   = new UploadHandlerRaw(bodyRaw);
                www.downloadHandler = new DownloadHandlerBuffer();
                www.SetRequestHeader("Content-Type", "application/json");
                www.SetRequestHeader("Authorization", $"Bearer {apiKey}");

                var op = www.SendWebRequest();
                while (!op.isDone) await Task.Yield();

                if (www.result != UnityWebRequest.Result.Success)
                {
                    Debug.LogError($"[KB Updater] OpenAI Vision error: {www.error}\n{www.downloadHandler.text}");
                    return null;
                }

                try
                {
                    dynamic parsed = JsonConvert.DeserializeObject(www.downloadHandler.text);
                    return ((string)parsed.choices[0].message.content).Trim();
                }
                catch (Exception ex)
                {
                    Debug.LogError($"[KB Updater] Failed to parse Vision response: {ex.Message}");
                    return null;
                }
            }
        }

        // ─── append comment block to HLSL ─────────────────────────────────────

        private static void AppendVisualDescriptionComment(string filePath, string description)
        {
            // Wrap each line of the description as a // comment line
            string[] lines = description.Split('\n');
            var sb = new System.Text.StringBuilder();
            sb.AppendLine();
            sb.AppendLine("// ------------------------------------------------------------------------");
            sb.AppendLine("//  Visual Result (High-level, parameter-invariant description)");
            sb.AppendLine("// ------------------------------------------------------------------------");
            foreach (string line in lines)
            {
                string trimmed = line.TrimEnd();
                sb.AppendLine(string.IsNullOrEmpty(trimmed) ? "//" : $"//  {trimmed}");
            }
            sb.AppendLine("// ------------------------------------------------------------------------");

            File.AppendAllText(filePath, sb.ToString());
        }

        // ─── prompt list ───────────────────────────────────────────────────────

        private static void AppendToPromptList(string userRequest)
        {
            if (string.IsNullOrWhiteSpace(userRequest)) return;

            // Read existing prompts to avoid duplicates
            if (File.Exists(PROMPT_LIST_PATH))
            {
                string existing = File.ReadAllText(PROMPT_LIST_PATH);
                if (existing.Contains(userRequest.Trim()))
                {
                    Debug.Log("[KB Updater] Prompt already exists in final-shape-list.txt — skipping.");
                    return;
                }
            }

            // Ensure file ends with a newline before appending
            string toAppend = userRequest.Trim() + Environment.NewLine + Environment.NewLine;
            File.AppendAllText(PROMPT_LIST_PATH, toAppend);
            AssetDatabase.Refresh();
            Debug.Log($"[KB Updater] ✓ Prompt appended to {PROMPT_LIST_PATH}");
        }

        // ─── KB JSON helpers ───────────────────────────────────────────────────

        private static ShapeKnowledgeBase LoadKnowledgeBase()
        {
            if (!File.Exists(KB_JSON_PATH))
            {
                Debug.LogWarning("[KB Updater] KB JSON not found — creating a new one.");
                return new ShapeKnowledgeBase { generatedDate = DateTime.Now.ToString("yyyy-MM-dd") };
            }
            try
            {
                return JsonConvert.DeserializeObject<ShapeKnowledgeBase>(File.ReadAllText(KB_JSON_PATH))
                       ?? new ShapeKnowledgeBase();
            }
            catch (Exception ex)
            {
                Debug.LogError($"[KB Updater] Failed to load KB: {ex.Message}");
                return new ShapeKnowledgeBase();
            }
        }

        private static void SaveKnowledgeBase(ShapeKnowledgeBase kb)
        {
            string dir = Path.GetDirectoryName(KB_JSON_PATH);
            if (!Directory.Exists(dir)) Directory.CreateDirectory(dir);
            File.WriteAllText(KB_JSON_PATH, JsonConvert.SerializeObject(kb, Formatting.Indented));
            AssetDatabase.Refresh();
        }

        // ─── enum parsers (same as MetadataExtractor) ─────────────────────────

        private static ShapeCategory ParseCategory(string v) => v switch
        {
            "GeometricPrimitives" => ShapeCategory.GeometricPrimitives,
            "OrganicShapes"       => ShapeCategory.OrganicShapes,
            "SymbolsAndIcons"     => ShapeCategory.SymbolsAndIcons,
            "CompositeShapes"     => ShapeCategory.CompositeShapes,
            _                     => ShapeCategory.CompositeShapes   // RAG shapes are always composite
        };

        private static ComplexityLevel ParseComplexity(string v) => v switch
        {
            "Primitive"    => ComplexityLevel.Primitive,
            "Intermediate" => ComplexityLevel.Intermediate,
            "Complex"      => ComplexityLevel.Complex,
            _              => ComplexityLevel.Complex
        };

        private static SymmetryType ParseSymmetry(string v) => v switch
        {
            "None"      => SymmetryType.None,
            "Bilateral" => SymmetryType.Bilateral,
            "Radial"    => SymmetryType.Radial,
            "Both"      => SymmetryType.Both,
            _           => SymmetryType.Unknown
        };

        // ─── fallback parameter conversion ────────────────────────────────────

        private static List<ShapeParameter> ConvertProperties(List<LLMShaderProperty> props)
        {
            var list = new List<ShapeParameter>();
            if (props == null) return list;
            foreach (var p in props)
            {
                var v = p.default_value;
                string t = p.type?.ToLowerInvariant() ?? "float";
                string dv = t switch
                {
                    "float"  => v.x.ToString("F4"),
                    "float2" => $"{v.x:F4},{v.y:F4}",
                    "float3" => $"{v.x:F4},{v.y:F4},{v.z:F4}",
                    _        => $"{v.x:F4},{v.y:F4},{v.z:F4},{v.w:F4}"
                };
                list.Add(new ShapeParameter { name = p.name, type = p.type, defaultValue = dv });
            }
            return list;
        }
    }
}
