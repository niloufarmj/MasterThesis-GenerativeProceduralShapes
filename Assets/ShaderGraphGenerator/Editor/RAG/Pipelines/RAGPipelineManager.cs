using System;
using System.Collections.Generic;
using System.IO;
using System.Threading.Tasks;
using UnityEngine;
using UnityEditor;
using Newtonsoft.Json;
using ShaderGraphGenerator.KnowledgeBase;
using ShaderGraphGenerator.Editor;

namespace ShaderGraphGenerator.RAG
{
    /// <summary>
    /// Complete RAG pipeline: Decompose → Retrieve → Generate → Build → Render → Evaluate
    /// </summary>
    public static class RAGPipelineManager
    {
        private const string RAG_OUTPUT_DIR = "Assets/ShaderGraphs/RAG_Generated";
        private const string PREVIEW_DIR = "Assets/ShaderGraphs/Previews";

        /// <summary>
        /// Run complete RAG pipeline with visual feedback
        /// </summary>
        public static async Task<RAGPipelineResult> RunCompletePipelineAsync(
            string userRequest,
            ShapeKnowledgeBase knowledgeBase,
            ShaderGraphGeneratorConfig config,
            int maxIterations = 3)
        {
            var result = new RAGPipelineResult
            {
                userRequest = userRequest,
                success = false
            };

            try
            {
                // Ensure directories exist
                EnsureDirectoriesExist();

                // Step 1: RAG Generation (Decompose + Retrieve + LLM)
                Debug.Log($"[RAG Pipeline] Starting for: {userRequest}");
                var llmResponse = await RAGShapeGenerator.GenerateWithRAGAsync(
                    userRequest,
                    knowledgeBase,
                    config,
                    useTransparency: true
                );

                if (llmResponse == null)
                {
                    result.errorMessage = "LLM generation failed";
                    return result;
                }

                result.fileName = llmResponse.file_name;
                result.hlslCode = llmResponse.hlsl_code;
                result.properties = llmResponse.properties;

                // Step 2: Save HLSL
                string hlslPath = Path.Combine(RAG_OUTPUT_DIR, $"{llmResponse.file_name}.hlsl");
                File.WriteAllText(hlslPath, llmResponse.hlsl_code);
                AssetDatabase.Refresh();
                Debug.Log($"[RAG Pipeline] ✓ HLSL saved: {hlslPath}");

                // Step 3: Build ShaderGraph JSON
                Debug.Log("[RAG Pipeline] Building ShaderGraph JSON...");
                string sgPath = Path.Combine(RAG_OUTPUT_DIR, $"{llmResponse.file_name}.shadergraph");
                var functionInfo = ShaderGraphBuilder.BuildShaderGraphFromLLMResponse(hlslPath, sgPath, useTransparency: true);
                AssetDatabase.Refresh();
                Debug.Log($"[RAG Pipeline] ✓ ShaderGraph saved: {sgPath}");

                result.shaderGraphPath = sgPath;

                // Wait for Unity to import the ShaderGraph
                await Task.Delay(1000);
                AssetDatabase.Refresh();
                await Task.Delay(500);

                // Step 4: Create Material
                Debug.Log("[RAG Pipeline] Creating material...");
                var shader = AssetDatabase.LoadAssetAtPath<Shader>(sgPath);
                
                if (shader == null)
                {
                    result.errorMessage = "Failed to load generated ShaderGraph as Shader";
                    return result;
                }

                string matPath = Path.Combine(RAG_OUTPUT_DIR, $"{llmResponse.file_name}.mat");
                if (AssetDatabase.LoadAssetAtPath<UnityEngine.Object>(matPath) != null)
                    AssetDatabase.DeleteAsset(matPath);
                var material = new Material(shader);
                AssetDatabase.CreateAsset(material, matPath);
                AssetDatabase.SaveAssets();
                AssetDatabase.Refresh();

                // Apply random sensible defaults first, then overlay with LLM values
                if (functionInfo != null)
                    MaterialPreviewHelper.SetRandomMaterialProperties(material, functionInfo);
                MaterialPreviewHelper.SetDefaultMaterialProperties(material, llmResponse.properties);

                Debug.Log($"[RAG Pipeline] ✓ Material created: {matPath}");

                result.materialPath = matPath;

                // Step 5: Apply to Quad and Render Preview
                Debug.Log("[RAG Pipeline] Rendering preview...");
                string previewPath = Path.Combine(PREVIEW_DIR, $"{llmResponse.file_name}_{maxIterations}.png");
                
                bool renderSuccess = await RenderPreviewAsync(material, previewPath);
                
                if (!renderSuccess)
                {
                    result.errorMessage = "Preview rendering failed";
                    return result;
                }

                result.previewImagePath = previewPath;
                Debug.Log($"[RAG Pipeline] ✓ Preview rendered: {previewPath}");

                // Step 6: VLM Visual Evaluation
                Debug.Log("[RAG Pipeline] Evaluating with VLM...");
                var evaluation = await EvaluateWithVLMAsync(
                    userRequest,
                    llmResponse.hlsl_code,
                    llmResponse.properties,
                    previewPath,
                    config.openAIKey
                );

                result.vmlScore = evaluation.score;
                result.vmlFeedback = evaluation.explanation;
                result.success = evaluation.score >= 7;

                Debug.Log($"[RAG Pipeline] ✓ VLM Score: {evaluation.score}/10");
                Debug.Log($"[RAG Pipeline] ✓ Feedback: {evaluation.explanation}");

                // Step 7: Iterative Refinement (if needed and iterations left)
                if (!result.success && maxIterations > 1)
                {
                    Debug.Log($"[RAG Pipeline] Score below threshold, refining... (iterations left: {maxIterations - 1})");
                    
                    // Build refinement prompt
                    string refinementRequest = BuildRefinementPrompt(userRequest, evaluation.explanation);
                    
                    // Recursive call with reduced iterations
                    return await RunCompletePipelineAsync(
                        refinementRequest,
                        knowledgeBase,
                        config,
                        maxIterations - 1
                    );
                }

                return result;
            }
            catch (Exception ex)
            {
                result.success = false;
                result.errorMessage = ex.Message;
                Debug.LogError($"[RAG Pipeline] Error: {ex.Message}\n{ex.StackTrace}");
                return result;
            }
        }

