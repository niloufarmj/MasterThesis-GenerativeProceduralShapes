using System;
using System.Threading.Tasks;
using Newtonsoft.Json;
using UnityEngine;
using UnityEngine.Networking;

namespace ShaderGraphGenerator.Editor
{
    /// <summary>
    /// Moonshot AI (Kimi) API calls. Uses the OpenAI-compatible endpoint.
    /// </summary>
    public static class KimiApiService
    {
        private const string URL = "https://api.moonshot.cn/v1/chat/completions";

        /// <summary>
        /// Sends a text prompt to a Kimi model and returns the raw response text.
        /// Used for HLSL shader code generation in the experiment pipeline.
        /// </summary>
        public static async Task<string> CallKimiAsync(string prompt, string apiKey, string model = "kimi-k2.6")
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
                    Debug.LogError($"[Kimi] API Error: {www.error}\n{www.downloadHandler.text}");
                    return null;
                }

                string raw = www.downloadHandler.text;
                try
                {
                    dynamic parsed = JsonConvert.DeserializeObject(raw);
                    if (parsed.error != null)
                    {
                        Debug.LogError($"[Kimi] API error: {parsed.error.message}");
                        return null;
                    }
                    return (string)parsed.choices[0].message.content;
                }
                catch (Exception ex)
                {
                    Debug.LogError($"[Kimi] Parse error: {ex.Message}\nRaw: {raw}");
                    return null;
                }
            }
        }
    }
}
