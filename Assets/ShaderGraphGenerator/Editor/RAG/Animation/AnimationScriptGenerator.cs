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
    /// <summary>Describes a single HLSL property that is missing and must be added.</summary>
    public class MissingShaderProperty
    {
        public string name        { get; set; }   // e.g. "_CornerRadius"
        public string hlsl_type   { get; set; }   // "float", "float4", "float2"
        public string range       { get; set; }   // e.g. "0.0 to 0.5"
        public string description { get; set; }   // what it controls in the shader
    }

    /// <summary>LLM classification of whether an animation needs HLSL shader changes.</summary>
    public class AnimationClassification
    {
        public bool   needs_hlsl_change  { get; set; }
        public string reason             { get; set; }
        /// <summary>
        /// Populated only when needs_hlsl_change==true.
        /// Each entry names a property the shader is missing for this animation.
        /// </summary>
        public List<MissingShaderProperty> missing_properties { get; set; } = new List<MissingShaderProperty>();
        /// <summary>
        /// A precise, self-contained update request for HLSLUpdatePipelineManager.
        /// Describes exactly what to add/change in the HLSL and why.
        /// Populated only when needs_hlsl_change==true.
        /// </summary>
        public string hlsl_update_request { get; set; }
    }

    public static class AnimationScriptGenerator
    {
        /// <summary>
        /// Asks Gemini whether the requested animation can be done purely via C# animating
        /// existing material properties, or whether new HLSL properties are required.
        /// When HLSL changes are needed, it also identifies exactly what is missing and
        /// produces a precise update request for the HLSL update pipeline.
        /// </summary>
        public static async Task<AnimationClassification> ClassifyAnimationRequirementsAsync(
            string animationRequest,
            string materialName,
            List<MaterialPropertyInfo> properties,
            string geminiKey)
        {
            var sb = new StringBuilder();
            sb.AppendLine("You are a Unity shader and animation expert.");
            sb.AppendLine("Analyse a material's existing properties and an animation request.");
            sb.AppendLine("Your job: decide whether the animation can be achieved purely by a C# MonoBehaviour");
            sb.AppendLine("that drives the EXISTING material properties (SetFloat/SetColor/SetVector), or whether");
            sb.AppendLine("the HLSL shader must be modified to expose new properties first.");
            sb.AppendLine();
            sb.AppendLine("## MATERIAL");
            sb.AppendLine($"Name: {materialName}");
            sb.AppendLine("### Existing Shader Properties (the ONLY ones a C# script could animate):");
            if (properties.Count == 0)
                sb.AppendLine("  (none)");
            else
                foreach (var p in properties)
                    sb.AppendLine($"  {p.name}  ({p.type})  current = {p.currentValue}");
            sb.AppendLine();
            sb.AppendLine("## ANIMATION REQUEST");
            sb.AppendLine(animationRequest);
            sb.AppendLine();
            sb.AppendLine("## DECISION RULES");
            sb.AppendLine("Set needs_hlsl_change: FALSE when:");
            sb.AppendLine("  - Every value the animation needs to drive already exists in the property list above.");
            sb.AppendLine("  - Example: 'pulse the color' → _Color exists → C# only.");
            sb.AppendLine();
            sb.AppendLine("Set needs_hlsl_change: TRUE when:");
            sb.AppendLine("  - The animation requires controlling a visual aspect that has NO corresponding property above.");
            sb.AppendLine("  - Example: 'animate corner radius' → no _CornerRadius property exists → HLSL must be updated.");
            sb.AppendLine("  - When TRUE you MUST fill in missing_properties and hlsl_update_request.");
            sb.AppendLine();
            sb.AppendLine("When in doubt, prefer FALSE (C# only).");
            sb.AppendLine();
            sb.AppendLine("## OUTPUT FORMAT — return ONLY valid JSON, no markdown, no preamble:");
            sb.AppendLine(@"{
  ""needs_hlsl_change"": false,
  ""reason"": ""One sentence: why C# alone is sufficient OR why HLSL must change."",
  ""missing_properties"": [],
  ""hlsl_update_request"": """"
}");
            sb.AppendLine();
            sb.AppendLine("When needs_hlsl_change is TRUE, populate missing_properties and hlsl_update_request like this example:");
            sb.AppendLine(@"{
  ""needs_hlsl_change"": true,
  ""reason"": ""The animation requires a corner-radius property that does not exist in the current shader."",
  ""missing_properties"": [
    {
      ""name"": ""_CornerRadius"",
      ""hlsl_type"": ""float"",
      ""range"": ""0.0 to 0.5"",
      ""description"": ""Controls how rounded the rectangle corners are; 0 = sharp, 0.5 = fully circular.""
    }
  ],
  ""hlsl_update_request"": ""Add a '_CornerRadius' float uniform (range 0.0–0.5, default 0.0) to the HLSL shader. It should smoothly blend the rectangle corners from sharp (0.0) to fully rounded (0.5) using a signed-distance-field or smooth-step approach. The rest of the shape (color, size, rotation) must remain unchanged.""
}");
            sb.AppendLine();
            sb.AppendLine("RULES for hlsl_update_request:");
            sb.AppendLine("- Be specific: name the exact properties to add and describe their visual effect.");
            sb.AppendLine("- Explain clearly what the shader must look like AFTER the update so the VLM can verify it.");
            sb.AppendLine("- Keep it focused — only describe what needs to change, not the whole shader.");

            string raw = await GeminiApiService.CallGeminiAsync(sb.ToString(), geminiKey);
            if (string.IsNullOrEmpty(raw))
            {
                Debug.LogWarning("[AnimClass] Gemini returned null — defaulting to C#-only path.");
                return new AnimationClassification { needs_hlsl_change = false, reason = "LLM unavailable." };
            }

            raw = StripMarkdown(raw);
            try
            {
                var cls = JsonConvert.DeserializeObject<AnimationClassification>(raw);
                if (cls.missing_properties == null) cls.missing_properties = new List<MissingShaderProperty>();
                Debug.Log($"[AnimClass] needs_hlsl_change={cls.needs_hlsl_change}  reason={cls.reason}");
                if (cls.needs_hlsl_change && cls.missing_properties.Count > 0)
                    Debug.Log($"[AnimClass] Missing properties: {string.Join(", ", cls.missing_properties.ConvertAll(p => p.name))}");
                if (cls.needs_hlsl_change)
                    Debug.Log($"[AnimClass] hlsl_update_request: {cls.hlsl_update_request}");
                return cls;
            }
            catch (Exception ex)
            {
                Debug.LogWarning($"[AnimClass] JSON parse failed ({ex.Message}) — defaulting to C#-only.\nRaw: {raw.Substring(0, Math.Min(300, raw.Length))}");
                return new AnimationClassification { needs_hlsl_change = false };
            }
        }

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