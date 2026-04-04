using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using UnityEngine;
using Newtonsoft.Json;
using ShaderGraphGenerator.KnowledgeBase;
using ShaderGraphGenerator.Editor;

namespace ShaderGraphGenerator.RAG
{
    /// <summary>
    /// RAG-based shape generator: Uses decomposition + retrieval + LLM composition
    /// </summary>
    public static class RAGShapeGenerator
    {
        /// <summary>
        /// Generate a complex shape using RAG approach
        /// </summary>
        public static async Task<LLMShaderResponse> GenerateWithRAGAsync(
            string userRequest,
            ShapeKnowledgeBase knowledgeBase,
            ShaderGraphGeneratorConfig config,
            bool useTransparency = true)
        {
            Debug.Log($"[RAG] Starting generation for: {userRequest}");

            // Step 1: Decompose request into components
            Debug.Log("[RAG] Step 1: Decomposing request...");
            var decomposition = await ShapeDecompositionService.DecomposeShapeAsync(
                userRequest, 
                knowledgeBase, 
                config.geminiKey
            );

            if (decomposition == null)
            {
                Debug.LogError("[RAG] Decomposition failed");
                return null;
            }

            Debug.Log($"[RAG] Decomposed into {decomposition.total_components} components");
            Debug.Log($"[RAG] Uses existing shapes: {decomposition.uses_existing_shapes}");

            // Step 2: Retrieve best matching primitives for each component
            Debug.Log("[RAG] Step 2: Retrieving primitives...");
            var retrievedExamples = new List<RetrievedExample>();

            foreach (var component in decomposition.components)
            {
                var searchResults = await SemanticShapeSearch.SearchAsync(
                    component.description,
                    knowledgeBase,
                    config.openAIKey,
                    topK: 2  // Get top 2 matches per component
                );

                bool matched = false;
                foreach (var candidate in searchResults)
                {
                    if (!File.Exists(candidate.shape.filePath))
                    {
                        Debug.LogWarning($"[RAG]   {component.role}: Skipping '{candidate.shape.fileName}' — file not found at {candidate.shape.filePath}");
                        continue;
                    }

                    string hlslCode = File.ReadAllText(candidate.shape.filePath);
                    retrievedExamples.Add(new RetrievedExample
                    {
                        componentRole = component.role,
                        componentDescription = component.description,
                        matchedShapeName = candidate.shape.fileName,
                        matchedShapePrompt = candidate.shape.originalPrompt,
                        matchedShapeDescription = candidate.shape.visualDescription,
                        hlslCode = hlslCode,
                        similarityScore = candidate.similarity
                    });

                    Debug.Log($"[RAG]   {component.role}: Found {candidate.shape.fileName} (similarity: {candidate.similarity:F3})");
                    matched = true;
                    break;
                }

                if (!matched)
                {
                    Debug.LogWarning($"[RAG]   {component.role}: No valid matches found - will generate from scratch");
                }
            }

            // Step 3: Build RAG-enhanced prompt and call LLM
            Debug.Log("[RAG] Step 3: Generating HLSL with LLM (informed by retrieved examples)...");
            string ragPrompt = BuildRAGPrompt(
                userRequest, 
                decomposition, 
                retrievedExamples, 
                useTransparency
            );

            string jsonResponse = await LLMApiService.CallGeminiAsync(ragPrompt, config.geminiKey);

            if (string.IsNullOrEmpty(jsonResponse))
            {
                Debug.LogError("[RAG] LLM returned null response");
                return null;
            }

            // Strip markdown code fences (```json ... ``` or ``` ... ```) if present
            jsonResponse = StripMarkdownCodeBlock(jsonResponse);

            try
            {
                var response = JsonConvert.DeserializeObject<LLMShaderResponse>(jsonResponse);
                Debug.Log($"[RAG] ✓ Generated: {response.file_name}");
                return response;
            }
            catch (Exception ex)
            {
                Debug.LogError($"[RAG] Failed to parse response: {ex.Message}\n{jsonResponse}");
                return null;
            }
        }