        /// <summary>
        /// Creates a quad in the active scene with the material applied, hides every other
        /// renderer, renders a clean off-screen screenshot onto a white background,
        /// then restores the scene. The quad stays in the scene so the user can inspect it.
        /// </summary>
        private static async Task<bool> RenderPreviewAsync(Material material, string outputPath)
        {
            // Hide all pre-existing renderers so the screenshot shows only this shape.
            var allRenderers = UnityEngine.Object.FindObjectsByType<Renderer>(FindObjectsSortMode.None);
            var wasEnabled = new bool[allRenderers.Length];
            for (int i = 0; i < allRenderers.Length; i++)
            {
                wasEnabled[i] = allRenderers[i].enabled;
                allRenderers[i].enabled = false;
            }

            GameObject cameraGO  = null;
            Camera     cam       = null;
            RenderTexture rt     = null;
            Texture2D screenshot = null;

            try
            {
                // ── Create quad in scene (stays after this method returns) ──────
                GameObject quad = GameObject.CreatePrimitive(PrimitiveType.Quad);
                quad.name = $"RAG Preview — {material.name}";
                quad.GetComponent<Renderer>().material = material;
                quad.transform.position = Vector3.zero;
                quad.transform.rotation = Quaternion.identity;
                quad.transform.localScale = Vector3.one;

                // Frame it in the Scene View so the user sees it
                Selection.activeGameObject = quad;
                if (SceneView.lastActiveSceneView != null)
                    SceneView.lastActiveSceneView.FrameSelected();

                // ── Off-screen camera (destroyed after render) ────────────────
                cameraGO = new GameObject("_RAGPreviewCamera");
                cam      = cameraGO.AddComponent<Camera>();
                cam.transform.position    = new Vector3(0f, 0f, -2f);
                cam.transform.LookAt(quad.transform);
                cam.clearFlags            = CameraClearFlags.SolidColor;
                cam.backgroundColor       = Color.white;
                cam.orthographic          = true;
                cam.orthographicSize      = 0.55f;
                cam.cullingMask           = 1 << quad.layer; // only render the quad's layer

                rt             = new RenderTexture(512, 512, 24);
                cam.targetTexture = rt;

                // Let Unity finish one frame so the material compiles
                await Task.Delay(100);

                cam.Render();

                // ── Read pixels ───────────────────────────────────────────────
                RenderTexture.active = rt;
                screenshot = new Texture2D(512, 512, TextureFormat.RGBA32, false);
                screenshot.ReadPixels(new Rect(0, 0, 512, 512), 0, 0);
                screenshot.Apply();

                // Composite over white so transparent areas become white
                var pixels = screenshot.GetPixels32();
                for (int i = 0; i < pixels.Length; i++)
                {
                    float a  = pixels[i].a / 255f;
                    pixels[i].r = (byte)(pixels[i].r * a + 255 * (1f - a));
                    pixels[i].g = (byte)(pixels[i].g * a + 255 * (1f - a));
                    pixels[i].b = (byte)(pixels[i].b * a + 255 * (1f - a));
                    pixels[i].a = 255;
                }
                screenshot.SetPixels32(pixels);
                screenshot.Apply();

                File.WriteAllBytes(outputPath, screenshot.EncodeToPNG());
                Debug.Log($"[RAG Pipeline] Screenshot saved: {outputPath}");

                return true;
            }
            catch (Exception ex)
            {
                Debug.LogError($"[RAG Pipeline] Render preview failed: {ex.Message}\n{ex.StackTrace}");
                return false;
            }
            finally
            {
                // ── Cleanup: destroy only the temporary camera & GPU resources ──
                RenderTexture.active = null;
                // Detach RT from camera before releasing to avoid Unity warning.
                if (cam != null) cam.targetTexture = null;
                if (rt != null)         { rt.Release(); UnityEngine.Object.DestroyImmediate(rt); }
                if (screenshot != null) { UnityEngine.Object.DestroyImmediate(screenshot); }
                if (cameraGO != null)   { UnityEngine.Object.DestroyImmediate(cameraGO); }

                // ── Restore all pre-existing renderers ────────────────────────
                for (int i = 0; i < allRenderers.Length; i++)
                {
                    if (allRenderers[i] != null)
                        allRenderers[i].enabled = wasEnabled[i];
                }

                AssetDatabase.Refresh();
            }
        }

