using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using UnityEngine;
using UnityEngine.Networking;
using Newtonsoft.Json;
using ShaderGraphGenerator.KnowledgeBase;

namespace ShaderGraphGenerator.RAG
{
    /// <summary>
    /// LLM service for decomposing complex shape requests into component primitives
    /// </summary>
    public static class ShapeDecompositionService
    {
        /// <summary>
        /// Decompose a complex shape request into component descriptions
        /// Takes knowledge base into account to make informed decisions
        /// </summary>
        public static async Task<ShapeDecomposition> DecomposeShapeAsync(
            string userRequest, 
            ShapeKnowledgeBase knowledgeBase,
            string apiKey)
        {
            string prompt = BuildDecompositionPrompt(userRequest, knowledgeBase);
            string jsonResponse = await CallGeminiAsync(prompt, apiKey);

            if (string.IsNullOrEmpty(jsonResponse))
            {
                Debug.LogError("LLM returned null response for decomposition");
                return null;
            }

            try
            {
                var decomposition = JsonConvert.DeserializeObject<ShapeDecomposition>(jsonResponse);
                return decomposition;
            }
            catch (Exception ex)
            {
                Debug.LogError($"Failed to parse decomposition response: {ex.Message}\nResponse: {jsonResponse}");
                return null;
            }
        }

        private static string BuildDecompositionPrompt(string userRequest, ShapeKnowledgeBase knowledgeBase)
        {
            // Build a summary of available shapes
            string availableShapesSummary = BuildKnowledgeBaseSummary(knowledgeBase);

            return $@"You are an expert at analyzing complex 2D shape descriptions and breaking them down into simple geometric primitives that can be combined using boolean operations and transformations.

**IMPORTANT CONTEXT - Available Shape Library:**
We have a knowledge base of {knowledgeBase.totalShapes} verified procedural shapes. Here's what's available:

{availableShapesSummary}

**User Request:**
{userRequest}

**Your Task:**
Decompose this request into component shapes that can be combined. You should:

1. **Consider what shapes we already have**: If we have a shape that matches a component, you can reference it
2. **Don't be limited by what we have**: If a needed component doesn't exist in our library, still include it - we can generate it later
3. **Prefer existing shapes when appropriate**: E.g., if we have ""RoundedRectangle"", use that instead of decomposing into ""rectangle + rounded corners""
4. **Break into simple primitives when needed**: If the request is complex and no single existing shape matches, decompose it

**Guidelines for Decomposition:**
- Break the shape into the SIMPLEST possible components
- Each component should be describable as a single primitive or existing shape
- Identify the role of each component (base, decoration, feature, etc.)
- Suggest spatial relationships and composition strategy
- Note which components might already exist in our library (but don't force it)

**Component Types:**
- Geometric primitives: circle, square, rectangle, triangle, polygon, ellipse, star, rounded rectangle, hexagon
- Organic shapes: heart, cloud, leaf, flower, blob
- Symbols: arrow, gear, cross, checkmark, battery, lock
- Composite patterns: If we already have a complex shape that matches, use it!

**Decision Process:**
1. Check if the ENTIRE request matches an existing shape → return as simple
2. Check if we have shapes that cover major components → reference them
3. For missing components → describe what's needed (we'll search or generate)

**CRITICAL**: Return ONLY valid JSON with this EXACT structure:

{{
  ""is_simple"": false,
  ""reasoning"": ""Brief explanation of decomposition strategy and which existing shapes were considered"",
  ""components"": [
    {{
      ""description"": ""rectangle for the house base"",
      ""role"": ""base"",
      ""primitive_type"": ""rectangle"",
      ""relative_size"": ""large"",
      ""position_hint"": ""bottom center"",
      ""might_exist_as"": ""RectangleShape or RoundedRectangle"",
      ""is_likely_in_library"": true
    }},
    {{
      ""description"": ""equilateral triangle for the roof"",
      ""role"": ""roof"",
      ""primitive_type"": ""triangle"",
      ""relative_size"": ""medium"",
      ""position_hint"": ""top center, sitting on base"",
      ""might_exist_as"": ""TriangleShape or EquilateralTriangle"",
      ""is_likely_in_library"": true
    }},
    {{
      ""description"": ""small rectangle for door with rounded top"",
      ""role"": ""door"",
      ""primitive_type"": ""rounded_rectangle"",
      ""relative_size"": ""small"",
      ""position_hint"": ""center bottom of house base"",
      ""might_exist_as"": ""RoundedRectangle or DoorShape"",
      ""is_likely_in_library"": false
    }}
  ],
  ""composition_strategy"": ""Layer the triangle roof on top of the rectangle base using union operation. Position the roof so its bottom edge aligns with the top of the house base. Add door as a smaller rounded rectangle positioned at center-bottom. Windows can be added as small squares on left and right sides."",
  ""total_components"": 3,
  ""uses_existing_shapes"": true,
  ""missing_shapes_needed"": [""door with rounded top - might need to generate""]
}}

**For SIMPLE shapes (matches existing or is a single primitive):**
{{
  ""is_simple"": true,
  ""reasoning"": ""Request matches existing CircleShape in library, no decomposition needed"",
  ""components"": [
    {{
      ""description"": ""a simple circle"",
      ""role"": ""main"",
      ""primitive_type"": ""circle"",
      ""relative_size"": ""medium"",
      ""position_hint"": ""center"",
      ""might_exist_as"": ""CircleShape or Circle"",
      ""is_likely_in_library"": true
    }}
  ],
  ""composition_strategy"": ""Single primitive shape, no composition needed"",
  ""total_components"": 1,
  ""uses_existing_shapes"": true,
  ""missing_shapes_needed"": []
}}

Do NOT include markdown formatting, code blocks, or any text outside the JSON object.";
        }

