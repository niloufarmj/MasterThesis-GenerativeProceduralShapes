using System;
using System.IO;
using System.Threading.Tasks;
using Newtonsoft.Json;
using UnityEngine;
using UnityEngine.Networking;

namespace ShaderGraphGenerator.Editor
{
    /// <summary>
    /// Gemini API calls: text-only generation and image+text (vision) generation.
    /// </summary>
    public static class GeminiApiService
    {
        private const string DEFAULT_MODEL = "gemini-3-pro-preview";

        /// <summary>
        /// Calls Gemini with a text-only prompt. Used for HLSL code generation.
        /// </summary>
        public static async Task<string> CallGeminiAsync(string prompt, string apiKey, string model = DEFAULT_MODEL)
        {
            string url = $"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={apiKey}";

            var bodyObj = new
            {
                contents = new object[]
                {
                    new { parts = new object[] { new { text = prompt } } }
                }
            };

            string jsonBody = JsonConvert.SerializeObject(bodyObj);
            byte[] bodyRaw  = System.Text.Encoding.UTF8.GetBytes(jsonBody);

            using (UnityWebRequest www = new UnityWebRequest(url, "POST"))
            {
                www.uploadHandler   = new UploadHandlerRaw(bodyRaw);
                www.downloadHandler = new DownloadHandlerBuffer();
                www.SetRequestHeader("Content-Type", "application/json");

                var op = www.SendWebRequest();
                while (!op.isDone) await Task.Yield();

                if (www.result == UnityWebRequest.Result.ConnectionError ||
                    www.result == UnityWebRequest.Result.ProtocolError)
                {
                    Debug.LogError($"Gemini API Error: {www.error}\n{www.downloadHandler.text}");
                    return null;
                }

                string raw = www.downloadHandler.text;
                try
                {
                    dynamic parsed = JsonConvert.DeserializeObject(raw);
                    var parts = parsed.candidates[0].content.parts;
                    // gemini-3-pro-preview thinking mode puts reasoning in parts marked thought:true;
                    // the actual response is always the last non-thought part.
                    string result = null;
                    foreach (var part in parts)
                    {
                        bool isThought = part.thought != null && (bool)part.thought;
                        if (!isThought)
                            result = (string)part.text;
                    }
                    if (result == null) result = (string)parts[0].text;
                    // strip accidental markdown fences
                    result = StripMarkdownFences(result);
                    return result;
                }
                catch (Exception ex)
                {
                    Debug.LogError($"Gemini parse error: {ex.Message}\nRaw: {raw}");
                    return null;
                }
            }
        }

        private static string StripMarkdownFences(string text)
        {
            if (string.IsNullOrEmpty(text)) return text;
            text = text.Trim();
            if (text.StartsWith("```"))
            {
                int newline = text.IndexOf('\n');
                if (newline >= 0) text = text.Substring(newline + 1);
                if (text.EndsWith("```")) text = text.Substring(0, text.LastIndexOf("```")).TrimEnd();
            }
            return text.Trim();
        }

        /// <summary>
        /// Calls Gemini with a text prompt and an inline image (base64 PNG/JPEG).
        /// Used by the Image→Shader pipeline for direct visual generation.
        /// absoluteImagePath must be an absolute filesystem path.
        /// </summary>
        /// <summary>
        /// VLM eval: scores how well a rendered preview matches the user's shape request.
        /// Returns JSON: { "score": 1-10, "explanation": "..." }
        /// </summary>
        public static async Task<string> CallGeminiEvalAsync(
            string userPrompt,
            string hlslCode,
            string previewPath,
            string apiKey,
            string model = DEFAULT_MODEL)
        {
            if (!File.Exists(previewPath))
            {
                Debug.LogError($"[Gemini Eval] Preview not found: {previewPath}");
                return null;
            }

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

            string raw = await CallGeminiWithImageAsync(textContent, previewPath, apiKey, model);
            return raw;
        }

        public static async Task<string> CallGeminiWithImageAsync(
            string textPrompt,
            string absoluteImagePath,
            string apiKey,
            string model = DEFAULT_MODEL)
        {
            string url = $"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={apiKey}";

            if (!File.Exists(absoluteImagePath))
            {
                Debug.LogError($"[Gemini Vision] Image not found: {absoluteImagePath}");
                return null;
            }

            byte[] imgBytes = File.ReadAllBytes(absoluteImagePath);
            string b64      = Convert.ToBase64String(imgBytes);
            string mimeType = absoluteImagePath.ToLowerInvariant().EndsWith(".jpg") ||
                              absoluteImagePath.ToLowerInvariant().EndsWith(".jpeg")
                ? "image/jpeg" : "image/png";

            Debug.Log($"[Gemini Vision] Sending image ({imgBytes.Length / 1024} KB, {mimeType}) + prompt ({textPrompt.Length} chars)");

            var bodyObj = new
            {
                contents = new object[]
                {
                    new
                    {
                        parts = new object[]
                        {
                            new { text = textPrompt },
                            new { inline_data = new { mime_type = mimeType, data = b64 } }
                        }
                    }
                }
            };

            string jsonBody = JsonConvert.SerializeObject(bodyObj);
            byte[] bodyRaw  = System.Text.Encoding.UTF8.GetBytes(jsonBody);

            using (UnityWebRequest www = new UnityWebRequest(url, "POST"))
            {
                www.uploadHandler   = new UploadHandlerRaw(bodyRaw);
                www.downloadHandler = new DownloadHandlerBuffer();
                www.SetRequestHeader("Content-Type", "application/json");

                var op = www.SendWebRequest();
                while (!op.isDone) await Task.Yield();

                if (www.result == UnityWebRequest.Result.ConnectionError ||
                    www.result == UnityWebRequest.Result.ProtocolError)
                {
                    Debug.LogError($"[Gemini Vision] API Error: {www.error}\n{www.downloadHandler.text}");
                    return null;
                }

                string raw = www.downloadHandler.text;
                try
                {
                    dynamic parsed = JsonConvert.DeserializeObject(raw);
                    var parts = parsed.candidates[0].content.parts;
                    string result = null;
                    foreach (var part in parts)
                    {
                        bool isThought = part.thought != null && (bool)part.thought;
                        if (!isThought)
                            result = (string)part.text;
                    }
                    if (result == null) result = (string)parts[0].text;
                    return StripMarkdownFences(result);
                }
                catch (Exception ex)
                {
                    Debug.LogError($"[Gemini Vision] Parse error: {ex.Message}\nRaw: {raw.Substring(0, Math.Min(500, raw.Length))}");
                    return null;
                }
            }
        }
    }
}
