using System;
using System.Collections.Generic;
using System.IO;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using UnityEditor;
using UnityEngine;
using Newtonsoft.Json;
using ShaderGraphGenerator.KnowledgeBase;
using ShaderGraphGenerator.Editor;

namespace ShaderGraphGenerator.RAG
{
    // ─── result data model ────────────────────────────────────────────────────

    public class HLSLUpdateResult
    {
        public string updateRequest;
        public string originalFileName;
        public string originalHlslCode;
        public string updatedFileName;
        public string updatedHlslCode;
        public List<LLMShaderProperty> properties;
        public string shaderGraphPath;
        public string materialPath;
        public string beforeImagePath;
        public string afterImagePath;
        public int    vlmScore;
        public string vlmFeedback;
        public bool   success;       // true = VLM score > 7
        public string errorMessage;
    }

    // ─── pipeline ─────────────────────────────────────────────────────────────

    /// <summary>
    /// Applies an update request to an existing material's HLSL shader using a
    /// VLM-validated before/after comparison loop.
    ///
    /// This pipeline is used for:
    ///   - Shape editing when the edit requires HLSL changes (e.g. "add stripes to the scarf")
    ///   - Animation setup when new shader properties must be added before animating
    ///   - Effect application (when LLM-driven; pixelation uses the client-side path instead)
    ///
    /// Pipeline steps:
    ///   1. Locate the HLSL source file referenced by the material's ShaderGraph.
    ///   2. Extract all current material property values.
    ///   3. Render a BEFORE screenshot of the original material.
    ///   4. Retrieve relevant KB shapes via semantic search.
    ///   5. For each VLM iteration:
    ///      a. Gemini generates updated HLSL based on the update request + retrieved examples.
    ///      b. New ShaderGraph + Material are built from the updated HLSL.
    ///      c. An AFTER screenshot is rendered.
    ///      d. GPT-4o Vision compares before/after and scores whether the update was applied (1–10).
    ///      e. If score &gt; 7, accept and return; otherwise feed VLM feedback into the next iteration.
    ///
    /// Output assets are written to Assets/ShaderGraphs/RAG_Updates/.
    /// </summary>
    public static class HLSLUpdatePipelineManager
    {
        private const string UPDATE_DIR  = "Assets/ShaderGraphs/RAG_Updates";
        private const string PREVIEW_DIR = "Assets/ShaderGraphs/Previews";

        /// <summary>VLM score (exclusive) above which a generated update is accepted.</summary>
        private const int VLM_ACCEPT_THRESHOLD = 7;

