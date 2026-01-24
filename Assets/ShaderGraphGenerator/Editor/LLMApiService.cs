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
    /// Handles all LLM API communications (Gemini, OpenAI, Claude).
    /// Separates network logic from UI and generation logic.
    /// </summary>
    public static class LLMApiService
    {
        // ═══════════════════════════════════════════════════════════════════════
        //  GEMINI API
        // ═══════════════════════════════════════════════════════════════════════

        /// <summary>
        /// Calls Gemini API for HLSL code generation.
        /// </summary>
        public static async Task<string> CallGeminiAsync(string prompt, string apiKey)
        {
            const string model = "gemini-3-pro-preview";
            string url = $"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={apiKey}";

            var bodyObj = new
            {
                contents = new object[]
                {
                    new
                    {
                        parts = new object[]
                        {
                            new { text = prompt }
                        }
                    }
                }
            };

            string jsonBody = JsonConvert.SerializeObject(bodyObj);
            byte[] bodyRaw = System.Text.Encoding.UTF8.GetBytes(jsonBody);

            using (UnityWebRequest www = new UnityWebRequest(url, "POST"))
            {
                www.uploadHandler = new UploadHandlerRaw(bodyRaw);
                www.downloadHandler = new DownloadHandlerBuffer();
                www.SetRequestHeader("Content-Type", "application/json");

                var op = www.SendWebRequest();
                while (!op.isDone)
                    await Task.Yield();

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
                    string text = parsed.candidates[0].content.parts[0].text;
                    return text;
                }
                catch (Exception ex)
                {
                    Debug.LogError($"Gemini parse error: {ex.Message}\nRaw: {raw}");
                    return null;
                }
            }
        }

        // ═══════════════════════════════════════════════════════════════════════
        //  OPENAI API (Visual Evaluation)
        // ═══════════════════════════════════════════════════════════════════════

        /// <summary>
        /// Calls OpenAI Vision API to evaluate generated shape against user request.
        /// Returns a JSON string with score (1-10) and explanation.
        /// </summary>
        public static async Task<string> CallOpenAIEvalAsync(
            string userPrompt,
            string hlslCode,
            List<LLMShaderProperty> properties,
            string previewPath,
            string apiKey)
        {
            const string url = "https://api.openai.com/v1/chat/completions";

            if (!File.Exists(previewPath))
            {
                Debug.LogError($"Preview image not found at: {previewPath}");
                return null;
            }

            // Read and encode preview image
            byte[] imageBytes = File.ReadAllBytes(previewPath);
            string base64 = Convert.ToBase64String(imageBytes);
            string dataUrl = $"data:image/png;base64,{base64}";

            // Build evaluation prompt
            string propertiesJson = properties != null 
                ? JsonConvert.SerializeObject(properties, Formatting.Indented) 
                : "[]";

            string textContent =
                "You are a strict visual evaluator for procedurally generated shapes.\n\n" +
                "User requested shape (natural language):\n" +
                userPrompt + "\n\n" +
                "HLSL code that produced the image:\n" +
                hlslCode + "\n\n" +
                "Shader properties (name, type, default_value) used for this preview:\n" +
                propertiesJson + "\n\n" +
                "Using ONLY the attached image and this information, rate from 1 to 10 how well " +
                "the rendered image matches the user's request. 1 = completely wrong, 10 = perfect match.\n\n" +
                "Return ONLY valid JSON with this structure:\n" +
                "{ \"score\": <integer 1-10>, \"explanation\": \"short explanation\" }";

            var bodyObject = new
            {
                model = "gpt-4o",
                response_format = new { type = "json_object" },
                messages = new object[]
                {
                    new {
                        role = "system",
                        content = "You are a helpful assistant that only responds with valid, raw JSON. " +
                                "Do not include markdown or any other text outside the JSON object."
                    },
                    new {
                        role = "user",
                        content = new object[]
                        {
                            new { type = "text", text = textContent },
                            new { type = "image_url", image_url = new { url = dataUrl } }
                        }
                    }
                }
            };

            string jsonBody = JsonConvert.SerializeObject(bodyObject);
            byte[] bodyRaw = System.Text.Encoding.UTF8.GetBytes(jsonBody);

            using (UnityWebRequest www = new UnityWebRequest(url, "POST"))
            {
                www.uploadHandler = new UploadHandlerRaw(bodyRaw);
                www.downloadHandler = new DownloadHandlerBuffer();
                www.SetRequestHeader("Content-Type", "application/json");
                www.SetRequestHeader("Authorization", $"Bearer {apiKey}");

                var op = www.SendWebRequest();
                while (!op.isDone)
                    await Task.Yield();

                if (www.result == UnityWebRequest.Result.ConnectionError ||
                    www.result == UnityWebRequest.Result.ProtocolError)
                {
                    Debug.LogError($"OpenAI Eval API Error: {www.error}\n{www.downloadHandler.text}");
                    return null;
                }

                string rawResponse = www.downloadHandler.text;
                try
                {
                    var openAiResponse = JsonConvert.DeserializeObject<dynamic>(rawResponse);
                    string jsonContent = openAiResponse.choices[0].message.content;
                    return jsonContent;
                }
                catch (Exception ex)
                {
                    Debug.LogError($"Failed to parse OpenAI eval response: {ex.Message}\nRaw response: {rawResponse}");
                    return rawResponse;
                }
            }
        }

        // ═══════════════════════════════════════════════════════════════════════
        //  CLAUDE API (Alternative Generator)
        // ═══════════════════════════════════════════════════════════════════════

        /// <summary>
        /// Calls Claude API with structured output for HLSL generation.
        /// </summary>
        public static async Task<string> CallClaudeAsync(string prompt, string apiKey)
        {
            const string url = "https://api.anthropic.com/v1/messages";

            var schema = new
            {
                type = "object",
                properties = new
                {
                    file_name = new { type = "string" },
                    hlsl_code = new { type = "string" },
                    properties = new
                    {
                        type = "array",
                        items = new
                        {
                            type = "object",
                            properties = new
                            {
                                name = new { type = "string" },
                                type = new { type = "string" },
                                default_value = new
                                {
                                    type = "object",
                                    properties = new
                                    {
                                        x = new { type = "number" },
                                        y = new { type = "number" },
                                        z = new { type = "number" },
                                        w = new { type = "number" }
                                    },
                                    required = new[] { "x", "y", "z", "w" },
                                    additionalProperties = false
                                }
                            },
                            required = new[] { "name", "type", "default_value" },
                            additionalProperties = false
                        }
                    }
                },
                required = new[] { "file_name", "hlsl_code", "properties" },
                additionalProperties = false
            };

            var bodyObject = new
            {
                model = "claude-sonnet-4-5-20250929",
                max_tokens = 4096,
                messages = new object[]
                {
                    new {
                        role = "user",
                        content = new object[]
                        {
                            new { type = "text", text = prompt }
                        }
                    }
                },
                output_format = new
                {
                    type = "json_schema",
                    schema = schema
                },
                betas = new[] { "structured-outputs-2025-11-13" }
            };

            string jsonBody = JsonConvert.SerializeObject(bodyObject);
            byte[] raw = System.Text.Encoding.UTF8.GetBytes(jsonBody);

            using (UnityWebRequest www = new UnityWebRequest(url, "POST"))
            {
                www.uploadHandler = new UploadHandlerRaw(raw);
                www.downloadHandler = new DownloadHandlerBuffer();

                www.SetRequestHeader("content-type", "application/json");
                www.SetRequestHeader("x-api-key", apiKey);
                www.SetRequestHeader("anthropic-version", "2023-06-01");
                www.SetRequestHeader("anthropic-beta", "structured-outputs-2025-11-13");

                var op = www.SendWebRequest();
                while (!op.isDone)
                    await Task.Yield();

                if (www.result != UnityWebRequest.Result.Success)
                {
                    Debug.LogError("Claude API Error: " + www.error + "\n" + www.downloadHandler.text);
                    return null;
                }

                var rawResponse = www.downloadHandler.text;
                dynamic parsed = JsonConvert.DeserializeObject(rawResponse);
                string jsonText = parsed.content[0].text;

                return jsonText;
            }
        }
    }
}