        /// <summary>
        /// Image-to-Shader RAG pipeline.
        /// 1. GPT-4o Vision describes the image in detail (for decomposition + KB retrieval).
        /// 2. Decompose the description into components and retrieve KB examples.
        /// 3. Gemini Vision generates HLSL with BOTH the text prompt AND the original image,
        ///    so it can see exactly what to recreate.
        /// absoluteImagePath must be an absolute filesystem path.
        /// editableHints: user's note about what should be editable properties (can be empty).
        /// </summary>
        public static async Task<LLMShaderResponse> GenerateWithRAGFromImageAsync(
            string absoluteImagePath,
            string editableHints,
            ShapeKnowledgeBase knowledgeBase,
            ShaderGraphGeneratorConfig config,
            bool useTransparency = true)
        {
            Debug.Log($"[RAG Image] Starting image-to-shader pipeline for: {absoluteImagePath}");

            // ── Step 1: VLM describes the image ──────────────────────────────
            Debug.Log("[RAG Image] Step 1: GPT-4o Vision describing image...");
            string visualDescription = await LLMApiService.CallOpenAIDescribeImageAsync(
                absoluteImagePath, editableHints, config.openAIKey);

            if (string.IsNullOrEmpty(visualDescription))
            {
                Debug.LogError("[RAG Image] Image description failed");
                return null;
            }

            Debug.Log($"[RAG Image] Visual description ({visualDescription.Length} chars):\n{visualDescription.Substring(0, System.Math.Min(300, visualDescription.Length))}...");

            // ── Step 2: Decompose visual description into components ───────────
            Debug.Log("[RAG Image] Step 2: Decomposing visual description...");
            var decomposition = await ShapeDecompositionService.DecomposeShapeAsync(
                visualDescription, knowledgeBase, config.geminiKey);

            if (decomposition == null)
            {
                Debug.LogError("[RAG Image] Decomposition failed");
                return null;
            }

            Debug.Log($"[RAG Image] Decomposed into {decomposition.total_components} components");

            // ── Step 3: Retrieve KB examples per component ───────────────────
            Debug.Log("[RAG Image] Step 3: Retrieving primitives...");
            var retrievedExamples = new List<RetrievedExample>();

            foreach (var component in decomposition.components)
            {
                var searchResults = await SemanticShapeSearch.SearchAsync(
                    component.description, knowledgeBase, config.openAIKey, topK: 2);

                foreach (var candidate in searchResults)
                {
                    if (!File.Exists(candidate.shape.filePath)) continue;
                    retrievedExamples.Add(new RetrievedExample
                    {
                        componentRole           = component.role,
                        componentDescription    = component.description,
                        matchedShapeName        = candidate.shape.fileName,
                        matchedShapePrompt      = candidate.shape.originalPrompt,
                        matchedShapeDescription = candidate.shape.visualDescription,
                        hlslCode                = File.ReadAllText(candidate.shape.filePath),
                        similarityScore         = candidate.similarity
                    });
                    Debug.Log($"[RAG Image]   {component.role}: {candidate.shape.fileName} (sim={candidate.similarity:F3})");
                    break; // top-1 per component
                }
            }

            // ── Step 4: Build prompt + call Gemini Vision ─────────────────────
            // The text prompt tells Gemini exactly what to generate (from the description).
            // The image gives it the ground truth visual reference. Best of both worlds.
            Debug.Log("[RAG Image] Step 4: Generating HLSL with Gemini Vision...");

            string editableSection = string.IsNullOrWhiteSpace(editableHints)
                ? ""
                : $"\n\n## USER-REQUESTED EDITABLE PROPERTIES\n{editableHints}\n" +
                  "Make sure each of these aspects has a corresponding shader parameter.";

            string ragPrompt = BuildRAGPromptFromImage(
                visualDescription, editableSection, decomposition, retrievedExamples, useTransparency);

            string jsonResponse = await LLMApiService.CallGeminiWithImageAsync(
                ragPrompt, absoluteImagePath, config.geminiKey);

            if (string.IsNullOrEmpty(jsonResponse))
            {
                Debug.LogError("[RAG Image] Gemini Vision returned null");
                return null;
            }

            jsonResponse = StripMarkdownCodeBlock(jsonResponse);

            try
            {
                var response = JsonConvert.DeserializeObject<LLMShaderResponse>(jsonResponse);
                Debug.Log($"[RAG Image] ✓ Generated: {response.file_name}");
                return response;
            }
            catch (Exception ex)
            {
                Debug.LogError($"[RAG Image] Failed to parse response: {ex.Message}\n{jsonResponse}");
                return null;
            }
        }

