using System;
using System.Collections.Generic;
using System.IO;
using System.Threading.Tasks;
using Newtonsoft.Json;
using UnityEngine;
using UnityEngine.Networking;

namespace ShaderGraphGenerator.Editor
{
    /// <summary>
    /// OpenAI API calls: shape evaluation (VLM), before/after update evaluation,
    /// image description for the Image→Shader pipeline, and image resize utility.
    /// </summary>
    public static class OpenAIApiService
    {
        private const string URL = "https://api.openai.com/v1/chat/completions";

        // ═══════════════════════════════════════════════════════════════════════
        //  Image resize utility
        // ═══════════════════════════════════════════════════════════════════════

        /// <summary>
        /// Downsamples a PNG on disk to targetSize x targetSize and returns it as a base64 data-URL.
        /// Keeps the original file untouched.
        /// </summary>
        public static string ImageToResizedBase64Public(string absolutePath, int targetSize = 256)
            => ImageToResizedBase64(absolutePath, targetSize);

        private static string ImageToResizedBase64(string absolutePath, int targetSize = 256)
        {
            byte[] raw = File.ReadAllBytes(absolutePath);

            var src = new Texture2D(2, 2, TextureFormat.RGBA32, false);
            src.LoadImage(raw);

            int srcW = src.width;
            int srcH = src.height;
            Debug.Log($"[VLM Eval] Loaded image {absolutePath} ({srcW}x{srcH}), resampling to {targetSize}x{targetSize}");

            var dst       = new Texture2D(targetSize, targetSize, TextureFormat.RGBA32, false);
            var dstPixels = new Color[targetSize * targetSize];
            for (int y = 0; y < targetSize; y++)
            {
                for (int x = 0; x < targetSize; x++)
                {
                    int srcX = Mathf.Clamp(Mathf.RoundToInt((float)x / targetSize * srcW), 0, srcW - 1);
                    int srcY = Mathf.Clamp(Mathf.RoundToInt((float)y / targetSize * srcH), 0, srcH - 1);
                    dstPixels[y * targetSize + x] = src.GetPixel(srcX, srcY);
                }
            }
            dst.SetPixels(dstPixels);
            dst.Apply();

            byte[] pngBytes = dst.EncodeToPNG();
            UnityEngine.Object.DestroyImmediate(src);
            UnityEngine.Object.DestroyImmediate(dst);

            string b64 = Convert.ToBase64String(pngBytes);
            Debug.Log($"[VLM Eval] Resized PNG base64 length: {b64.Length} chars (~{b64.Length * 3 / 4 / 1024} KB)");
            return $"data:image/png;base64,{b64}";
        }

        // ═══════════════════════════════════════════════════════════════════════
        //  Shape evaluation (single image vs. user request)
        // ═══════════════════════════════════════════════════════════════════════

        /// <summary>
        /// Sends a single screenshot to GPT-4o Vision and rates how well the rendered
        /// shape matches the user's request. Returns JSON: { "score": 1-10, "explanation": "..." }
        /// </summary>
        public static async Task<string> CallOpenAIEvalAsync(
            string userPrompt,
            string hlslCode,
            List<LLMShaderProperty> properties,
            string previewPath,
            string apiKey)
        {
            if (!File.Exists(previewPath))
            {
                Debug.LogError($"Preview image not found at: {previewPath}");
                return null;
            }

            byte[] imageBytes = File.ReadAllBytes(previewPath);
            string dataUrl    = $"data:image/png;base64,{Convert.ToBase64String(imageBytes)}";

            string propertiesJson = properties != null
                ? JsonConvert.SerializeObject(properties, Formatting.Indented)
                : "[]";

            string textContent =
                "You are a visual evaluator for procedurally generated 2D shapes.\n\n" +
                "User requested shape:\n" + userPrompt + "\n\n" +
                "Using ONLY the attached image, rate from 1 to 10 how well the rendered shape matches the request.\n\n" +
                "Scoring guide:\n" +
                "  10 = shape is correct and clearly recognizable\n" +
                "   7 = shape is correct but has minor imperfections (slightly off proportions, thin border artifacts)\n" +
                "   4 = shape is partially recognizable but significantly wrong\n" +
                "   1 = completely wrong or blank\n\n" +
                "IMPORTANT: Ignore soft/anti-aliased edges, slight glow or blur around shape borders, and minor " +
                "color variations — these are normal shader rendering artifacts and should NOT reduce the score. " +
                "Focus only on whether the overall shape matches the request.\n\n" +
                "Return ONLY valid JSON: { \"score\": <integer 1-10>, \"explanation\": \"short explanation\" }";

            var bodyObject = new
            {
                model           = "gpt-4o",
                response_format = new { type = "json_object" },
                messages        = new object[]
                {
                    new {
                        role    = "system",
                        content = "You are a helpful assistant that only responds with valid, raw JSON. " +
                                  "Do not include markdown or any other text outside the JSON object."
                    },
                    new {
                        role    = "user",
                        content = new object[]
                        {
                            new { type = "text",      text = textContent },
                            new { type = "image_url", image_url = new { url = dataUrl } }
                        }
                    }
                }
            };

            return await PostAndExtractContentAsync(bodyObject, apiKey, "OpenAI Eval");
        }

