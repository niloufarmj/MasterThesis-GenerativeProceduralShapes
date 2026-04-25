using System;
using System.Threading.Tasks;
using Newtonsoft.Json;
using UnityEngine;
using UnityEngine.Networking;

namespace ShaderGraphGenerator.Editor
{
    /// <summary>
    /// Claude (Anthropic) API calls: structured JSON output for HLSL generation.
    /// </summary>
    public static class ClaudeApiService
    {
        private const string URL   = "https://api.anthropic.com/v1/messages";
        private const string MODEL = "claude-sonnet-4-6";
        private const string BETA  = "structured-outputs-2025-11-13";

        /// <summary>
        /// Calls Claude with structured output enforced via JSON schema.
        /// Returns the raw JSON string matching the LLMShaderResponse schema.
        /// </summary>
        public static async Task<string> CallClaudeAsync(string prompt, string apiKey)
        {
            var schema = new
            {
                type = "object",
                properties = new
                {
                    file_name  = new { type = "string" },
                    hlsl_code  = new { type = "string" },
                    properties = new
                    {
                        type  = "array",
                        items = new
                        {
                            type       = "object",
                            properties = new
                            {
                                name          = new { type = "string" },
                                type          = new { type = "string" },
                                default_value = new
                                {
                                    type                 = "object",
                                    properties           = new { x = new { type = "number" }, y = new { type = "number" }, z = new { type = "number" }, w = new { type = "number" } },
                                    required             = new[] { "x", "y", "z", "w" },
                                    additionalProperties = false
                                }
                            },
                            required             = new[] { "name", "type", "default_value" },
                            additionalProperties = false
                        }
                    }
                },
                required             = new[] { "file_name", "hlsl_code", "properties" },
                additionalProperties = false
            };

            var bodyObject = new
            {
                model      = MODEL,
                max_tokens = 4096,
                messages   = new object[]
                {
                    new { role = "user", content = new object[] { new { type = "text", text = prompt } } }
                },
                output_format = new { type = "json_schema", schema = schema }
            };

            string jsonBody = JsonConvert.SerializeObject(bodyObject);
            byte[] raw      = System.Text.Encoding.UTF8.GetBytes(jsonBody);

            using (UnityWebRequest www = new UnityWebRequest(URL, "POST"))
            {
                www.uploadHandler   = new UploadHandlerRaw(raw);
                www.downloadHandler = new DownloadHandlerBuffer();
                www.SetRequestHeader("content-type",       "application/json");
                www.SetRequestHeader("x-api-key",          apiKey);
                www.SetRequestHeader("anthropic-version",  "2023-06-01");
                www.SetRequestHeader("anthropic-beta",     BETA);

                var op = www.SendWebRequest();
                while (!op.isDone) await Task.Yield();

                if (www.result != UnityWebRequest.Result.Success)
                {
                    Debug.LogError("Claude API Error: " + www.error + "\n" + www.downloadHandler.text);
                    return null;
                }

                var rawResponse = www.downloadHandler.text;
                dynamic parsed  = JsonConvert.DeserializeObject(rawResponse);
                return (string)parsed.content[0].text;
            }
        }
    }
}