        private static string BuildRAGPromptFromImage(
            string visualDescription,
            string editableSection,
            ShapeDecomposition decomposition,
            List<RetrievedExample> retrievedExamples,
            bool useTransparency)
        {
            var sb = new System.Text.StringBuilder();

            sb.AppendLine(GetMasterPromptHeader());
            sb.AppendLine();

            sb.AppendLine("## YOUR TASK: IMAGE-TO-SHADER GENERATION");
            sb.AppendLine("An image has been provided alongside this prompt. Your goal is to recreate it as a 2D procedural HLSL shader.");
            sb.AppendLine("Study the image carefully — it is the ground truth visual reference.");
            sb.AppendLine();

            sb.AppendLine("## VISUAL DESCRIPTION (from image analysis)");
            sb.AppendLine("A vision model analyzed the reference image and produced this structured description:");
            sb.AppendLine();
            sb.AppendLine(visualDescription);
            sb.AppendLine();

            if (!string.IsNullOrWhiteSpace(editableSection))
            {
                sb.AppendLine(editableSection);
                sb.AppendLine();
            }

            sb.AppendLine("## DECOMPOSITION STRATEGY");
            sb.AppendLine($"Reasoning: {decomposition.reasoning}");
            sb.AppendLine($"Strategy: {decomposition.composition_strategy}");
            sb.AppendLine($"Components: {decomposition.total_components}");
            sb.AppendLine();

            if (retrievedExamples.Count > 0)
            {
                sb.AppendLine("## RETRIEVED LIBRARY EXAMPLES (technique reference)");
                foreach (var ex in retrievedExamples)
                {
                    sb.AppendLine($"### {ex.componentRole}: {ex.matchedShapeName} (sim={ex.similarityScore:F2})");
                    sb.AppendLine($"Description: {ex.matchedShapeDescription}");
                    sb.AppendLine("```hlsl");
                    sb.AppendLine(ex.hlslCode);
                    sb.AppendLine("```");
                    sb.AppendLine();
                }
            }

            sb.AppendLine("## INSTRUCTIONS");
            sb.AppendLine("1. Look at the provided reference image as your primary visual target.");
            sb.AppendLine("2. Use the visual description and retrieved examples as supporting context.");
            sb.AppendLine("3. Generate a SINGLE HLSL function that reproduces the image as closely as possible.");
            sb.AppendLine("4. Every visually distinct colored region should have a corresponding float4 Color parameter.");
            sb.AppendLine("5. Important sizes (body radius, hat height, etc.) should be float parameters.");
            sb.AppendLine("6. Match the spatial layout, proportions, and colors from the reference image.");
            sb.AppendLine("7. Use SDF composition (union, subtraction, smoothstep AA) for clean edges.");
            sb.AppendLine();
            sb.AppendLine("## CRITICAL — DEFAULT VALUES (THIS IS MANDATORY)");
            sb.AppendLine("Every property in the 'properties' array MUST have a meaningful non-zero default_value.");
            sb.AppendLine("The default values will be applied directly to the material at generation time.");
            sb.AppendLine("If default values are zero, the rendered output will be completely invisible (white/black).");
            sb.AppendLine("RULES:");
            sb.AppendLine("- float4 colors: set RGBA from the reference image. NEVER return {x:0,y:0,z:0,w:0}.");
            sb.AppendLine("  Always set w (alpha) to 1.0 for opaque colors. E.g. red = {x:1,y:0,z:0,w:1}");
            sb.AppendLine("- float sizes: use realistic values visible on a 0-1 UV quad. E.g. 0.3 for a body.");
            sb.AppendLine("  NEVER return 0 for a size. The shape must be visible.");
            sb.AppendLine("- float2 positions: default to center {x:0.5,y:0.5} unless offset is needed.");
            sb.AppendLine("BAD:  {\"name\":\"StarColor\",\"type\":\"float4\",\"default_value\":{\"x\":0,\"y\":0,\"z\":0,\"w\":0}}");
            sb.AppendLine("GOOD: {\"name\":\"StarColor\",\"type\":\"float4\",\"default_value\":{\"x\":1,\"y\":0.8,\"z\":0,\"w\":1}}");
            sb.AppendLine("BAD:  {\"name\":\"StarSize\",\"type\":\"float\",\"default_value\":0}");
            sb.AppendLine("GOOD: {\"name\":\"StarSize\",\"type\":\"float\",\"default_value\":0.35}");
            sb.AppendLine();
            sb.AppendLine("Return ONLY the JSON with file_name, hlsl_code, and properties. No markdown fences.");

            return sb.ToString();
        }

