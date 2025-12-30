using System;
using System.IO;
using System.Threading.Tasks;
using UnityEngine.Networking;
using Newtonsoft.Json;

namespace ShaderGraphExperiments.Providers
{
    public class OpenAIEvalProvider : IEvalProvider
    {
        public string Name => "OpenAI";
        private readonly string _apiKey;
        private readonly string _model;

        public OpenAIEvalProvider(string apiKey, string model = "gpt-4o")
        {
            _apiKey = apiKey;
            _model = model;
        }

        public async Task<string> EvaluateImageAsync(string userPrompt, string hlslCode, string propertiesJson, string previewPngPath)
        {
            string url = "https://api.openai.com/v1/chat/completions";

            byte[] imageBytes = File.ReadAllBytes(previewPngPath);
            string dataUrl = $"data:image/png;base64,{Convert.ToBase64String(imageBytes)}";

            string textContent =
                "You are a strict visual evaluator for procedurally generated shapes.\n\n" +
                "User requested shape:\n" + userPrompt + "\n\n" +
                "HLSL code:\n" + hlslCode + "\n\n" +
                "Properties:\n" + propertiesJson + "\n\n" +
                "Return ONLY valid JSON:\n" +
                "{ \"score\": <integer 1-10>, \"explanation\": \"short\" }";

            var body = new
            {
                model = _model,
                response_format = new { type = "json_object" },
                messages = new object[]
                {
                    new { role = "system", content = "Return ONLY valid raw JSON." },
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

            byte[] raw = System.Text.Encoding.UTF8.GetBytes(JsonConvert.SerializeObject(body));

            using (UnityWebRequest www = new UnityWebRequest(url, "POST"))
            {
                www.uploadHandler = new UploadHandlerRaw(raw);
                www.downloadHandler = new DownloadHandlerBuffer();

                www.SetRequestHeader("Content-Type", "application/json");
                www.SetRequestHeader("Authorization", $"Bearer {_apiKey}");

                var op = www.SendWebRequest();
                while (!op.isDone)
                    await Task.Yield();

                if (www.result != UnityWebRequest.Result.Success)
                    throw new Exception($"OpenAI Eval Error: {www.error}\n{www.downloadHandler.text}");

                dynamic parsed = JsonConvert.DeserializeObject(www.downloadHandler.text);
                return (string)parsed.choices[0].message.content;
            }
        }
    }
}
