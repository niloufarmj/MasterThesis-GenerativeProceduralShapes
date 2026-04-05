using System.Collections.Generic;
using System.Text;
using ShaderGraphGenerator.Editor;

namespace ShaderGraphGenerator.RAG
{
    /// <summary>
    /// Builds the LLM prompt for the HLSL update pipeline.
    /// Separated from HLSLUpdatePipelineManager to keep the pipeline logic focused.
    /// </summary>
    public static class HLSLUpdatePromptBuilder
    {
        public static string Build(
            string originalHlsl,
            string currentHlsl,
            string updateRequest,
            List<LLMShaderProperty> originalProperties,
            List<RetrievedExample>  examples,
            string prevVlmFeedback,
            string userFeedback,
            int    iteration)
        {
            var sb = new StringBuilder();

            sb.AppendLine("You are an expert HLSL shader developer for Unity ShaderGraph Custom Function Nodes.");
            sb.AppendLine("Your task: UPDATE an existing HLSL shader to satisfy the user's specific request.");
            sb.AppendLine();
            sb.AppendLine("## CRITICAL RULES");
            sb.AppendLine("- Preserve the EXACT same function signature style:  void Name_float(float2 UV, ..., out float4 outColor)");
            sb.AppendLine("- You MAY add new parameters but must KEEP all existing ones");
            sb.AppendLine("- Change ONLY what the update request asks — preserve everything else visually");
            sb.AppendLine("- Use HLSL intrinsics only: lerp (not mix), frac (not fract), fmod (not mod)");
            sb.AppendLine("- Helper functions must be defined BEFORE the main function");
            sb.AppendLine();

            sb.AppendLine("## ORIGINAL HLSL (do not regress from this baseline)");
            sb.AppendLine("```hlsl");
            sb.AppendLine(originalHlsl);
            sb.AppendLine("```");
            sb.AppendLine();

            if (iteration > 1 && !string.ReferenceEquals(originalHlsl, currentHlsl))
            {
                sb.AppendLine("## CURRENT BEST ATTEMPT (improve this, not the original)");
                sb.AppendLine("```hlsl");
                sb.AppendLine(currentHlsl);
                sb.AppendLine("```");
                sb.AppendLine();
            }

            sb.AppendLine("## USER UPDATE REQUEST");
            sb.AppendLine(updateRequest);
            sb.AppendLine();

            if (originalProperties != null && originalProperties.Count > 0)
            {
                sb.AppendLine("## CURRENT MATERIAL PROPERTY VALUES");
                sb.AppendLine("These are the EXACT values currently set on the material that produces the 'before' image.");
                sb.AppendLine("IMPORTANT: Your 'properties' array MUST include EVERY parameter in the updated shader function — both");
                sb.AppendLine("unchanged ones (copy exact values from the list below) and new/changed ones (assign appropriate values).");
                sb.AppendLine("Do NOT omit any parameter. If a parameter was removed by the update, omit only that one.");
                sb.AppendLine("For color/float4 properties: ALWAYS set w (alpha) to 1.0 unless you have a specific reason otherwise.");
                sb.AppendLine("NEVER return a color with w=0 — that makes it invisible.");
                sb.AppendLine();
                foreach (var p in originalProperties)
                {
                    var    v      = p.default_value;
                    string valStr = p.type == "float"
                        ? v.x.ToString("F4")
                        : $"{{x:{v.x:F4}, y:{v.y:F4}, z:{v.z:F4}, w:{v.w:F4}}}";
                    sb.AppendLine($"  {p.name} ({p.type}): {valStr}");
                }
                sb.AppendLine();
            }

            if (!string.IsNullOrEmpty(prevVlmFeedback))
            {
                sb.AppendLine("## VLM FEEDBACK FROM PREVIOUS ATTEMPT (address these issues)");
                sb.AppendLine(prevVlmFeedback);
                sb.AppendLine();
            }

            if (!string.IsNullOrEmpty(userFeedback))
            {
                sb.AppendLine("## HUMAN REVIEWER FEEDBACK (address these issues)");
                sb.AppendLine(userFeedback);
                sb.AppendLine();
            }

            if (examples.Count > 0)
            {
                sb.AppendLine("## RETRIEVED LIBRARY EXAMPLES (technique reference only)");
                foreach (var ex in examples)
                {
                    sb.AppendLine($"### {ex.matchedShapeName} (similarity: {ex.similarityScore:F2})");
                    if (!string.IsNullOrEmpty(ex.matchedShapeDescription))
                        sb.AppendLine($"Description: {ex.matchedShapeDescription}");
                    sb.AppendLine("```hlsl");
                    sb.AppendLine(ex.hlslCode);
                    sb.AppendLine("```");
                    sb.AppendLine();
                }
            }

            sb.AppendLine("## OUTPUT FORMAT — return ONLY this JSON, no markdown, no extra text");
            sb.AppendLine("CRITICAL for the 'properties' array:");
            sb.AppendLine("- List ALL parameters in the updated shader function (not just changed ones).");
            sb.AppendLine("- For unchanged parameters: copy the EXACT value from 'CURRENT MATERIAL PROPERTY VALUES' above.");
            sb.AppendLine("- For new or changed parameters: assign a meaningful non-zero value.");
            sb.AppendLine("- float/float2/float3: scalar  e.g. 0.5");
            sb.AppendLine("- float4/color: object with w=1.0 for opaque  e.g. {\"x\":1.0,\"y\":0.2,\"z\":0.2,\"w\":1.0}");
            sb.AppendLine("- NEVER output {\"x\":0,\"y\":0,\"z\":0,\"w\":0} — if you have no good value, use the original from above.");
            sb.AppendLine(@"{
  ""file_name"": ""UpdatedShapeName"",
  ""hlsl_code"": ""[complete updated HLSL code]"",
  ""properties"": [
    { ""name"": ""ScarfStripeCount"", ""type"": ""float"", ""default_value"": 5 },
    { ""name"": ""ScarfStripeColor"", ""type"": ""float4"", ""default_value"": {""x"":1.0,""y"":1.0,""z"":0.0,""w"":1.0} }
  ]
}");
            return sb.ToString();
        }
    }
}