        /// <summary>
        /// Build RAG-enhanced prompt with retrieved examples
        /// </summary>
        private static string BuildRAGPrompt(
            string userRequest,
            ShapeDecomposition decomposition,
            List<RetrievedExample> retrievedExamples,
            bool useTransparency)
        {
            var sb = new StringBuilder();

            // Start with the Master Prompt structure
            sb.AppendLine(GetMasterPromptHeader());
            sb.AppendLine();

            // Add RAG-specific context
            sb.AppendLine("## RETRIEVAL-AUGMENTED GENERATION CONTEXT");
            sb.AppendLine();
            sb.AppendLine("Your task has been decomposed into components. For each component, we've retrieved similar shapes from our verified library.");
            sb.AppendLine("**IMPORTANT**: These are EXAMPLES to inspire you, NOT code to copy verbatim.");
            sb.AppendLine("- Study the SDF techniques used in these examples");
            sb.AppendLine("- Understand how they achieve their visual effects");
            sb.AppendLine("- Adapt and combine these techniques to create the requested shape");
            sb.AppendLine("- You are NOT restricted to only these approaches - innovate as needed");
            sb.AppendLine();

            // Decomposition summary
            sb.AppendLine("### Decomposition Strategy");
            sb.AppendLine($"**Agent Reasoning**: {decomposition.reasoning}");
            sb.AppendLine($"**Composition Strategy**: {decomposition.composition_strategy}");
            sb.AppendLine($"**Total Components**: {decomposition.total_components}");
            sb.AppendLine();

            // Retrieved examples
            if (retrievedExamples.Count > 0)
            {
                sb.AppendLine("### Retrieved Example Shapes (for inspiration)");
                sb.AppendLine();

                foreach (var example in retrievedExamples)
                {
                    sb.AppendLine($"#### Component: {example.componentRole}");
                    sb.AppendLine($"**Needed**: {example.componentDescription}");
                    sb.AppendLine($"**Retrieved Match**: {example.matchedShapeName} (similarity: {example.similarityScore:F2})");
                    sb.AppendLine($"**Original Prompt**: {example.matchedShapePrompt}");
                    sb.AppendLine($"**Visual Description**: {example.matchedShapeDescription}");
                    sb.AppendLine();
                    sb.AppendLine("**HLSL Code (for reference):**");
                    sb.AppendLine("```hlsl");
                    sb.AppendLine(example.hlslCode);
                    sb.AppendLine("```");
                    sb.AppendLine();
                }

                sb.AppendLine("---");
                sb.AppendLine();
            }
            else
            {
                sb.AppendLine("### No Retrieved Examples");
                sb.AppendLine("No matching shapes found in library - generate from scratch using SDF fundamentals.");
                sb.AppendLine();
            }

            // User request
            sb.AppendLine("## USER REQUEST");
            sb.AppendLine(userRequest);
            sb.AppendLine();

            // Instructions
            sb.AppendLine("## YOUR TASK");
            sb.AppendLine("Create a SINGLE HLSL function that generates the requested shape.");
            sb.AppendLine();
            sb.AppendLine("**How to use the retrieved examples:**");
            sb.AppendLine("1. Study the SDF formulas used (sdCircle, sdBox, smooth union, etc.)");
            sb.AppendLine("2. Understand the parameter structure and transformations");
            sb.AppendLine("3. Identify useful techniques (e.g., polar coordinates, repetition, smoothMin)");
            sb.AppendLine("4. **Synthesize a NEW solution** - don't copy-paste, but adapt and combine");
            sb.AppendLine("5. If components need to be combined, use union/intersection/subtraction operations");
            sb.AppendLine();

            // Add constraints from Master Prompt
            sb.AppendLine(GetMasterPromptConstraints(useTransparency));

            return sb.ToString();
        }

