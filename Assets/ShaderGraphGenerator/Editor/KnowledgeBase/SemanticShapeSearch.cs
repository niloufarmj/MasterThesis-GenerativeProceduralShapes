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
        // Keywords that indicate a character/humanoid generation request.
        // When matched, base templates receive a similarity boost so they
        // surface at the top of search results.
        private static readonly HashSet<string> CharacterKeywords = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            "character", "person", "human", "figure", "mannequin", "humanoid",
            "robot", "knight", "warrior", "wizard", "hero", "avatar",
            "soldier", "player", "npc", "creature", "puppet"
        };

        /// <summary>
        /// Returns true when the query is asking for a character/humanoid shape.
        /// </summary>
        public static bool IsCharacterRequest(string query)
        {
            if (string.IsNullOrEmpty(query)) return false;
            foreach (var kw in CharacterKeywords)
                if (query.IndexOf(kw, StringComparison.OrdinalIgnoreCase) >= 0)
                    return true;
            return false;
        }

        /// <summary>
        /// Find most similar shapes to a query using cosine similarity.
        /// Base templates are boosted when the query is a character request.
        /// Shapes with priority > 0 receive an additional flat bonus.
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
            bool isCharacter = IsCharacterRequest(query);

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

                // Boost base templates for character requests (1.5× multiplier)
                if (shape.isBaseTemplate && isCharacter)
                    similarity = Mathf.Min(1f, similarity * 1.5f);

                // Flat priority bonus: each priority point adds 0.05 to similarity
                if (shape.priority > 0)
                    similarity = Mathf.Min(1f, similarity + shape.priority * 0.05f);

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