using System;
using System.Collections.Generic;
using System.Linq;
using UnityEngine;

namespace ShaderGraphGenerator.KnowledgeBase
{
    /// <summary>
    /// Semantic search over shape knowledge base using embeddings
    /// </summary>
    public static class SemanticShapeSearch
    {
        /// <summary>
        /// Find most similar shapes to a query using cosine similarity
        /// </summary>
        public static List<ShapeSearchResult> Search(
            string query,
            float[] queryEmbedding,
            ShapeKnowledgeBase knowledgeBase,
            int topK = 5,
            ShapeCategory? categoryFilter = null,
            ComplexityLevel? maxComplexity = null)
        {
            var results = new List<ShapeSearchResult>();

            foreach (var shape in knowledgeBase.shapes)
            {
                // Skip if no embedding
                if (shape.embedding == null || shape.embedding.Length == 0)
                    continue;

                // Apply filters
                if (categoryFilter.HasValue && shape.category != categoryFilter.Value)
                    continue;

                if (maxComplexity.HasValue && shape.complexity > maxComplexity.Value)
                    continue;

                // Calculate cosine similarity
                float similarity = CosineSimilarity(queryEmbedding, shape.embedding);

                results.Add(new ShapeSearchResult
                {
                    shape = shape,
                    similarity = similarity
                });
            }

            // Sort by similarity (descending) and return top K
            return results
                .OrderByDescending(r => r.similarity)
                .Take(topK)
                .ToList();
        }

        /// <summary>
        /// Search with automatic query embedding
        /// </summary>
        public static async System.Threading.Tasks.Task<List<ShapeSearchResult>> SearchAsync(
            string query,
            ShapeKnowledgeBase knowledgeBase,
            string openAiApiKey,
            int topK = 5,
            ShapeCategory? categoryFilter = null,
            ComplexityLevel? maxComplexity = null)
        {
            // Generate embedding for query
            float[] queryEmbedding = await ShapeEmbeddingService.GenerateEmbeddingAsync(query, openAiApiKey);

            if (queryEmbedding == null)
            {
                Debug.LogError("Failed to generate query embedding");
                return new List<ShapeSearchResult>();
            }

            return Search(query, queryEmbedding, knowledgeBase, topK, categoryFilter, maxComplexity);
        }

        /// <summary>
        /// Multi-query search: decompose complex request into multiple component searches
        /// </summary>
        public static async System.Threading.Tasks.Task<Dictionary<string, List<ShapeSearchResult>>> MultiQuerySearchAsync(
            List<string> componentQueries,
            ShapeKnowledgeBase knowledgeBase,
            string openAiApiKey,
            int topKPerQuery = 3)
        {
            var results = new Dictionary<string, List<ShapeSearchResult>>();

            foreach (string query in componentQueries)
            {
                var searchResults = await SearchAsync(query, knowledgeBase, openAiApiKey, topKPerQuery);
                results[query] = searchResults;
            }

            return results;
        }

        /// <summary>
        /// Calculate cosine similarity between two vectors
        /// </summary>
        private static float CosineSimilarity(float[] a, float[] b)
        {
            if (a.Length != b.Length)
            {
                Debug.LogError($"Vector dimension mismatch: {a.Length} vs {b.Length}");
                return 0f;
            }

            float dotProduct = 0f;
            float normA = 0f;
            float normB = 0f;

            for (int i = 0; i < a.Length; i++)
            {
                dotProduct += a[i] * b[i];
                normA += a[i] * a[i];
                normB += b[i] * b[i];
            }

            if (normA == 0f || normB == 0f)
                return 0f;

            return dotProduct / (Mathf.Sqrt(normA) * Mathf.Sqrt(normB));
        }

        /// <summary>
        /// Get diverse results (avoid too many similar shapes)
        /// </summary>
        public static List<ShapeSearchResult> GetDiverseResults(
            List<ShapeSearchResult> results,
            int count,
            float diversityThreshold = 0.9f)
        {
            var diverse = new List<ShapeSearchResult>();
            
            foreach (var result in results)
            {
                if (diverse.Count >= count)
                    break;

                // Check if too similar to already selected shapes
                bool tooSimilar = false;
                foreach (var selected in diverse)
                {
                    if (result.shape.embedding != null && selected.shape.embedding != null)
                    {
                        float sim = CosineSimilarity(result.shape.embedding, selected.shape.embedding);
                        if (sim > diversityThreshold)
                        {
                            tooSimilar = true;
                            break;
                        }
                    }
                }

                if (!tooSimilar)
                    diverse.Add(result);
            }

            return diverse;
        }
    }

    /// <summary>
    /// Search result with similarity score
    /// </summary>
    [Serializable]
    public class ShapeSearchResult
    {
        public ShapeMetadata shape;
        public float similarity; // 0-1, higher is better

        public override string ToString()
        {
            return $"{shape.fileName} (similarity: {similarity:F3})";
        }
    }
}