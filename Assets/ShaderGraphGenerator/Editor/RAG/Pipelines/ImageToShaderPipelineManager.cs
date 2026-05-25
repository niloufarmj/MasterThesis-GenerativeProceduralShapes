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
    // ─── result data model ────────────────────────────────────────────────────

    public class ImageToShaderResult
    {
        public string absoluteImagePath;   // original reference image
        public string editableHints;       // user's editable-properties note
        public string visualDescription;   // GPT-4o's description of the image
        public string fileName;
        public string hlslCode;
        public List<LLMShaderProperty> properties;
        public string shaderGraphPath;
        public string materialPath;
        public string previewImagePath;    // rendered preview (abs path)
        public int    vlmScore;
        public string vlmFeedback;
        public bool   success;
        public string errorMessage;
    }

    // ─── pipeline ─────────────────────────────────────────────────────────────

    public static class ImageToShaderPipelineManager
    {
        private const string OUTPUT_DIR  = "Assets/ShaderGraphs/RAG_Generated";
        private const string PREVIEW_DIR = "Assets/ShaderGraphs/Previews";
        private const int    VLM_THRESHOLD = 7;

        /// <summary>
        /// Full image-to-shader pipeline:
        ///   1. GPT-4o Vision → structured visual description
        ///   2. Decompose description → retrieve KB examples
        ///   3. Gemini Vision (text + image) → HLSL + properties
        ///   4. Build ShaderGraph + Material, apply properties
        ///   5. Render preview → VLM compare (original image vs rendered preview)
        ///   6. Retry loop up to maxVlmIterations if score ≤ VLM_THRESHOLD
        /// </summary>
        public static async Task<ImageToShaderResult> RunPipelineAsync(
            string absoluteImagePath,
            string editableHints,
            ShapeKnowledgeBase knowledgeBase,
            ShaderGraphGeneratorConfig config,
            int maxVlmIterations = 2,
            bool usePixelation   = false,
            int  pixelCount      = 50)
        {
            var result = new ImageToShaderResult
            {
                absoluteImagePath = absoluteImagePath,
                editableHints     = editableHints
            };

            try
            {
                EnsureDirectories();

                if (!File.Exists(absoluteImagePath))
                {
                    result.errorMessage = $"Reference image not found: {absoluteImagePath}";
                    return result;
                }

                // ── Step 1: Describe the image ────────────────────────────────
                Debug.Log("[Img2Shader] Step 1: Describing image with GPT-4o Vision...");
                string description = await OpenAIApiService.CallOpenAIDescribeImageAsync(
                    absoluteImagePath, editableHints, config.openAIKey);

                if (string.IsNullOrEmpty(description))
                {
                    result.errorMessage = "Image description step failed (OpenAI Vision returned null).";
                    return result;
                }

                result.visualDescription = description;
                Debug.Log($"[Img2Shader] Description ({description.Length} chars) obtained.");

                // ── Pre-compute decomposition once (reused across all VLM iterations) ──
                // Decomposition is derived from the stable visual description of the reference image,
                // which never changes between iterations, so computing it once is correct.
                Debug.Log("[Img2Shader] Pre-computing decomposition (reused across all iterations)...");
                var cachedDecomposition = await ShapeDecompositionService.DecomposeShapeAsync(
                    description, knowledgeBase, config.geminiKey);

                if (cachedDecomposition == null)
                {
                    result.errorMessage = "Shape decomposition step failed.";
                    return result;
                }
                Debug.Log($"[Img2Shader] Decomposition complete: {cachedDecomposition.total_components} components.");

                // ── VLM iteration loop ────────────────────────────────────────
                string prevVlmFeedback = null;

                for (int iter = 1; iter <= maxVlmIterations; iter++)
                {
                    Debug.Log($"[Img2Shader] Generation iteration {iter}/{maxVlmIterations}...");

                    // ── Step 2+3: Retrieve + generate (decomposition and description are reused) ─────────────
                    var llmResponse = await RAGShapeGenerator.GenerateWithRAGFromImageAsync(
                        absoluteImagePath,
                        string.IsNullOrWhiteSpace(prevVlmFeedback)
                            ? editableHints
                            : editableHints + "\n\n[Previous attempt feedback]: " + prevVlmFeedback,
                        knowledgeBase,
                        config,
                        useTransparency: true,
                        cachedVisualDescription: description,
                        cachedDecomposition: cachedDecomposition);

                    if (llmResponse == null)
                    {
                        result.errorMessage = "LLM generation failed.";
                        return result;
                    }

                    result.fileName   = llmResponse.file_name;
                    result.hlslCode   = llmResponse.hlsl_code;
                    result.properties = llmResponse.properties;

                    // ── Step 4: Save HLSL + build ShaderGraph + Material ──────
                    string hlslPath = Path.Combine(OUTPUT_DIR, $"{llmResponse.file_name}.hlsl");
                    File.WriteAllText(hlslPath, llmResponse.hlsl_code);
                    AssetDatabase.Refresh();

                    string sgPath = Path.Combine(OUTPUT_DIR, $"{llmResponse.file_name}.shadergraph");
                    var functionInfo = ShaderGraphBuilder.BuildShaderGraphFromLLMResponse(
                        hlslPath, sgPath, useTransparency: true, usePixelation: usePixelation);
                    AssetDatabase.Refresh();
                    await Task.Delay(1200);
                    AssetDatabase.Refresh();
                    await Task.Delay(400);

                    var shader = AssetDatabase.LoadAssetAtPath<Shader>(sgPath);
                    if (shader == null)
                    {
                        Debug.LogWarning($"[Img2Shader] Shader not loaded on iter {iter}, skipping.");
                        continue;
                    }

                    string matPath = Path.Combine(OUTPUT_DIR, $"{llmResponse.file_name}.mat");
                    if (AssetDatabase.LoadAssetAtPath<UnityEngine.Object>(matPath) != null)
                        AssetDatabase.DeleteAsset(matPath);

                    var material = new Material(shader);
                    AssetDatabase.CreateAsset(material, matPath);
                    AssetDatabase.SaveAssets();
                    AssetDatabase.Refresh();

                    material = AssetDatabase.LoadAssetAtPath<Material>(matPath);

                    // Apply LLM-suggested property values
                    if (functionInfo != null)
                        MaterialPreviewHelper.SetRandomMaterialProperties(material, functionInfo);
                    if (llmResponse.properties != null)
                        MaterialPreviewHelper.SetDefaultMaterialProperties(material, llmResponse.properties);
                    if (usePixelation)
                    {
                        if (material.HasProperty("PixelCount"))
                            material.SetFloat("PixelCount", pixelCount);
                        else if (material.HasProperty("_PixelCount"))
                            material.SetFloat("_PixelCount", pixelCount);
                    }

                    EditorUtility.SetDirty(material);
                    AssetDatabase.SaveAssets();

                    result.shaderGraphPath = sgPath;
                    result.materialPath    = matPath;

                    // ── Step 5: Render preview ────────────────────────────────
                    string projectRoot   = Path.GetDirectoryName(Application.dataPath);
                    string previewRelative = Path.Combine(PREVIEW_DIR, $"{llmResponse.file_name}_preview_{iter}.png");
                    string previewAbs    = Path.GetFullPath(Path.Combine(projectRoot, previewRelative));
                    Directory.CreateDirectory(Path.GetDirectoryName(previewAbs));

                    bool rendered = await RenderMaterialAsync(material, previewAbs);
                    if (!rendered)
                    {
                        Debug.LogWarning($"[Img2Shader] Render failed on iter {iter}.");
                        continue;
                    }

                    result.previewImagePath = previewAbs;

                    // ── Step 6: VLM: compare original image vs preview ────────
                    Debug.Log("[Img2Shader] VLM comparing reference vs preview...");
                    var eval = await EvaluateAgainstReferenceAsync(
                        absoluteImagePath, previewAbs, description, config.openAIKey);

                    Debug.Log($"[Img2Shader] VLM score: {eval.score}/10 — {eval.explanation}");
                    result.vlmScore    = eval.score;
                    result.vlmFeedback = eval.explanation;

                    if (eval.score > VLM_THRESHOLD)
                    {
                        result.success = true;
                        Debug.Log($"[Img2Shader] ✓ Accepted at iteration {iter}.");
                        return result;
                    }

                    prevVlmFeedback = eval.explanation;
                }

                result.success      = false;
                result.errorMessage = $"VLM score never exceeded {VLM_THRESHOLD} in {maxVlmIterations} iterations.";
                return result;
            }
            catch (Exception ex)
            {
                result.errorMessage = ex.Message;
                Debug.LogError($"[Img2Shader] Exception: {ex.Message}\n{ex.StackTrace}");
                return result;
            }
        }

        // ─── VLM evaluation: reference image vs rendered preview ─────────────

        private static async Task<LLMMatchScoreResponse> EvaluateAgainstReferenceAsync(
            string referenceAbsPath,
            string previewAbsPath,
            string visualDescription,
            string openAIKey)
        {
            const string url = "https://api.openai.com/v1/chat/completions";

            if (!File.Exists(referenceAbsPath) || !File.Exists(previewAbsPath))
            {
                Debug.LogWarning("[Img2Shader VLM] Missing images for comparison.");
                return new LLMMatchScoreResponse { score = 5, explanation = "Missing images." };
            }

            string refUrl;
            string previewUrl;
            try
            {
                refUrl     = OpenAIApiService.ImageToResizedBase64Public(referenceAbsPath, 256);
                previewUrl = OpenAIApiService.ImageToResizedBase64Public(previewAbsPath,   256);
            }
            catch (Exception ex)
            {
                Debug.LogError($"[Img2Shader VLM] Image encode failed: {ex.Message}");
                return new LLMMatchScoreResponse { score = 0, explanation = "Image encode failed." };
            }

            string textContent =
                "You are evaluating how well a procedurally generated shader recreates a reference image.\n\n" +
                "Image 1 (REFERENCE): The original reference image the user provided.\n" +
                "Image 2 (RENDERED PREVIEW): The shader rendered as a 2D material on a quad.\n\n" +
                "Visual description of what was targeted:\n" + visualDescription.Substring(0, Math.Min(500, visualDescription.Length)) + "\n\n" +
                "Rate 1–10 how closely the rendered preview matches the reference image.\n" +
                "1 = completely wrong. 10 = near-perfect match in shape, color, and layout.\n\n" +
                "Focus on: overall shape accuracy, color match, component placement, proportions.\n" +
                "Ignore: anti-aliasing, minor pixel differences.\n\n" +
                "Return ONLY valid JSON: { \"score\": <int 1-10>, \"explanation\": \"short feedback\" }";

            var bodyObject = new
            {
                model = "gpt-4o",
                response_format = new { type = "json_object" },
                messages = new object[]
                {
                    new { role = "system", content = "You are a helpful assistant that only responds with valid JSON." },
                    new
                    {
                        role = "user",
                        content = new object[]
                        {
                            new { type = "text",      text = textContent },
                            new { type = "image_url", image_url = new { url = refUrl } },
                            new { type = "image_url", image_url = new { url = previewUrl } }
                        }
                    }
                }
            };

            string jsonBody = JsonConvert.SerializeObject(bodyObject);
            byte[] bodyRaw  = System.Text.Encoding.UTF8.GetBytes(jsonBody);

            using (var www = new UnityEngine.Networking.UnityWebRequest(url, "POST"))
            {
                www.uploadHandler   = new UnityEngine.Networking.UploadHandlerRaw(bodyRaw);
                www.downloadHandler = new UnityEngine.Networking.DownloadHandlerBuffer();
                www.SetRequestHeader("Content-Type",  "application/json");
                www.SetRequestHeader("Authorization", $"Bearer {openAIKey}");

                var op = www.SendWebRequest();
                while (!op.isDone) await Task.Yield();

                if (www.result != UnityEngine.Networking.UnityWebRequest.Result.Success)
                {
                    Debug.LogError($"[Img2Shader VLM] Error: {www.error}\n{www.downloadHandler.text}");
                    return new LLMMatchScoreResponse { score = 0, explanation = "VLM request failed." };
                }

                string raw = www.downloadHandler.text;
                Debug.Log($"[Img2Shader VLM] Raw (first 400): {raw.Substring(0, Math.Min(400, raw.Length))}");
                try
                {
                    var parsed = JsonConvert.DeserializeObject<dynamic>(raw);
                    if (parsed.error != null)
                    {
                        Debug.LogError($"[Img2Shader VLM] API error: {parsed.error.message}");
                        return new LLMMatchScoreResponse { score = 0, explanation = $"API error: {parsed.error.message}" };
                    }
                    return JsonConvert.DeserializeObject<LLMMatchScoreResponse>((string)parsed.choices[0].message.content);
                }
                catch (Exception ex)
                {
                    Debug.LogError($"[Img2Shader VLM] Parse error: {ex.Message}\n{raw}");
                    return new LLMMatchScoreResponse { score = 0, explanation = "Parse failed." };
                }
            }
        }

        // ─── render helper ────────────────────────────────────────────────────

        private static async Task<bool> RenderMaterialAsync(Material material, string absOutputPath)
        {
            var allRenderers = UnityEngine.Object.FindObjectsByType<Renderer>(FindObjectsSortMode.None);
            var wasEnabled   = new bool[allRenderers.Length];
            for (int i = 0; i < allRenderers.Length; i++)
            {
                wasEnabled[i]           = allRenderers[i].enabled;
                allRenderers[i].enabled = false;
            }

            GameObject quad     = null;
            GameObject cameraGO = null;
            Camera     cam      = null;
            RenderTexture rt    = null;
            Texture2D screenshot = null;

            try
            {
                quad = GameObject.CreatePrimitive(PrimitiveType.Quad);
                quad.name = $"Img2ShaderPreview — {material.name}";
                quad.GetComponent<Renderer>().material = material;
                quad.transform.SetPositionAndRotation(Vector3.zero, Quaternion.identity);
                quad.transform.localScale = Vector3.one;

                cameraGO = new GameObject("_Img2ShaderCamera");
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

                File.WriteAllBytes(absOutputPath, screenshot.EncodeToPNG());
                Debug.Log($"[Img2Shader] Preview saved: {absOutputPath}");
                return true;
            }
            catch (Exception ex)
            {
                Debug.LogError($"[Img2Shader] Render failed: {ex.Message}");
                return false;
            }
            finally
            {
                RenderTexture.active = null;
                if (cam != null) cam.targetTexture = null;
                if (rt != null) { rt.Release(); UnityEngine.Object.DestroyImmediate(rt); }
                if (screenshot != null) UnityEngine.Object.DestroyImmediate(screenshot);
                if (cameraGO != null) UnityEngine.Object.DestroyImmediate(cameraGO);
                if (quad != null) UnityEngine.Object.DestroyImmediate(quad);
                for (int i = 0; i < allRenderers.Length; i++)
                    if (allRenderers[i] != null) allRenderers[i].enabled = wasEnabled[i];
                AssetDatabase.Refresh();
            }
        }

        private static void EnsureDirectories()
        {
            if (!Directory.Exists(OUTPUT_DIR))  Directory.CreateDirectory(OUTPUT_DIR);
            if (!Directory.Exists(PREVIEW_DIR)) Directory.CreateDirectory(PREVIEW_DIR);
        }
    }
}