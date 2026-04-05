using System;
using System.Collections.Generic;
using System.IO;
using System.Threading.Tasks;
using UnityEngine;
using UnityEditor;
using ShaderGraphGenerator.KnowledgeBase;
using ShaderGraphGenerator.Editor;

namespace ShaderGraphGenerator.RAG
{
    // ─── LLM Response Model ───────────────────────────────────────────────────

    [Serializable]
    public class LLMAnimationResponse
    {
        public string file_name;
        public string cs_code;
        public string animation_summary;
        public List<string> properties_used   = new List<string>();
        public List<string> animation_tags    = new List<string>();
        // New shader properties the animation needs but that don't yet exist on the material.
        // Only populated when allowNewProperties=true in the prompt.
        public List<LLMShaderProperty> new_properties = new List<LLMShaderProperty>();
    }

    // ─── Material Property Info ───────────────────────────────────────────────

    public class MaterialPropertyInfo
    {
        public string name;
        public string type;          // "float", "color", "vector"
        public string currentValue;
    }

    // ─── Pipeline Result ──────────────────────────────────────────────────────

    public class AnimationPipelineResult
    {
        public string animationRequest;
        public string sourceMaterialName;
        public string fileName;
        public string csCode;
        public string scriptAssetPath;
        public string animationSummary;
        public List<string> propertiesUsed;
        public List<string> tags;
        public bool   success;
        public string errorMessage;
        public ShapeMetadata matchedShape;       // non-null if material found in KB
        // Set when new properties were added to the shader via the update pipeline
        public bool   newPropertiesAdded;
        public List<LLMShaderProperty> addedProperties;
        public string updatedMaterialPath;       // path to the new material after HLSL update
    }

    // ─── Animation KB Helper ──────────────────────────────────────────────────

    /// <summary>
    /// Helpers for AnimatorEntry items stored inside ShapeMetadata.animators.
    /// No separate KB file — everything lives in shape_metadata.json.
    /// </summary>
    public static class AnimationKBHelper
    {
        private const string KB_PATH = "Assets/ShaderGraphGenerator/KnowledgeBase/shape_metadata.json";

        // ── Shape matching ────────────────────────────────────────────────────

        /// <summary>
        /// Finds the KB shape matching a material by name/shader comparison.
        /// Returns null if not in KB.
        /// </summary>
        public static ShapeMetadata FindMatchingShape(Material material, ShapeKnowledgeBase kb)
        {
            if (material == null || kb == null) return null;

            string matName    = material.name;
            string shaderName = material.shader != null ? material.shader.name : "";
            string shaderBase = Path.GetFileNameWithoutExtension(shaderName);

            foreach (var shape in kb.shapes)
            {
                if (string.Equals(shape.fileName, matName,    StringComparison.OrdinalIgnoreCase)) return shape;
                if (string.Equals(shape.fileName, shaderBase, StringComparison.OrdinalIgnoreCase)) return shape;
                if (matName.StartsWith(shape.fileName,    StringComparison.OrdinalIgnoreCase))     return shape;
                if (!string.IsNullOrEmpty(shaderBase) &&
                    shaderBase.IndexOf(shape.fileName, StringComparison.OrdinalIgnoreCase) >= 0)   return shape;
            }
            return null;
        }

        // ── Cross-shape animation retrieval ───────────────────────────────────

        public static async Task<List<(AnimatorEntry entry, ShapeMetadata shape, float similarity)>>
            SearchAnimationsAsync(string query, ShapeKnowledgeBase kb, string openAIKey, int topK = 2)
        {
            var results = new List<(AnimatorEntry entry, ShapeMetadata shape, float similarity)>();
            if (kb == null) return results;

            var candidates = new List<(AnimatorEntry, ShapeMetadata)>();
            foreach (var shape in kb.shapes)
                foreach (var anim in shape.animators)
                    if (anim.embedding != null && anim.embedding.Length > 0)
                        candidates.Add((anim, shape));

            if (candidates.Count == 0) return results;

            float[] queryEmb = await ShapeEmbeddingService.GenerateEmbeddingAsync(query, openAIKey);
            if (queryEmb == null) return results;

            foreach (var (anim, shape) in candidates)
                results.Add((anim, shape, CosineSimilarity(queryEmb, anim.embedding)));

            results.Sort((a, b) => b.similarity.CompareTo(a.similarity));
            return results.Count > topK ? results.GetRange(0, topK) : results;
        }

        // ── Save animator to shape ────────────────────────────────────────────

        public static async Task SaveAnimatorToShapeAsync(
            AnimatorEntry entry, ShapeMetadata shape, ShapeKnowledgeBase kb, string openAIKey)
        {
            if (!string.IsNullOrEmpty(openAIKey))
            {
                string embedText = $"{entry.animationSummary} {string.Join(" ", entry.tags)} {entry.animationDescription}";
                entry.embedding  = await ShapeEmbeddingService.GenerateEmbeddingAsync(embedText, openAIKey);
            }

            shape.animators.Add(entry);
            SaveKB(kb);
            Debug.Log($"[AnimKB] Saved '{entry.fileName}' to shape '{shape.fileName}' " +
                      $"({shape.animators.Count} animator(s) total).");
        }

        public static void SaveKB(ShapeKnowledgeBase kb)
        {
            kb.totalShapes   = kb.shapes.Count;
            kb.generatedDate = DateTime.Now.ToString("yyyy-MM-dd");
            File.WriteAllText(KB_PATH,
                Newtonsoft.Json.JsonConvert.SerializeObject(kb, Newtonsoft.Json.Formatting.Indented));
            AssetDatabase.Refresh();
        }

        private static float CosineSimilarity(float[] a, float[] b)
        {
            float dot = 0f, magA = 0f, magB = 0f;
            int len = Math.Min(a.Length, b.Length);
            for (int i = 0; i < len; i++) { dot += a[i]*b[i]; magA += a[i]*a[i]; magB += b[i]*b[i]; }
            float d = Mathf.Sqrt(magA) * Mathf.Sqrt(magB);
            return d < 1e-8f ? 0f : dot / d;
        }
    }
}