        // ═══════════════════════════════════════════════════════════════════════
        //  Before/After update evaluation
        // ═══════════════════════════════════════════════════════════════════════

        /// <summary>
        /// Sends two screenshots (before/after) to GPT-4o Vision and asks whether
        /// the user's specific update request was applied.
        /// Returns JSON: { "score": 1-10, "explanation": "..." }
        /// </summary>
        public static async Task<string> CallOpenAIUpdateEvalAsync(
            string updateRequest,
            string beforeImagePath,
            string afterImagePath,
            string apiKey)
        {
            Debug.Log($"[VLM Eval] Starting evaluation. Before='{beforeImagePath}' After='{afterImagePath}'");

            if (!File.Exists(beforeImagePath))
            {
                Debug.LogError($"[VLM Eval] BEFORE image not found: '{beforeImagePath}'");
                return null;
            }
            if (!File.Exists(afterImagePath))
            {
                Debug.LogError($"[VLM Eval] AFTER image not found: '{afterImagePath}'");
                return null;
            }

            string beforeUrl, afterUrl;
            try
            {
                beforeUrl = ImageToResizedBase64(beforeImagePath, 256);
                afterUrl  = ImageToResizedBase64(afterImagePath,  256);
            }
            catch (Exception ex)
            {
                Debug.LogError($"[VLM Eval] Failed to encode images: {ex.Message}");
                return null;
            }

            string textContent =
                "You are evaluating whether a specific visual update was successfully applied to a 2D procedural shader.\n\n" +
                "Update request: \"" + updateRequest + "\"\n\n" +
                "Image 1 (BEFORE): The original shader before the update.\n" +
                "Image 2 (AFTER): The shader after the update was attempted.\n\n" +
                "Rate from 1 to 10 how well the requested update is visible in Image 2 compared to Image 1.\n" +
                "1 = no visible change, update not applied at all.\n" +
                "10 = the requested update is clearly and correctly visible.\n\n" +
                "Focus ONLY on whether the update request was applied — ignore unrelated visual differences.\n\n" +
                "Return ONLY valid JSON:\n" +
                "{ \"score\": <integer 1-10>, \"explanation\": \"short explanation\" }";

            var bodyObject = new
            {
                model           = "gpt-4o",
                response_format = new { type = "json_object" },
                messages        = new object[]
                {
                    new { role = "system", content = "You are a helpful assistant that only responds with valid, raw JSON." },
                    new
                    {
                        role    = "user",
                        content = new object[]
                        {
                            new { type = "text",      text = textContent },
                            new { type = "image_url", image_url = new { url = beforeUrl } },
                            new { type = "image_url", image_url = new { url = afterUrl  } }
                        }
                    }
                }
            };

            string jsonBody = JsonConvert.SerializeObject(bodyObject);
            byte[] bodyRaw  = System.Text.Encoding.UTF8.GetBytes(jsonBody);

            using (UnityWebRequest www = new UnityWebRequest(URL, "POST"))
            {
                www.uploadHandler   = new UploadHandlerRaw(bodyRaw);
                www.downloadHandler = new DownloadHandlerBuffer();
                www.SetRequestHeader("Content-Type",  "application/json");
                www.SetRequestHeader("Authorization", $"Bearer {apiKey}");

                var op = www.SendWebRequest();
                while (!op.isDone) await Task.Yield();

                if (www.result == UnityWebRequest.Result.ConnectionError ||
                    www.result == UnityWebRequest.Result.ProtocolError)
                {
                    Debug.LogError($"OpenAI Update Eval Error: {www.error}\n{www.downloadHandler.text}");
                    return null;
                }

                string rawResponse = www.downloadHandler.text;
                Debug.Log($"[VLM Eval] Raw response (first 800): {rawResponse.Substring(0, Math.Min(800, rawResponse.Length))}");
                try
                {
                    var parsed = JsonConvert.DeserializeObject<dynamic>(rawResponse);
                    if (parsed.error != null)
                    {
                        Debug.LogError($"[VLM Eval] OpenAI API error: {parsed.error.message} (type: {parsed.error.type})");
                        return null;
                    }
                    return (string)parsed.choices[0].message.content;
                }
                catch (Exception ex)
                {
                    Debug.LogError($"[VLM Eval] Parse error: {ex.Message}\nFull raw: {rawResponse}");
                    return null;
                }
            }
        }

