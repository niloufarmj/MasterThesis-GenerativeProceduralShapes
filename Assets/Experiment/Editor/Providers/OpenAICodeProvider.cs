using System;
using System.Threading.Tasks;
using UnityEngine.Networking;
using Newtonsoft.Json;

namespace ShaderGraphExperiments.Providers
{
    public class OpenAICodeProvider : ICodeProvider
    {
        public string Name => "OpenAI";
        private readonly string _apiKey;
        private readonly string _model;

        public OpenAICodeProvider(string apiKey, string model = "gpt-4o-mini")
        {
            _apiKey = apiKey;
            _model = model;
        }

        public Task<string> GenerateShaderJsonAsync(string prompt) => CallOpenAIAsync(prompt);
        public Task<string> RefineShaderJsonAsync(string refinementPrompt) => CallOpenAIAsync(refinementPrompt);

        private async Task<string> CallOpenAIAsync(string prompt)
        {
            string url = "https://api.openai.com/v1/chat/completions";

            var body = new
            {
                model = _model,
                response_format = new { type = "json_object" },
                messages = new object[]
                {
                    new { role = "system", content = "Return ONLY a valid raw JSON object." },
                    new { role = "user", content = prompt }
                }
            };

            byte[] raw = System.Text.Encoding.UTF8.GetBytes(JsonConvert.SerializeObject(body));

            using (UnityWebRequest www = new UnityWebRequest(url, "POST"))
            {
                www.uploadHandler = new UploadHandlerRaw(raw);
                www.downloadHandler = new DownloadHandlerBuffer();
                www.SetRequestHeader("Content-Type", "application/json");
                www.SetRequestHeader("Authorization", $"Bearer {_apiKey}");

                var op = www.SendWebRequest();
                while (!op.isDone) await Task.Yield();

                if (www.result != UnityWebRequest.Result.Success)
                    throw new Exception($"OpenAI API Error: {www.error}\n{www.downloadHandler.text}");

                dynamic parsed = JsonConvert.DeserializeObject(www.downloadHandler.text);
                return (string)parsed.choices[0].message.content;
            }
        }
    }
}