        /// <summary>
        /// Runs the full HLSL update pipeline with VLM-guided validation.
        /// </summary>
        /// <param name="originalMaterial">The Unity Material whose ShaderGraph contains the HLSL to update.</param>
        /// <param name="updateRequest">
        /// A precise, self-contained description of what to change in the shader.
        /// The more specific this is (exact property names, visual outcomes), the more
        /// reliably the VLM can verify success in the before/after comparison.
        /// </param>
        /// <param name="knowledgeBase">KB for retrieving relevant HLSL examples.</param>
        /// <param name="config">API key config.</param>
        /// <param name="maxVlmIterations">Maximum refinement iterations (default 1).</param>
        /// <param name="userFeedback">Optional extra context from the user (e.g. from a retry).</param>
        /// <returns>
        /// <see cref="HLSLUpdateResult"/> with before/after image paths, VLM score, and
        /// paths to the updated HLSL, ShaderGraph, and Material.
        /// <c>success</c> is true only when VLM score &gt; <see cref="VLM_ACCEPT_THRESHOLD"/>.
        /// </returns>
        public static async Task<HLSLUpdateResult> RunUpdatePipelineAsync(
            Material originalMaterial,
            string   updateRequest,
            ShapeKnowledgeBase knowledgeBase,
            ShaderGraphGeneratorConfig config,
            int    maxVlmIterations = 1,
            string userFeedback     = null)
        {
            var result = new HLSLUpdateResult
            {
                updateRequest    = updateRequest,
                originalFileName = originalMaterial != null ? originalMaterial.name : "unknown"
            };

            try
            {
                EnsureDirectories();

                // ── 1. Extract HLSL from the material's ShaderGraph ───────────
                if (originalMaterial == null)
                {
                    result.errorMessage = "No material provided.";
                    return result;
                }

                string originalHlslPath = ExtractHlslPathFromMaterial(originalMaterial);
                if (string.IsNullOrEmpty(originalHlslPath))
                {
                    result.errorMessage =
                        "Could not find an HLSL Custom Function source in this material's ShaderGraph. " +
                        "Make sure the shader was generated by this tool.";
                    return result;
                }

                string originalHlsl = File.ReadAllText(originalHlslPath);
                result.originalHlslCode = originalHlsl;
                result.originalFileName  = Path.GetFileNameWithoutExtension(originalHlslPath);
                Debug.Log($"[Update Pipeline] HLSL source: {originalHlslPath}");

                // ── 2. Extract current material property values ───────────────
                var originalProperties = ExtractMaterialProperties(originalMaterial);
                Debug.Log($"[Update Pipeline] Extracted {originalProperties.Count} properties from material.");

                // ── 3. Render BEFORE screenshot from the original material ────
                Debug.Log("[Update Pipeline] Rendering BEFORE screenshot…");
                string beforePath    = Path.Combine(PREVIEW_DIR, $"{result.originalFileName}_before.png");
                string beforeAbsPath = ToAbsolutePath(beforePath);
                Directory.CreateDirectory(Path.GetDirectoryName(beforeAbsPath));
                bool beforeOk = await RenderMaterialToImageAsync(originalMaterial, beforeAbsPath, keepQuad: false);
                result.beforeImagePath = beforeOk && File.Exists(beforeAbsPath) ? beforeAbsPath : null;

                // ── 4. Retrieve relevant KB examples ──────────────────────────
                Debug.Log("[Update Pipeline] Retrieving KB examples for update…");
                var examples = await RetrieveExamplesAsync(updateRequest, knowledgeBase, config.openAIKey);

                // ── 5. VLM-guided iteration loop ──────────────────────────────
                string currentHlsl         = originalHlsl;
                string previousVlmFeedback = null;

                for (int iter = 1; iter <= maxVlmIterations; iter++)
                {
                    Debug.Log($"[Update Pipeline] VLM iteration {iter}/{maxVlmIterations}");

                    // 5a. Ask LLM to produce updated HLSL
                    string prompt = HLSLUpdatePromptBuilder.Build(
                        originalHlsl, currentHlsl, updateRequest,
                        originalProperties, examples,
                        previousVlmFeedback, userFeedback, iter);

                    string jsonRaw = await GeminiApiService.CallGeminiAsync(prompt, config.geminiKey);
                    if (string.IsNullOrEmpty(jsonRaw))
                    {
                        result.errorMessage = "LLM returned an empty response.";
                        return result;
                    }
                    jsonRaw = StripMarkdown(jsonRaw);

                    LLMShaderResponse llmResponse;
                    try { llmResponse = JsonConvert.DeserializeObject<LLMShaderResponse>(jsonRaw); }
                    catch (Exception ex)
                    {
                        Debug.LogError($"[Update Pipeline] JSON parse error: {ex.Message}\n{jsonRaw}");
                        continue; // try again
                    }

                    // 5b. Save updated HLSL
                    string updatedHlslPath = Path.Combine(UPDATE_DIR, $"{llmResponse.file_name}.hlsl");
                    File.WriteAllText(updatedHlslPath, llmResponse.hlsl_code);
                    AssetDatabase.Refresh();

                    // 5c. Build ShaderGraph + Material
                    string sgPath = Path.Combine(UPDATE_DIR, $"{llmResponse.file_name}.shadergraph");
                    ShaderGraphBuilder.BuildShaderGraphFromLLMResponse(updatedHlslPath, sgPath, useTransparency: true);
                    AssetDatabase.Refresh();
                    await Task.Delay(1200);
                    AssetDatabase.Refresh();
                    await Task.Delay(400);

                    var shader = AssetDatabase.LoadAssetAtPath<Shader>(sgPath);
                    if (shader == null)
                    {
                        Debug.LogWarning($"[Update Pipeline] Shader not loaded on iter {iter} — skipping.");
                        continue;
                    }

                    string matPath = Path.Combine(UPDATE_DIR, $"{llmResponse.file_name}.mat");
                    if (AssetDatabase.LoadAssetAtPath<UnityEngine.Object>(matPath) != null)
                        AssetDatabase.DeleteAsset(matPath);
                    var material = new Material(shader);
                    AssetDatabase.CreateAsset(material, matPath);
                    AssetDatabase.SaveAssets();
                    AssetDatabase.Refresh();

                    // Reload after refresh — the object reference may be stale post-reimport.
                    material = AssetDatabase.LoadAssetAtPath<Material>(matPath);

                    // Apply ALL properties returned by the LLM.
                    // The prompt instructs the LLM to return the FULL property list — keeping
                    // exact original values for unchanged params and updated values for changed/new ones.
                    // We must NOT use CopyPropertiesFromMaterial: it copies values from a different
                    // shader's property block, which silently fails or maps to wrong slots when the
                    // new shader has different or additional properties. Any property only on the new
                    // shader would be left at 0,0,0,0 (fully transparent / invisible).
                    if (llmResponse.properties != null && llmResponse.properties.Count > 0)
                        MaterialPreviewHelper.SetDefaultMaterialProperties(material, llmResponse.properties);

                    // Persist so Unity uses the correct values at render time.
                    EditorUtility.SetDirty(material);
                    AssetDatabase.SaveAssets();

                    // 5d. Render AFTER screenshot (quad stays in scene)
                    string afterPath    = Path.Combine(PREVIEW_DIR, $"{llmResponse.file_name}_after_{iter}.png");
                    string afterAbsPath = ToAbsolutePath(afterPath);
                    Directory.CreateDirectory(Path.GetDirectoryName(afterAbsPath));
                    bool rendered = await RenderMaterialToImageAsync(material, afterAbsPath, keepQuad: true);
                    if (!rendered)
                    {
                        Debug.LogWarning($"[Update Pipeline] After render failed on iter {iter}.");
                        continue;
                    }

                    // 5e. VLM comparison evaluation (before vs after)
                    var eval = await EvaluateUpdateAsync(
                        updateRequest, result.beforeImagePath, afterAbsPath, config.openAIKey);

                    Debug.Log($"[Update Pipeline] VLM score: {eval.score}/10 — {eval.explanation}");

                    // Save best result so far
                    result.updatedFileName = llmResponse.file_name;
                    result.updatedHlslCode = llmResponse.hlsl_code;
                    result.properties      = llmResponse.properties;
                    result.shaderGraphPath = sgPath;
                    result.materialPath    = matPath;
                    result.afterImagePath  = afterAbsPath;
                    result.vlmScore        = eval.score;
                    result.vlmFeedback     = eval.explanation;

                    if (eval.score > VLM_ACCEPT_THRESHOLD)
                    {
                        result.success = true;
                        Debug.Log($"[Update Pipeline] ✓ Accepted at VLM iteration {iter}.");
                        return result;
                    }

                    previousVlmFeedback = eval.explanation;
                    currentHlsl         = llmResponse.hlsl_code;
                }

                // All VLM iterations exhausted — return best attempt anyway
                result.success      = false;
                result.errorMessage = $"VLM score never exceeded {VLM_ACCEPT_THRESHOLD} in {maxVlmIterations} iterations.";
                return result;
            }
            catch (Exception ex)
            {
                result.errorMessage = ex.Message;
                Debug.LogError($"[Update Pipeline] Exception: {ex.Message}\n{ex.StackTrace}");
                return result;
            }
        }