        /// <summary>
        /// Get the master prompt header with HLSL rules
        /// </summary>
        private static string GetMasterPromptHeader()
        {
            return @"You are an expert HLSL shader developer specializing in Signed Distance Function (SDF) based procedural 2D graphics for Unity ShaderGraph.

## CRITICAL RULES - MUST FOLLOW EXACTLY

### Function Signature (STRICT)
```hlsl
void FunctionName_float(
    float2 UV,           // ALWAYS first parameter
    [your parameters],   // Your custom parameters
    out float4 outColor  // ALWAYS last parameter
)
```

### HLSL Syntax Requirements
- Use HLSL intrinsics ONLY (never GLSL): `lerp` not `mix`, `frac` not `fract`, `fmod` not `mod`
- Helper functions MUST be defined BEFORE main function
- Constants as preprocessor: `#ifndef PI \n#define PI 3.14159265359\n#endif`
- Never use `const float` for constants inside functions

### Parameter Naming (CRITICAL)
- Parameters with 'color' in name → `float4` type
- Other parameters: `float`, `float2`, `float3` as appropriate
- Default values will be auto-generated, focus on correct types";
        }

        /// <summary>
        /// Get constraints section from master prompt
        /// </summary>
        private static string GetMasterPromptConstraints(bool useTransparency)
        {
            string blendMode = useTransparency ? "Transparency/Alpha blending" : "Opaque";

            return $@"
## OUTPUT FORMAT (STRICT)

Return ONLY valid JSON with NO markdown, NO code blocks, NO preamble:

{{
  ""file_name"": ""DescriptiveShapeName"",
  ""hlsl_code"": ""[complete HLSL code here]"",
  ""properties"": [
    {{
      ""name"": ""ParameterName"",
      ""type"": ""float4"",
      ""default_value"": {{""x"": 1.0, ""y"": 0.5, ""z"": 0.0, ""w"": 1.0}}
    }}
  ]
}}

## Rendering Requirements
- Blend mode: {blendMode}
- Anti-aliasing: Use smoothstep or fwidth for smooth edges
- UV space: (0,0) = bottom-left, (1,1) = top-right, center shape at (0.5, 0.5)
- Distance field: negative = inside shape, positive = outside

## SDF Composition Operations
- Union: `min(d1, d2)`
- Smooth Union: `smin(d1, d2, k)` where k controls smoothness
- Intersection: `max(d1, d2)`
- Subtraction: `max(d1, -d2)`

Generate the complete, compilable HLSL code now.";
        }

        /// <summary>
        /// Helper to get smooth min function definition
        /// </summary>
        private static string StripMarkdownCodeBlock(string text)
        {
            if (string.IsNullOrEmpty(text)) return text;
            // Match ```json ... ``` or ``` ... ```
            var match = System.Text.RegularExpressions.Regex.Match(
                text, @"```(?:json)?\s*([\s\S]*?)```",
                System.Text.RegularExpressions.RegexOptions.Multiline);
            return match.Success ? match.Groups[1].Value.Trim() : text.Trim();
        }

        private static string GetSmoothMinHelper()
        {
            return @"
// Smooth minimum function (useful for blending shapes)
float smin(float a, float b, float k) {
    float h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * 0.25;
}";
        }
    }

    /// <summary>
    /// Container for retrieved example shapes
    /// </summary>
    public class RetrievedExample
    {
        public string componentRole;
        public string componentDescription;
        public string matchedShapeName;
        public string matchedShapePrompt;
        public string matchedShapeDescription;
        public string hlslCode;
        public float similarityScore;
    }
}