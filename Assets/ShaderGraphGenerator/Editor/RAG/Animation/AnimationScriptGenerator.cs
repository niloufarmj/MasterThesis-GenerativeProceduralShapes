using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using System.Threading.Tasks;
using UnityEngine;
using UnityEditor;
using Newtonsoft.Json;
using ShaderGraphGenerator.Editor;
using ShaderGraphGenerator.KnowledgeBase;

namespace ShaderGraphGenerator.RAG
{
    public static class AnimationScriptGenerator
    {
        /// <summary>
        /// Extracts all animatable properties (float, color, vector) from a material.
        /// Skips Unity internals and texture properties.
        /// </summary>
        public static List<MaterialPropertyInfo> ExtractMaterialProperties(Material material)
        {
            var result = new List<MaterialPropertyInfo>();
            if (material == null) return result;

            MaterialProperty[] props;
            try { props = MaterialEditor.GetMaterialProperties(new UnityEngine.Object[] { material }); }
            catch { return result; }

            foreach (var prop in props)
            {
                if (prop.name.StartsWith("unity_", StringComparison.OrdinalIgnoreCase)) continue;
                if (prop.type == MaterialProperty.PropType.Texture) continue;

                string typeName;
                string valueStr;

                switch (prop.type)
                {
                    case MaterialProperty.PropType.Float:
                    case MaterialProperty.PropType.Range:
                        typeName = "float";
                        valueStr = prop.floatValue.ToString("F3");
                        break;
                    case MaterialProperty.PropType.Color:
                        typeName = "color";
                        var c = prop.colorValue;
                        valueStr = $"({c.r:F2}, {c.g:F2}, {c.b:F2}, {c.a:F2})";
                        break;
                    case MaterialProperty.PropType.Vector:
                        typeName = "vector";
                        var v = prop.vectorValue;
                        valueStr = $"({v.x:F2}, {v.y:F2}, {v.z:F2}, {v.w:F2})";
                        break;
                    default: continue;
                }

                result.Add(new MaterialPropertyInfo
                {
                    name         = prop.name,
                    type         = typeName,
                    currentValue = valueStr
                });
            }
            return result;
        }

        /// <summary>
        /// Calls Gemini to generate a C# MonoBehaviour animation script.
        /// Returns LLMAnimationResponse or null on failure.
        /// </summary>
        public static async Task<LLMAnimationResponse> GenerateAnimationScriptAsync(
            string animationRequest,
            string materialName,
            List<MaterialPropertyInfo> properties,
            List<(AnimatorEntry entry, float similarity)> retrievedExamples,
            string geminiKey,
            string userFeedback        = null,
            bool   allowNewProperties  = false)
        {
            string prompt = BuildPrompt(animationRequest, materialName, properties,
                                        retrievedExamples, userFeedback, allowNewProperties);

            string raw = await GeminiApiService.CallGeminiAsync(prompt, geminiKey);
            if (string.IsNullOrEmpty(raw))
            {
                Debug.LogError("[AnimGen] Gemini returned null");
                return null;
            }

            // Strip markdown fences
            raw = StripMarkdown(raw);

            try
            {
                var response = JsonConvert.DeserializeObject<LLMAnimationResponse>(raw);
                Debug.Log($"[AnimGen] Generated: {response.file_name}");
                return response;
            }
            catch (Exception ex)
            {
                Debug.LogError($"[AnimGen] JSON parse failed: {ex.Message}\nRaw: {raw.Substring(0, Math.Min(500, raw.Length))}");
                return null;
            }
        }

        // ─── Prompt Builder ───────────────────────────────────────────────────