        // ─── Extract HLSL path from material's ShaderGraph ────────────────────

        /// <summary>
        /// Reads the .shadergraph asset referenced by the material's shader,
        /// finds the CustomFunctionNode's m_FunctionSource GUID, and resolves it to an HLSL path.
        /// </summary>
        public static string ExtractHlslPathFromMaterial(Material material)
        {
            string sgPath = AssetDatabase.GetAssetPath(material.shader);
            if (string.IsNullOrEmpty(sgPath) || !File.Exists(sgPath))
            {
                Debug.LogWarning("[Update Pipeline] Material's shader asset not found on disk.");
                return null;
            }

            string sgJson = File.ReadAllText(sgPath);
            var match = Regex.Match(sgJson, @"""m_FunctionSource""\s*:\s*""([a-f0-9A-F]+)""");
            if (!match.Success)
            {
                Debug.LogWarning("[Update Pipeline] No m_FunctionSource GUID found in ShaderGraph.");
                return null;
            }

            string guid     = match.Groups[1].Value;
            string hlslPath = AssetDatabase.GUIDToAssetPath(guid);
            if (string.IsNullOrEmpty(hlslPath))
            {
                Debug.LogWarning($"[Update Pipeline] GUID {guid} could not be resolved to an asset path.");
                return null;
            }

            return hlslPath;
        }

        // ─── Extract current property values from a material ──────────────────