        /// <summary>
        /// Build a concise summary of available shapes for the prompt
        /// </summary>
        private static string BuildKnowledgeBaseSummary(ShapeKnowledgeBase knowledgeBase)
        {
            var categorized = new Dictionary<ShapeCategory, List<string>>();

            // Group shapes by category
            foreach (var shape in knowledgeBase.shapes)
            {
                if (!categorized.ContainsKey(shape.category))
                    categorized[shape.category] = new List<string>();

                // Create a short descriptor: "ShapeName (tags)"
                string tags = shape.tags != null && shape.tags.Count > 0 
                    ? string.Join(", ", shape.tags.Take(3)) 
                    : "";
                string descriptor = string.IsNullOrEmpty(tags) 
                    ? shape.fileName 
                    : $"{shape.fileName} ({tags})";

                categorized[shape.category].Add(descriptor);
            }

            // Build summary text
            var lines = new List<string>();
            lines.Add("```");

            foreach (var category in categorized.Keys.OrderBy(c => c))
            {
                lines.Add($"\n{category} ({categorized[category].Count} shapes):");
                
                // Show up to 20 shapes per category (to keep prompt manageable)
                var shapesToShow = categorized[category].Take(20);
                foreach (var shape in shapesToShow)
                {
                    lines.Add($"  • {shape}");
                }
                
                if (categorized[category].Count > 20)
                {
                    lines.Add($"  ... and {categorized[category].Count - 20} more");
                }
            }

            lines.Add("```");
            return string.Join("\n", lines);
        }

        private static async Task<string> CallGeminiAsync(string prompt, string apiKey)
        {
            const string model = "gemini-3-pro-preview";
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

    /// <summary>
    /// Result of shape decomposition
    /// </summary>
    [Serializable]
    public class ShapeDecomposition
    {
        public bool is_simple;
        public string reasoning;
        public List<ShapeComponent> components = new List<ShapeComponent>();
        public string composition_strategy;
        public int total_components;
        public bool uses_existing_shapes;
        public List<string> missing_shapes_needed = new List<string>();
    }

    /// <summary>
    /// A single component in the decomposition
    /// </summary>
    [Serializable]
    public class ShapeComponent
    {
        public string description;          // "rectangle for house base"
        public string role;                  // "base", "decoration", "feature"
        public string primitive_type;        // "rectangle", "circle", "triangle"
        public string relative_size;         // "large", "medium", "small"
        public string position_hint;         // "bottom center", "top left"
        public string might_exist_as;        // "RectangleShape or RoundedRectangle"
        public bool is_likely_in_library;    // Agent's estimate if we have this
    }
}