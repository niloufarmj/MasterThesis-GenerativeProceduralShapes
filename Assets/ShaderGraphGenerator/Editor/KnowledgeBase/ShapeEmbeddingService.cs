using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using UnityEngine;
using UnityEngine.Networking;
using Newtonsoft.Json;

namespace ShaderGraphGenerator.KnowledgeBase
{
    /// <summary>
    /// Service for generating embeddings using OpenAI API
    /// </summary>
    public static class ShapeEmbeddingService
    {
        private const string EMBEDDING_MODEL = "text-embedding-3-small";
        private const string OPENAI_URL = "https://api.openai.com/v1/embeddings";

        /// <summary>
        /// Generate embedding for a single text
        /// </summary>
        public static async Task<float[]> GenerateEmbeddingAsync(string text, string apiKey)
        {
            var requestBody = new
            {
                input = text,
                model = EMBEDDING_MODEL
            };

            string jsonBody = JsonConvert.SerializeObject(requestBody);
            byte[] bodyRaw = System.Text.Encoding.UTF8.GetBytes(jsonBody);

            using (UnityWebRequest www = new UnityWebRequest(OPENAI_URL, "POST"))
            {
                www.uploadHandler = new UploadHandlerRaw(bodyRaw);
                www.downloadHandler = new DownloadHandlerBuffer();
                www.SetRequestHeader("Content-Type", "application/json");
                www.SetRequestHeader("Authorization", $"Bearer {apiKey}");

                var op = www.SendWebRequest();
                while (!op.isDone)
                    await Task.Yield();

                if (www.result != UnityWebRequest.Result.Success)
                {
                    Debug.LogError($"OpenAI Embedding Error: {www.error}\n{www.downloadHandler.text}");
                    return null;
                }

                try
                {
                    var response = JsonConvert.DeserializeObject<OpenAIEmbeddingResponse>(www.downloadHandler.text);
                    return response.data[0].embedding;
                }
                catch (Exception ex)
                {
                    Debug.LogError($"Failed to parse embedding response: {ex.Message}");
                    return null;
                }
            }
        }

        /// <summary>
        /// Generate embeddings for multiple texts in batch
        /// </summary>
        public static async Task<List<float[]>> GenerateEmbeddingsBatchAsync(
            List<string> texts, 
            string apiKey,
            Action<int, int> progressCallback = null)
        {
            var embeddings = new List<float[]>();

            for (int i = 0; i < texts.Count; i++)
            {
                progressCallback?.Invoke(i + 1, texts.Count);

                var embedding = await GenerateEmbeddingAsync(texts[i], apiKey);
                embeddings.Add(embedding);

                // Small delay to avoid rate limits
                await Task.Delay(100);
            }

            return embeddings;
        }

        /// <summary>
        /// Create search text from shape metadata (what we'll embed)
        /// </summary>
        public static string CreateSearchableText(ShapeMetadata shape)
        {
            // Combine multiple fields for rich semantic search
            var parts = new List<string>();

            // Add original prompt
            if (!string.IsNullOrEmpty(shape.originalPrompt))
                parts.Add(shape.originalPrompt);

            // Add visual description
            if (!string.IsNullOrEmpty(shape.visualDescription))
                parts.Add(shape.visualDescription);

            // Add tags
            if (shape.tags != null && shape.tags.Count > 0)
                parts.Add(string.Join(", ", shape.tags));

            // Add category and complexity as context
            parts.Add($"Category: {shape.category}");
            parts.Add($"Complexity: {shape.complexity}");

            return string.Join(". ", parts);
        }

        [Serializable]
        private class OpenAIEmbeddingResponse
        {
            public List<EmbeddingData> data;
        }

        [Serializable]
        private class EmbeddingData
        {
            public float[] embedding;
        }
    }
}