        /// <summary>
        /// Evaluate rendered preview with VLM
        /// </summary>
        private static async Task<LLMMatchScoreResponse> EvaluateWithVLMAsync(
            string userRequest,
            string hlslCode,
            List<LLMShaderProperty> properties,
            string imagePath,
            string openAiApiKey)
        {
            string evaluationResponse = await OpenAIApiService.CallOpenAIEvalAsync(
                userRequest,
                hlslCode,
                properties,
                imagePath,
                openAiApiKey
            );

            if (string.IsNullOrEmpty(evaluationResponse))
            {
                return new LLMMatchScoreResponse { score = 0, explanation = "VLM evaluation failed" };
            }

            try
            {
                return JsonConvert.DeserializeObject<LLMMatchScoreResponse>(evaluationResponse);
            }
            catch
            {
                return new LLMMatchScoreResponse { score = 0, explanation = "Failed to parse VLM response" };
            }
        }

        /// <summary>
        /// Build refinement prompt based on VLM feedback
        /// </summary>
        private static string BuildRefinementPrompt(string originalRequest, string feedback)
        {
            return $"{originalRequest}\n\nPrevious attempt feedback: {feedback}\nPlease address these issues in the refined version.";
        }

        /// <summary>
        /// Ensure output directories exist
        /// </summary>
        private static void EnsureDirectoriesExist()
        {
            if (!Directory.Exists(RAG_OUTPUT_DIR))
                Directory.CreateDirectory(RAG_OUTPUT_DIR);

            if (!Directory.Exists(PREVIEW_DIR))
                Directory.CreateDirectory(PREVIEW_DIR);
        }
    }

    /// <summary>
    /// Result of complete RAG pipeline execution
    /// </summary>
    [Serializable]
    public class RAGPipelineResult
    {
        public string userRequest;
        public bool success;
        public string errorMessage;
        
        public string fileName;
        public string hlslCode;
        public List<LLMShaderProperty> properties;
        public string shaderGraphPath;
        public string materialPath;
        public string previewImagePath;

        public int vmlScore;
        public string vmlFeedback;
    }
}