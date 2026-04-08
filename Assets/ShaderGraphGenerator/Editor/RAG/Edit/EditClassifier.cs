// EditClassifier.cs
// Classifies a user's edit request into one of two paths:
//   A) Property-only: the edit can be achieved by calling SetFloat/SetColor/SetVector
//      on the existing material — no shader code changes needed.
//   B) HLSL update: the edit requires new geometry, new parameters, or structural
//      shader changes — routed to HLSLUpdatePipelineManager.
//
// The classification is performed by a single Gemini call with a structured JSON
// prompt. On success it returns either a list of exact material property changes
// (path A) or a precise, targeted HLSL update request string (path B).
//
// Used by: ChatBridge.TriggerEdit
// See also: AnimationScriptGenerator.ClassifyAnimationRequirementsAsync (same pattern for animation)

using System;
using System.Collections.Generic;
using System.Text;
using System.Threading.Tasks;
using UnityEngine;
using UnityEditor;
using Newtonsoft.Json;
using ShaderGraphGenerator.Editor;
using ShaderGraphGenerator.RAG;

namespace ShaderGraphGenerator.RAG
{
    /// <summary>A single material-property change that can be applied directly without touching HLSL.</summary>
    public class MaterialPropertyChange
    {
        public string property_name { get; set; }
        /// <summary>"float", "color", or "vector"</summary>
        public string property_type { get; set; }
        public string description   { get; set; }

        // float / range
        public float float_value { get; set; }
        // color  (r g b a in 0-1 range)
        public float r { get; set; }
        public float g { get; set; }
        public float b { get; set; }
        public float a { get; set; } = 1f;
        // vector (x y z w)
        public float x { get; set; }
        public float y { get; set; }
        public float z { get; set; }
        public float w { get; set; }
    }

    /// <summary>
    /// Result of asking the LLM whether an edit request can be achieved by
    /// tweaking existing material properties or requires an HLSL update.
    /// </summary>
    public class EditClassification
    {
        public bool   needs_hlsl_change  { get; set; }
        public string reason             { get; set; }
        /// <summary>
        /// Populated when needs_hlsl_change == false.
        /// Each entry maps to a material.SetFloat/SetColor/SetVector call.
        /// </summary>
        public List<MaterialPropertyChange> material_changes  { get; set; } = new List<MaterialPropertyChange>();
        /// <summary>
        /// Populated when needs_hlsl_change == true.
        /// A precise, targeted prompt for HLSLUpdatePipelineManager — specific enough
        /// that the VLM can verify before/after screenshots.
        /// </summary>
        public string hlsl_update_request { get; set; }
    }