        /// <summary>
        /// Reads all Float, Range, Vector, and Color properties from a material
        /// and returns them as LLMShaderProperty list (the same format LLM outputs).
        /// </summary>
        private static List<LLMShaderProperty> ExtractMaterialProperties(Material material)
        {
            var result = new List<LLMShaderProperty>();

            MaterialProperty[] props;
            try
            {
                props = MaterialEditor.GetMaterialProperties(new UnityEngine.Object[] { material });
            }
            catch (Exception ex)
            {
                Debug.LogWarning($"[Update Pipeline] Could not read material properties: {ex.Message}");
                return result;
            }

            foreach (var prop in props)
            {
                // Skip Unity internal / texture properties
                if (prop.name.StartsWith("unity_", StringComparison.OrdinalIgnoreCase)) continue;
                if (prop.type == MaterialProperty.PropType.Texture) continue;

                LLMShaderProperty sp = null;

                switch (prop.type)
                {
                    case MaterialProperty.PropType.Float:
                    case MaterialProperty.PropType.Range:
                        sp = new LLMShaderProperty
                        {
                            name          = prop.name,
                            type          = "float",
                            default_value = new LLMValueObject(prop.floatValue)
                        };
                        break;

                    case MaterialProperty.PropType.Vector:
                        sp = new LLMShaderProperty
                        {
                            name          = prop.name,
                            type          = "float4",
                            default_value = new LLMValueObject(
                                prop.vectorValue.x, prop.vectorValue.y,
                                prop.vectorValue.z, prop.vectorValue.w)
                        };
                        break;

                    case MaterialProperty.PropType.Color:
                        sp = new LLMShaderProperty
                        {
                            name          = prop.name,
                            type          = "float4",
                            default_value = new LLMValueObject(
                                prop.colorValue.r, prop.colorValue.g,
                                prop.colorValue.b, prop.colorValue.a)
                        };
                        break;
                }

                if (sp != null) result.Add(sp);
            }

            return result;
        }

        // ─── shared render helper ─────────────────────────────────────────────

        private static async Task<bool> RenderMaterialToImageAsync(
            Material material, string outputPath, bool keepQuad)
        {
            // Hide all existing renderers
            var allRenderers = UnityEngine.Object.FindObjectsByType<Renderer>(FindObjectsSortMode.None);
            var wasEnabled   = new bool[allRenderers.Length];
            for (int i = 0; i < allRenderers.Length; i++)
            {
                wasEnabled[i]           = allRenderers[i].enabled;
                allRenderers[i].enabled = false;
            }

            GameObject quad      = null;
            GameObject cameraGO  = null;
            Camera     cam       = null;
            RenderTexture rt     = null;
            Texture2D screenshot = null;

            try
            {
                quad = GameObject.CreatePrimitive(PrimitiveType.Quad);
                quad.name = $"UpdatePreview — {material.name}";
                quad.GetComponent<Renderer>().material = material;
                quad.transform.SetPositionAndRotation(Vector3.zero, Quaternion.identity);
                quad.transform.localScale = Vector3.one;

                if (keepQuad)
                {
                    Selection.activeGameObject = quad;
                    if (SceneView.lastActiveSceneView != null)
                        SceneView.lastActiveSceneView.FrameSelected();
                }

                cameraGO = new GameObject("_UpdateRenderCamera");
                cam      = cameraGO.AddComponent<Camera>();
                cam.transform.position = new Vector3(0f, 0f, -2f);
                cam.transform.LookAt(quad.transform);
                cam.clearFlags       = CameraClearFlags.SolidColor;
                cam.backgroundColor  = Color.white;
                cam.orthographic     = true;
                cam.orthographicSize = 0.55f;
                cam.cullingMask      = 1 << quad.layer;

                rt                = new RenderTexture(512, 512, 24);
                cam.targetTexture = rt;

                await Task.Delay(100);
                cam.Render();

                RenderTexture.active = rt;
                screenshot = new Texture2D(512, 512, TextureFormat.RGBA32, false);
                screenshot.ReadPixels(new Rect(0, 0, 512, 512), 0, 0);
                screenshot.Apply();

                // Composite transparent pixels over white
                var pixels = screenshot.GetPixels32();
                for (int i = 0; i < pixels.Length; i++)
                {
                    float a     = pixels[i].a / 255f;
                    pixels[i].r = (byte)(pixels[i].r * a + 255 * (1f - a));
                    pixels[i].g = (byte)(pixels[i].g * a + 255 * (1f - a));
                    pixels[i].b = (byte)(pixels[i].b * a + 255 * (1f - a));
                    pixels[i].a = 255;
                }
                screenshot.SetPixels32(pixels);
                screenshot.Apply();

                File.WriteAllBytes(outputPath, screenshot.EncodeToPNG());
                Debug.Log($"[Update Pipeline] Screenshot saved: {outputPath}");
                return true;
            }
            catch (Exception ex)
            {
                Debug.LogError($"[Update Pipeline] Render failed: {ex.Message}");
                return false;
            }
            finally
            {
                RenderTexture.active = null;
                // Detach RT from camera before releasing it, otherwise Unity throws a warning.
                if (cam != null) cam.targetTexture = null;
                if (rt         != null) { rt.Release(); UnityEngine.Object.DestroyImmediate(rt); }
                if (screenshot != null) UnityEngine.Object.DestroyImmediate(screenshot);
                if (cameraGO   != null) UnityEngine.Object.DestroyImmediate(cameraGO);
                if (!keepQuad && quad != null) UnityEngine.Object.DestroyImmediate(quad);

                for (int i = 0; i < allRenderers.Length; i++)
                    if (allRenderers[i] != null)
                        allRenderers[i].enabled = wasEnabled[i];

                AssetDatabase.Refresh();
            }
        }