        private static string BuildPrompt(
            string animationRequest,
            string materialName,
            List<MaterialPropertyInfo> properties,
            List<(AnimatorEntry entry, float similarity)> retrievedExamples,
            string userFeedback,
            bool   allowNewProperties = false)
        {
            var sb = new StringBuilder();

            sb.AppendLine("You are an expert Unity C# developer specialising in procedural material animation.");
            sb.AppendLine("Your task: write a self-contained MonoBehaviour that animates a material's properties over time.");
            sb.AppendLine();

            sb.AppendLine("## CRITICAL RULES — READ CAREFULLY");
            sb.AppendLine("1. The script MUST be a single, complete, compilable C# class.");
            sb.AppendLine("2. Inherit from MonoBehaviour. Use ONLY standard Unity APIs.");
            sb.AppendLine("3. NEVER use Tween libraries (DOTween, LeanTween, iTween), Animator, or Animation components.");
            sb.AppendLine("4. Animate ONLY via material.SetFloat(), material.SetColor(), material.SetVector().");
            sb.AppendLine("5. In Awake(), get the renderer and call mat = GetComponent<Renderer>().material;");
            sb.AppendLine("   (Use .material NOT .sharedMaterial — instance only, never affect shared assets.)");
            sb.AppendLine("6. Drive animation with Time.time and Mathf functions (Sin, Cos, PingPong, Repeat, Lerp).");
            sb.AppendLine("7. Expose tuning parameters as [Header(\"...\")]  public fields so user can tweak in Inspector.");
            sb.AppendLine("8. Include a public bool loop = true; and public float speed = 1f; at minimum.");
            if (!allowNewProperties)
                sb.AppendLine("9. Only animate properties that actually EXIST in the property list below. Do NOT invent new ones.");
            else
                sb.AppendLine("9. Prefer existing properties. If the animation truly requires a new property, declare it in 'new_properties' (see output format below). Keep new properties minimal.");
            sb.AppendLine("10. Use #pragma warning disable / enable around any generated code if needed.");
            sb.AppendLine("11. The class name MUST match file_name exactly.");
            sb.AppendLine("12. Include a Reset() public method that restores all animated properties to their initial values.");
            sb.AppendLine();

            sb.AppendLine("## MATERIAL BEING ANIMATED");
            sb.AppendLine($"Material name: {materialName}");
            sb.AppendLine();
            sb.AppendLine("### Animatable Properties (use ONLY these exact names with SetFloat/SetColor/SetVector):");
            foreach (var p in properties)
                sb.AppendLine($"  {p.name}  ({p.type})  current = {p.currentValue}");
            sb.AppendLine();

            sb.AppendLine("## USER ANIMATION REQUEST");
            sb.AppendLine(animationRequest);
            sb.AppendLine();

            if (!string.IsNullOrWhiteSpace(userFeedback))
            {
                sb.AppendLine("## FEEDBACK FROM PREVIOUS ATTEMPT (address all of these)");
                sb.AppendLine(userFeedback);
                sb.AppendLine();
            }

            if (retrievedExamples != null && retrievedExamples.Count > 0)
            {
                sb.AppendLine("## RETRIEVED ANIMATION EXAMPLES (technique reference — adapt don't copy)");
                foreach (var (entry, sim) in retrievedExamples)
                {
                    sb.AppendLine($"### {entry.fileName}  (similarity: {sim:F2})");
                    sb.AppendLine($"Description: {entry.animationSummary}");
                    sb.AppendLine($"Tags: {string.Join(", ", entry.tags)}");
                    sb.AppendLine($"Properties used: {string.Join(", ", entry.propertiesUsed)}");
                    if (!string.IsNullOrEmpty(entry.scriptPath) && File.Exists(entry.scriptPath))
                    {
                        sb.AppendLine("```csharp");
                        sb.AppendLine(File.ReadAllText(entry.scriptPath));
                        sb.AppendLine("```");
                    }
                    sb.AppendLine();
                }
            }

            sb.AppendLine("## ANIMATION PATTERNS (use as needed)");
            sb.AppendLine("- Smooth oscillation:   Mathf.Sin(Time.time * speed) * amplitude");
            sb.AppendLine("- Ping-pong:            Mathf.PingPong(Time.time * speed, 1f)");
            sb.AppendLine("- One-shot:             Mathf.Clamp01((Time.time - startTime) / duration)");
            sb.AppendLine("- Color hue cycle:      Color.HSVToRGB(Mathf.Repeat(Time.time * speed, 1f), sat, val)");
            sb.AppendLine("- Color lerp:           Color.Lerp(colorA, colorB, t)");
            sb.AppendLine("- Ease in-out:          t = Mathf.SmoothStep(0, 1, t)");
            sb.AppendLine("- Bounce:               Mathf.Abs(Mathf.Sin(Time.time * speed * Mathf.PI))");
            sb.AppendLine();

            sb.AppendLine("## OUTPUT FORMAT");
            sb.AppendLine("Return ONLY valid JSON — no markdown fences, no preamble:");
            if (!allowNewProperties)
            {
                sb.AppendLine(@"{
  ""file_name"": ""MaterialNameAnimationStyle"",
  ""cs_code"": ""using UnityEngine;\n\npublic class MaterialNameAnimationStyle : MonoBehaviour\n{\n    ...\n}"",
  ""animation_summary"": ""One sentence describing what this animation does"",
  ""properties_used"": [""Size"", ""ScarfColor""],
  ""animation_tags"": [""pulse"", ""color-cycle"", ""loop""],
  ""new_properties"": []
}");
            }
            else
            {
                sb.AppendLine(@"{
  ""file_name"": ""MaterialNameAnimationStyle"",
  ""cs_code"": ""using UnityEngine;\n\npublic class MaterialNameAnimationStyle : MonoBehaviour\n{\n    ...\n}"",
  ""animation_summary"": ""One sentence describing what this animation does"",
  ""properties_used"": [""Size"", ""ScarfColor"", ""GlowIntensity""],
  ""animation_tags"": [""pulse"", ""glow"", ""loop""],
  ""new_properties"": [
    { ""name"": ""GlowIntensity"", ""type"": ""float"", ""default_value"": 0.5 },
    { ""name"": ""GlowColor"",     ""type"": ""float4"", ""default_value"": {""x"":1.0,""y"":0.8,""z"":0.2,""w"":1.0} }
  ]
}");
                sb.AppendLine();
                sb.AppendLine("RULES for new_properties:");
                sb.AppendLine("- Only declare a new property if it is truly impossible to achieve the animation with existing ones.");
                sb.AppendLine("- Use type: float for scalars, float4 for colors (with w=1.0 for opaque).");
                sb.AppendLine("- Give every new property a meaningful non-zero default_value.");
                sb.AppendLine("- The new property name must be used in cs_code with material.SetFloat/SetColor/SetVector.");
                sb.AppendLine("- Leave new_properties as [] if all existing properties are sufficient.");
            }
            sb.AppendLine();
            sb.AppendLine("IMPORTANT for cs_code:");
            sb.AppendLine("- Use real newlines (\\n) in the JSON string for readability.");
            sb.AppendLine("- Do NOT escape quotes inside the class unnecessarily.");
            sb.AppendLine("- The code must compile without errors in Unity 6.");

            return sb.ToString();
        }

        private static string StripMarkdown(string text)
        {
            if (string.IsNullOrEmpty(text)) return text;
            var m = System.Text.RegularExpressions.Regex.Match(
                text, @"```(?:json)?\s*([\s\S]*?)```",
                System.Text.RegularExpressions.RegexOptions.Multiline);
            return m.Success ? m.Groups[1].Value.Trim() : text.Trim();
        }
    }
}