        // ═══════════════════════════════════════════════════════════════════════
        //  Image description for decomposition
        // ═══════════════════════════════════════════════════════════════════════

        /// <summary>
        /// Sends an image to GPT-4o Vision and asks for a detailed structured description.
        /// The description feeds into decomposition + KB retrieval in the Image→Shader pipeline.
        /// userEditableHints: optional note about which properties should be editable.
        /// Returns plain-text structured description, or null on failure.
        /// </summary>
        public static async Task<string> CallOpenAIDescribeImageAsync(
            string absoluteImagePath,
            string userEditableHints,
            string apiKey)
        {
            if (!File.Exists(absoluteImagePath))
            {
                Debug.LogError($"[Image Describe] Image not found: {absoluteImagePath}");
                return null;
            }

            string dataUrl;
            try { dataUrl = ImageToResizedBase64(absoluteImagePath, 512); }
            catch (Exception ex)
            {
                Debug.LogError($"[Image Describe] Failed to encode: {ex.Message}");
                return null;
            }

            string hintsSection = string.IsNullOrWhiteSpace(userEditableHints)
                ? ""
                : $"\n\nThe user specifically wants these aspects to be editable shader properties: {userEditableHints}";

            string systemPrompt =
                "You are an expert at analyzing 2D illustrations and translating them into structured descriptions " +
                "for procedural shader generation. Be precise about shapes, colors, sizes, and spatial relationships.";

            string userPrompt =
                "Analyze this image and produce a detailed structured description for generating it as a 2D procedural HLSL shader.\n\n" +
                "Your description must cover:\n" +
                "1. OVERALL SHAPE: What is the subject? What is its overall silhouette?\n" +
                "2. COMPONENTS: List every distinct visual part (e.g. body, head, hat, scarf, arms, buttons). For each:\n" +
                "   - Geometric primitive it resembles (circle, rectangle, ellipse, triangle, etc.)\n" +
                "   - Approximate position relative to center (top-left, center, etc.)\n" +
                "   - Approximate relative size (small/medium/large fraction of whole)\n" +
                "   - Color (as RGB approximation or common name)\n" +
                "   - Any special visual effect (gradient, stripe, outline, etc.)\n" +
                "3. COLORS: List all distinct colors used with approximate RGB values\n" +
                "4. STYLE: Cartoon? Realistic? Flat? Outlined? Shadowed?\n" +
                "5. SHADER PARAMETERS: Based on the image and user hints, suggest which visual properties " +
                "would make the most useful editable shader parameters (e.g. body size, hat color, stripe count)." +
                hintsSection +
                "\n\nBe specific and thorough. This description will be used to generate HLSL shader code.";

            var bodyObject = new
            {
                model      = "gpt-4o",
                max_tokens = 1500,
                messages   = new object[]
                {
                    new { role = "system", content = systemPrompt },
                    new
                    {
                        role    = "user",
                        content = new object[]
                        {
                            new { type = "text",      text = userPrompt },
                            new { type = "image_url", image_url = new { url = dataUrl } }
                        }
                    }
                }
            };

            string jsonBody = JsonConvert.SerializeObject(bodyObject);
            byte[] bodyRaw  = System.Text.Encoding.UTF8.GetBytes(jsonBody);

            using (UnityWebRequest www = new UnityWebRequest(URL, "POST"))
            {
                www.uploadHandler   = new UploadHandlerRaw(bodyRaw);
                www.downloadHandler = new DownloadHandlerBuffer();
                www.SetRequestHeader("Content-Type",  "application/json");
                www.SetRequestHeader("Authorization", $"Bearer {apiKey}");

                var op = www.SendWebRequest();
                while (!op.isDone) await Task.Yield();

                if (www.result == UnityWebRequest.Result.ConnectionError ||
                    www.result == UnityWebRequest.Result.ProtocolError)
                {
                    Debug.LogError($"[Image Describe] OpenAI Error: {www.error}\n{www.downloadHandler.text}");
                    return null;
                }

                string raw = www.downloadHandler.text;
                Debug.Log($"[Image Describe] Raw response (first 300): {raw.Substring(0, Math.Min(300, raw.Length))}");
                try
                {
                    var parsed = JsonConvert.DeserializeObject<dynamic>(raw);
                    if (parsed.error != null)
                    {
                        Debug.LogError($"[Image Describe] OpenAI error: {parsed.error.message}");
                        return null;
                    }
                    return (string)parsed.choices[0].message.content;
                }
                catch (Exception ex)
                {
                    Debug.LogError($"[Image Describe] Parse error: {ex.Message}\nRaw: {raw}");
                    return null;
                }
            }
        }

