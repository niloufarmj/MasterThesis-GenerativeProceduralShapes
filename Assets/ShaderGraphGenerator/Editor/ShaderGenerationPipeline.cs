using System;
using System.Collections.Generic;
using System.IO;
using System.Threading.Tasks;
using Newtonsoft.Json;
using UnityEditor;
using UnityEngine;

namespace ShaderGraphGenerator.Editor
{
    /// <summary>
    /// Settings for the shader generation pipeline.
    /// </summary>
    public class GenerationSettings
    {
        public bool UseTransparency = true;
        public bool UsePixelation = false;
        public bool CreateMaterial = true;
        public bool CreatePreviewQuad = true;
        public bool CaptureScreenshot = true;
        
        public string HlslFolder = "Assets/ShaderGraphs/Generated/HLSL";
        public string GraphFolder = "Assets/ShaderGraphs/Generated/Graphs";
        public string PreviewFolder = "Assets/ShaderGraphs/Generated/Previews";
        public string SuccessFolder = "Assets/ShaderGraphs/SuccessfulResults";
    }

    /// <summary>
    /// Handles the complete shader generation pipeline:
    /// HLSL → ShaderGraph → Material → Preview → Evaluation
    /// </summary>
    public static class ShaderGenerationPipeline
    {
        public const int MaxIterations = 4;
        public const int SuccessThreshold = 7;

        // ═══════════════════════════════════════════════════════════════════════
        //  SINGLE PIPELINE EXECUTION
        // ═══════════════════════════════════════════════════════════════════════

        /// <summary>
        /// Executes a single pipeline iteration: HLSL → Graph → Material → Screenshot.
        /// Returns the path to the generated preview image.
        /// </summary>
        public static async Task<string> ExecutePipelineAsync(
            LLMShaderResponse llmResponse,
            GenerationSettings settings)
        {
            // 1. Write HLSL file
            string hlslPath = ShaderGraphGeneratorEditorUtility.CreateHLSLFile(
                llmResponse.file_name,
                llmResponse.hlsl_code,
                settings.HlslFolder
            );

            string hlslGuid = AssetDatabase.AssetPathToGUID(hlslPath);
            AssetDatabase.Refresh();

            // 2. Create ShaderGraph
            string graphPath = Path.Combine(settings.GraphFolder, llmResponse.file_name + ".shadergraph");
            HLSLFunctionInfo functionInfo = ShaderGraphJSONGenerator.GenerateFromHLSL(
                hlslPath,
                hlslGuid,
                graphPath,
                settings.UseTransparency,
                settings.UsePixelation
            );

            AssetDatabase.Refresh();

            // 3. Create Material
            Material mat = ShaderGraphGeneratorEditorUtility.CreateMaterialForShaderGraph(graphPath);
            if (mat == null)
                throw new Exception("Failed to create material.");

            // 4. Apply property defaults from LLM response
            ShaderGraphGeneratorEditorUtility.SetDefaultMaterialProperties(mat, llmResponse.properties);

            // Apply pixelation default if enabled
            if (settings.UsePixelation && mat.HasProperty("_PixelCount"))
            {
                mat.SetFloat("_PixelCount", 50.0f);
            }

            // 5. Check for shader compile errors
            if (ShaderGraphGeneratorEditorUtility.HasShaderCompileErrors(mat.shader))
                throw new Exception("Shader compile error detected.");

            // 6. Create preview and capture screenshot
            if (!Directory.Exists(settings.PreviewFolder))
                Directory.CreateDirectory(settings.PreviewFolder);

            string previewPath = Path.Combine(
                settings.PreviewFolder,
                $"{llmResponse.file_name}_{Guid.NewGuid()}.png"
            );

            GameObject quad = ShaderGraphGeneratorEditorUtility.CreatePreviewQuad(mat, true, previewPath);
            
            bool ready = await WaitForFileAsync(previewPath);
            if (!ready)
                throw new Exception("Screenshot was not produced within timeout.");

            return previewPath;
        }

        // ═══════════════════════════════════════════════════════════════════════
        //  ITERATIVE GENERATION WITH FEEDBACK
        // ═══════════════════════════════════════════════════════════════════════

        /// <summary>
        /// Result of a generation attempt.
        /// </summary>
        public class GenerationResult
        {
            public bool Success;
            public int FinalScore;
            public string Explanation;
            public LLMShaderResponse Response;
            public int IterationsUsed;
        }