    public static class EditClassifier
    {
        /// <summary>
        /// Asks Gemini whether the requested edit can be achieved purely by
        /// changing existing material property values, or whether the HLSL shader
        /// must be modified.  Returns an <see cref="EditClassification"/> that
        /// either lists the exact property changes to apply, or a precise HLSL
        /// update request for HLSLUpdatePipelineManager.
        /// </summary>
        public static async Task<EditClassification> ClassifyEditRequestAsync(
            string editRequest,
            string materialName,
            List<MaterialPropertyInfo> properties,
            string geminiKey)
        {
            var sb = new StringBuilder();
            sb.AppendLine("You are a Unity shader expert.");
            sb.AppendLine("Given a material's current properties and an edit request, decide:");
            sb.AppendLine("  A) The edit can be achieved by changing values of EXISTING material properties only.");
            sb.AppendLine("  B) The edit requires modifying the HLSL shader source (new feature, new parameter, new visual element).");
            sb.AppendLine();
            sb.AppendLine("## MATERIAL");
            sb.AppendLine($"Name: {materialName}");
            sb.AppendLine("### Current Properties:");
            if (properties == null || properties.Count == 0)
                sb.AppendLine("  (none)");
            else
                foreach (var p in properties)
                    sb.AppendLine($"  {p.name}  ({p.type})  current = {p.currentValue}");
            sb.AppendLine();
            sb.AppendLine("## EDIT REQUEST");
            sb.AppendLine(editRequest);
            sb.AppendLine();
            sb.AppendLine("## DECISION RULES");
            sb.AppendLine("Choose needs_hlsl_change: FALSE when:");
            sb.AppendLine("  - The user wants to change a value that already exists in the property list (e.g. color, size, width, opacity).");
            sb.AppendLine("  - Example: 'make the body blue' and _BodyColor exists → just change _BodyColor.");
            sb.AppendLine("  - Example: 'make it larger' and _Size exists → just change _Size.");
            sb.AppendLine("  When FALSE, fill in material_changes with the EXACT new values to set.");
            sb.AppendLine();
            sb.AppendLine("Choose needs_hlsl_change: TRUE when:");
            sb.AppendLine("  - The request adds a completely new visual feature with no matching property.");
            sb.AppendLine("  - Example: 'add stripes to the scarf' when no stripe property exists.");
            sb.AppendLine("  - Example: 'add a shadow underneath the shape'.");
            sb.AppendLine("  When TRUE, fill in hlsl_update_request with a precise description of what to add/change in the HLSL.");
            sb.AppendLine();
            sb.AppendLine("When in doubt, prefer FALSE (property change only).");
            sb.AppendLine();
            sb.AppendLine("## OUTPUT FORMAT — return ONLY valid JSON, no markdown, no preamble:");
            sb.AppendLine(@"{
  ""needs_hlsl_change"": false,
  ""reason"": ""One sentence explaining the decision."",
  ""material_changes"": [],
  ""hlsl_update_request"": """"
}");
            sb.AppendLine();
            sb.AppendLine("When needs_hlsl_change is FALSE, populate material_changes like this example:");
            sb.AppendLine(@"{
  ""needs_hlsl_change"": false,
  ""reason"": ""_BodyColor already exists and can be set to blue."",
  ""material_changes"": [
    {
      ""property_name"": ""_BodyColor"",
      ""property_type"": ""color"",
      ""description"": ""Change body color from green to blue"",
      ""float_value"": 0.0,
      ""r"": 0.0, ""g"": 0.13, ""b"": 0.8, ""a"": 1.0,
      ""x"": 0.0, ""y"": 0.0, ""z"": 0.0, ""w"": 0.0
    }
  ],
  ""hlsl_update_request"": """"
}");
            sb.AppendLine();
            sb.AppendLine("When needs_hlsl_change is TRUE, populate hlsl_update_request like this example:");
            sb.AppendLine(@"{
  ""needs_hlsl_change"": true,
  ""reason"": ""No stripe property exists; new stripe geometry must be added to the HLSL."",
  ""material_changes"": [],
  ""hlsl_update_request"": ""Add horizontal stripes to the scarf section of the snowman. Introduce a '_StripeCount' float property (range 2-20, default 6) and a '_StripeColor' color property (default red). The stripes should tile evenly across the scarf UV region. All other parts of the snowman (body, hat, buttons) must remain unchanged.""
}");
            sb.AppendLine();
            sb.AppendLine("RULES for material_changes values:");
            sb.AppendLine("- For property_type 'float' or 'range': set float_value to the new scalar.");
            sb.AppendLine("- For property_type 'color': set r, g, b, a in 0.0-1.0 range.");
            sb.AppendLine("- For property_type 'vector': set x, y, z, w.");
            sb.AppendLine("- Always set description to a short human-readable summary of the change.");
            sb.AppendLine("RULES for hlsl_update_request:");
            sb.AppendLine("- Name the exact properties/features to add.");
            sb.AppendLine("- Describe what the shader should look like AFTER the change so a VLM can verify it.");
            sb.AppendLine("- Keep it focused — only what needs to change, not the whole shader.");

            string raw = await GeminiApiService.CallGeminiAsync(sb.ToString(), geminiKey);
            if (string.IsNullOrEmpty(raw))
            {
                Debug.LogWarning("[EditClassifier] Gemini returned null — defaulting to HLSL update path.");
                return new EditClassification
                {
                    needs_hlsl_change  = true,
                    reason             = "LLM unavailable.",
                    hlsl_update_request = editRequest
                };
            }

            // Strip markdown fences if present
            var m = System.Text.RegularExpressions.Regex.Match(
                raw, @"```(?:json)?\s*([\s\S]*?)```",
                System.Text.RegularExpressions.RegexOptions.Multiline);
            if (m.Success) raw = m.Groups[1].Value.Trim();
            else raw = raw.Trim();

            try
            {
                var cls = JsonConvert.DeserializeObject<EditClassification>(raw);
                if (cls.material_changes == null) cls.material_changes = new List<MaterialPropertyChange>();
                Debug.Log($"[EditClassifier] needs_hlsl_change={cls.needs_hlsl_change}  reason={cls.reason}");
                return cls;
            }
            catch (Exception ex)
            {
                Debug.LogWarning($"[EditClassifier] JSON parse failed ({ex.Message}) — falling back to HLSL update.\nRaw: {raw.Substring(0, Math.Min(300, raw.Length))}");
                return new EditClassification
                {
                    needs_hlsl_change   = true,
                    reason              = "Classification parse failed.",
                    hlsl_update_request = editRequest
                };
            }
        }
    }
}
