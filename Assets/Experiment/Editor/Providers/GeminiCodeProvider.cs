using System;
using System.Threading.Tasks;
using UnityEngine.Networking;
using Newtonsoft.Json;

namespace ShaderGraphExperiments.Providers
{
    public class GeminiCodeProvider : ICodeProvider
    {
        public string Name => "Gemini";
        private readonly string _apiKey;
        private readonly string _model;

        public GeminiCodeProvider(string apiKey, string model = "gemini-3-pro-preview")
        {
            _apiKey = apiKey;
            _model = model;
        }

        public Task<string> GenerateShaderJsonAsync(string prompt) => CallGeminiAsync(prompt);
        public Task<string> RefineShaderJsonAsync(string refinementPrompt) => CallGeminiAsync(refinementPrompt);

        private async Task<string> CallGeminiAsync(string prompt)
        {
            string url = $"https://generativelanguage.googleapis.com/v1beta/models/{_model}:generateContent?key={_apiKey}";

            var bodyObj = new
            {
                contents = new object[]
                {
                    new { parts = new object[] { new { text = prompt } } }
                }
            };

            byte[] bodyRaw = System.Text.Encoding.UTF8.GetBytes(JsonConvert.SerializeObject(bodyObj));

            using (UnityWebRequest www = new UnityWebRequest(url, "POST"))
            {
                www.uploadHandler = new UploadHandlerRaw(bodyRaw);
                www.downloadHandler = new DownloadHandlerBuffer();
                www.SetRequestHeader("Content-Type", "application/json");

                var op = www.SendWebRequest();
                while (!op.isDone) await Task.Yield();

                if (www.result != UnityWebRequest.Result.Success)
                    throw new Exception($"Gemini API Error: {www.error}\n{www.downloadHandler.text}");

                dynamic parsed = JsonConvert.DeserializeObject(www.downloadHandler.text);
                return (string)parsed.candidates[0].content.parts[0].text;
            }
        }
    }
}