        /// <summary>
        /// Runs the complete iterative generation loop with visual feedback.
        /// </summary>
        public static async Task<GenerationResult> GenerateWithFeedbackAsync(
            string userPrompt,
            GenerationSettings settings,
            ShaderGraphGeneratorConfig config,
            Action<int, string> onIterationStart = null)
        {
            string firstPrompt = ShaderGraphGeneratorEditorUtility.BuildLLMPrompt(userPrompt, settings.UseTransparency);
            string currentPrompt = firstPrompt;
            LLMShaderResponse llmResponse = null;

            for (int iteration = 1; iteration <= MaxIterations; iteration++)
            {
                onIterationStart?.Invoke(iteration, $"Iteration {iteration}/{MaxIterations}");
                Debug.Log($"=== ITERATION {iteration} ===");

                // 1. Call Gemini for code generation
                string jsonResponse = await LLMApiService.CallGeminiAsync(currentPrompt, config.geminiKey);
                if (string.IsNullOrEmpty(jsonResponse))
                {
                    Debug.LogError("Gemini returned null response.");
                    continue;
                }

                llmResponse = JsonConvert.DeserializeObject<LLMShaderResponse>(jsonResponse);

                // 2. Execute pipeline
                string previewPath;
                try
                {
                    previewPath = await ExecutePipelineAsync(llmResponse, settings);
                }
                catch (Exception ex)
                {
                    Debug.LogError($"Pipeline error: {ex.Message}");
                    continue;
                }

                // 3. Evaluate with vision model
                string evalJson = await LLMApiService.CallOpenAIEvalAsync(
                    userPrompt,
                    llmResponse.hlsl_code,
                    llmResponse.properties,
                    previewPath,
                    config.openAIKey
                );

                if (string.IsNullOrEmpty(evalJson))
                {
                    Debug.LogError("OpenAI evaluation returned null.");
                    continue;
                }

                var eval = JsonConvert.DeserializeObject<LLMMatchScoreResponse>(evalJson);
                Debug.Log($"Score = {eval.score}, Explanation = {eval.explanation}");

                // 4. Check for success
                if (eval.score >= SuccessThreshold)
                {
                    SaveSuccessfulResult(llmResponse, settings.SuccessFolder);
                    
                    return new GenerationResult
                    {
                        Success = true,
                        FinalScore = eval.score,
                        Explanation = eval.explanation,
                        Response = llmResponse,
                        IterationsUsed = iteration
                    };
                }

                // 5. Build refinement prompt for next iteration
                currentPrompt = ShaderGraphGeneratorEditorUtility.BuildRefinementPrompt(
                    firstPrompt,
                    llmResponse,
                    eval.explanation
                );
            }

            // Max iterations reached without success
            return new GenerationResult
            {
                Success = false,
                FinalScore = 0,
                Explanation = "Max iterations reached without achieving success threshold.",
                Response = llmResponse,
                IterationsUsed = MaxIterations
            };
        }

        // ═══════════════════════════════════════════════════════════════════════
        //  BATCH LIBRARY GENERATION
        // ═══════════════════════════════════════════════════════════════════════

        /// <summary>
        /// Generates shapes from a library file (one shape description per line).
        /// </summary>
        public static async Task RunLibraryGenerationAsync(
            string libraryFilePath,
            GenerationSettings settings,
            ShaderGraphGeneratorConfig config,
            Action<string, int, int> onShapeStart = null)
        {
            if (!File.Exists(libraryFilePath))
            {
                Debug.LogError($"Library file not found: {libraryFilePath}");
                return;
            }

            string[] lines = File.ReadAllLines(libraryFilePath);
            List<string> shapeRequests = new List<string>();

            foreach (string line in lines)
            {
                string trimmed = line.Trim();
                if (!string.IsNullOrEmpty(trimmed))
                    shapeRequests.Add(trimmed);
            }

            Debug.Log($"Loaded {shapeRequests.Count} shape definitions.");

            for (int i = 0; i < shapeRequests.Count; i++)
            {
                string request = shapeRequests[i];
                onShapeStart?.Invoke(request, i + 1, shapeRequests.Count);
                Debug.Log($"=== Processing shape {i + 1}/{shapeRequests.Count}: {request} ===");

                await GenerateWithFeedbackAsync(request, settings, config);
                
                DisableAllPreviewQuads();
            }

            Debug.Log("✓ Library generation completed.");
        }

        // ═══════════════════════════════════════════════════════════════════════
        //  HELPERS
        // ═══════════════════════════════════════════════════════════════════════

        private static void SaveSuccessfulResult(LLMShaderResponse response, string folder)
        {
            if (!Directory.Exists(folder))
                Directory.CreateDirectory(folder);

            string path = Path.Combine(folder, response.file_name + ".hlsl");
            File.WriteAllText(path, response.hlsl_code);
            AssetDatabase.ImportAsset(path);

            Debug.Log($"✓ Saved successful result to {path}");
        }

        private static async Task<bool> WaitForFileAsync(string path, float timeoutSeconds = 5f)
        {
            double start = EditorApplication.timeSinceStartup;
            path = path.Replace("\\", "/");

            while (!File.Exists(path) &&
                   EditorApplication.timeSinceStartup - start < timeoutSeconds)
            {
                await Task.Delay(200);
            }

            return File.Exists(path);
        }

        private static void DisableAllPreviewQuads()
        {
            foreach (var quad in GameObject.FindObjectsOfType<MeshRenderer>())
            {
                if (quad.name.Contains("Preview Quad"))
                    quad.gameObject.SetActive(false);
            }
        }
    }
}