        // ═══════════════════════════════════════════════════════════════════════
        //  Text generation (HLSL code generation)
        // ═══════════════════════════════════════════════════════════════════════

        /// <summary>
        /// Sends a text prompt to an OpenAI model and returns the raw response text.
        /// Used for HLSL shader code generation in the experiment pipeline.
        /// </summary>
        public static async Task<string> CallOpenAIGenerateAsync(string prompt, string apiKey, string model = "gpt-4.1")
        {
            var bodyObject = new
            {
                model,
                response_format = new { type = "json_object" },
                messages = new object[]
                {
                    new { role = "system", content = "You are a shader code generator. Respond only with valid JSON." },
                    new { role = "user",   content = prompt }
                }
            };
            return await PostAndExtractContentAsync(bodyObject, apiKey, $"OpenAI Generate ({model})");
        }

        // ─── shared POST helper ───────────────────────────────────────────────

        private static async Task<string> PostAndExtractContentAsync(object bodyObject, string apiKey, string tag)
        {
            string jsonBody = JsonConvert.SerializeObject(bodyObject);
            byte[] bodyRaw  = System.Text.Encoding.UTF8.GetBytes(jsonBody);

            using (UnityWebRequest www = new UnityWebRequest(URL, "POST"))
            {
                www.uploadHandler   = new UploadHandlerRaw(bodyRaw);
                www.downloadHandler = new DownloadHandlerBuffer();
                www.SetRequestHeader("Content-Type",  "application/json");
                www.SetRequestHeader("Authorization", $"Bearer {apiKey}");

                var op = www.SendWebRequest();
                while (!op.isDone) await Task.Yield();

                if (www.result == UnityWebRequest.Result.ConnectionError ||
                    www.result == UnityWebRequest.Result.ProtocolError)
                {
                    Debug.LogError($"{tag} API Error: {www.error}\n{www.downloadHandler.text}");
                    return null;
                }

                string rawResponse = www.downloadHandler.text;
                try
                {
                    var parsed = JsonConvert.DeserializeObject<dynamic>(rawResponse);
                    return (string)parsed.choices[0].message.content;
                }
                catch (Exception ex)
                {
                    Debug.LogError($"{tag}: Failed to parse response: {ex.Message}\nRaw: {rawResponse}");
                    return rawResponse;
                }
            }
        }
    }
}
