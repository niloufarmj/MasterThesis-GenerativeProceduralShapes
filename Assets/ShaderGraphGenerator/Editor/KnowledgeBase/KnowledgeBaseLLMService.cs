using System;
using System.Threading.Tasks;
using UnityEngine;
using UnityEngine.Networking;
using Newtonsoft.Json;

namespace ShaderGraphGenerator.KnowledgeBase
{
    /// <summary>
    /// LLM service for analyzing HLSL shapes and extracting rich metadata
    /// </summary>
    public static class KnowledgeBaseLLMService
    {
        /// <summary>
        /// Analyze an HLSL shape using LLM to extract detailed metadata
        /// </summary>
        public static async Task<LLMShapeAnalysis> AnalyzeShapeAsync(
            string hlslCode, 
            string originalPrompt, 
            string apiKey)
        {
            string prompt = BuildAnalysisPrompt(hlslCode, originalPrompt);
            string jsonResponse = await CallGeminiAsync(prompt, apiKey);

            if (string.IsNullOrEmpty(jsonResponse))
            {
                Debug.LogError("LLM returned null response");
                return null;
            }

            try
            {
                var analysis = JsonConvert.DeserializeObject<LLMShapeAnalysis>(jsonResponse);
                return analysis;
            }
            catch (Exception ex)
            {
                Debug.LogError($"Failed to parse LLM response: {ex.Message}\nResponse: {jsonResponse}");
                return null;
            }
        }

        private static string BuildAnalysisPrompt(string hlslCode, string originalPrompt)
        {
            return $@"You are analyzing a procedural 2D shape created using Signed Distance Functions (SDF) in HLSL.

**Original User Prompt (what the user requested):**
{originalPrompt}

**Generated HLSL Code:**
```hlsl
{hlslCode}
```

Your task is to analyze this shape and provide detailed metadata in JSON format.

**Instructions:**
1. **visual_description**: Write a DETAILED, comprehensive visual description of this shape (3-5 sentences). Describe:
   - What the shape looks like visually
   - Key geometric features (curves, angles, proportions)
   - Visual characteristics (smooth edges, sharp corners, etc.)
   - How parameters affect the appearance
   - Any notable mathematical or artistic qualities
   
   Do NOT write a short description. Be thorough and detailed.

2. **category**: Classify into ONE of these categories:
   - ""GeometricPrimitives"" (basic shapes: circle, square, triangle, polygon, rectangle, ellipse)
   - ""OrganicShapes"" (natural/flowing: heart, cloud, flower, leaf, blob, wave)
   - ""SymbolsAndIcons"" (recognizable symbols: star, gear, arrow, cross, checkmark, icon)
   - ""CompositeShapes"" (clearly built from multiple shapes combined together)

3. **complexity**: Classify the mathematical/code complexity:
   - ""Primitive"" (single basic SDF function, minimal operations)
   - ""Intermediate"" (2-3 SDF operations, some transformations)
   - ""Complex"" (4+ operations, advanced math, complex combinations)

4. **symmetry**: Identify symmetry type:
   - ""None"" (no symmetry)
   - ""Bilateral"" (mirror symmetry on one axis)
   - ""Radial"" (rotational symmetry around center)
   - ""Both"" (both bilateral and radial symmetry)

5. **tags**: Generate 5-10 descriptive tags (lowercase, single words or short phrases) that could help find this shape through search. Include:
   - Shape type keywords
   - Visual characteristics
   - Potential use cases
   - Style descriptors

**CRITICAL**: Return ONLY valid JSON with this EXACT structure:
{{
  ""visual_description"": ""detailed multi-sentence description here"",
  ""category"": ""GeometricPrimitives"",
  ""complexity"": ""Primitive"",
  ""symmetry"": ""Radial"",
  ""tags"": [""circle"", ""round"", ""basic"", ""ui"", ""icon""]
}}

Do NOT include markdown formatting, code blocks, or any text outside the JSON object.";
        }

        private static async Task<string> CallGeminiAsync(string prompt, string apiKey)
        {
            const string model = "gemini-3.1-pro-preview";
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
                    
                    // Clean up response (remove markdown if present)
                    text = text.Trim();
                    if (text.StartsWith("```json"))
                        text = text.Substring(7);
                    if (text.StartsWith("```"))
                        text = text.Substring(3);
                    if (text.EndsWith("```"))
                        text = text.Substring(0, text.Length - 3);
                    
                    return text.Trim();
                }
                catch (Exception ex)
                {
                    Debug.LogError($"Gemini parse error: {ex.Message}\nRaw: {raw}");
                    return null;
                }
            }
        }
    }
}