        // ─── KB retrieval ─────────────────────────────────────────────────────

        private static async Task<List<RetrievedExample>> RetrieveExamplesAsync(
            string updateRequest, ShapeKnowledgeBase kb, string openAIKey)
        {
            var examples = new List<RetrievedExample>();
            var results  = await SemanticShapeSearch.SearchAsync(updateRequest, kb, openAIKey, topK: 3);

            foreach (var r in results)
            {
                if (!File.Exists(r.shape.filePath)) continue;
                examples.Add(new RetrievedExample
                {
                    componentRole           = "reference",
                    componentDescription    = updateRequest,
                    matchedShapeName        = r.shape.fileName,
                    matchedShapePrompt      = r.shape.originalPrompt,
                    matchedShapeDescription = r.shape.visualDescription,
                    hlslCode                = File.ReadAllText(r.shape.filePath),
                    similarityScore         = r.similarity
                });
                Debug.Log($"[Update Pipeline]   Retrieved: {r.shape.fileName} (sim={r.similarity:F3})");
            }
            return examples;
        }

        // ─── helpers ─────────────────────────────────────────────────────────

        /// Converts an Assets-relative path to an absolute filesystem path.
        /// File I/O (File.Exists, File.ReadAllBytes) needs absolute paths because
        /// Unity's CWD can shift after AssetDatabase.Refresh() / domain reloads.
        private static string ToAbsolutePath(string assetPath)
        {
            if (string.IsNullOrEmpty(assetPath)) return assetPath;
            if (Path.IsPathRooted(assetPath)) return assetPath;
            // Application.dataPath = "<ProjectRoot>/Assets"
            string projectRoot = Path.GetDirectoryName(Application.dataPath);
            return Path.GetFullPath(Path.Combine(projectRoot, assetPath));
        }

        // ─── VLM comparison evaluation ────────────────────────────────────────

        private static async Task<LLMMatchScoreResponse> EvaluateUpdateAsync(
            string updateRequest, string beforePath, string afterPath, string openAIKey)
        {
            string beforeAbs = ToAbsolutePath(beforePath);
            string afterAbs  = ToAbsolutePath(afterPath);

            if (string.IsNullOrEmpty(beforeAbs) || !File.Exists(beforeAbs))
            {
                Debug.LogWarning($"[Update Pipeline] No before image at '{beforeAbs}' — cannot compare. Returning mid score.");
                return new LLMMatchScoreResponse { score = 5, explanation = "No before image available." };
            }

            string json = await OpenAIApiService.CallOpenAIUpdateEvalAsync(
                updateRequest, beforeAbs, afterAbs, openAIKey);

            if (string.IsNullOrEmpty(json))
                return new LLMMatchScoreResponse { score = 0, explanation = "VLM evaluation failed." };

            try   { return JsonConvert.DeserializeObject<LLMMatchScoreResponse>(json); }
            catch { return new LLMMatchScoreResponse { score = 0, explanation = "Could not parse VLM response." }; }
        }

        // ─── helpers ──────────────────────────────────────────────────────────

        private static string StripMarkdown(string text)
        {
            if (string.IsNullOrEmpty(text)) return text;
            var m = Regex.Match(text, @"```(?:json)?\s*([\s\S]*?)```",
                                RegexOptions.Multiline);
            return m.Success ? m.Groups[1].Value.Trim() : text.Trim();
        }

        private static void EnsureDirectories()
        {
            if (!Directory.Exists(UPDATE_DIR))  Directory.CreateDirectory(UPDATE_DIR);
            if (!Directory.Exists(PREVIEW_DIR)) Directory.CreateDirectory(PREVIEW_DIR);
        }
    }
}