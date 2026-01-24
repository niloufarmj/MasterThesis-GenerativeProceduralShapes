using UnityEditor;
using UnityEngine;

namespace ShaderGraphGenerator.Editor
{
    /// <summary>
    /// Reusable UI drawing utilities for the ShaderGraph Generator window.
    /// Keeps the main window class clean and focused on logic.
    /// </summary>
    public static class GeneratorWindowUI
    {
        // ═══════════════════════════════════════════════════════════════════════
        //  STYLES (Lazy-initialized)
        // ═══════════════════════════════════════════════════════════════════════

        private static GUIStyle _titleStyle;
        private static GUIStyle _subtitleStyle;
        private static GUIStyle _sectionHeaderStyle;
        private static GUIStyle _footerStyle;
        private static GUIStyle _tipStyle;

        public static GUIStyle TitleStyle => _titleStyle ??= new GUIStyle(EditorStyles.boldLabel)
        {
            fontSize = 16,
            alignment = TextAnchor.MiddleCenter
        };

        public static GUIStyle SubtitleStyle => _subtitleStyle ??= new GUIStyle(EditorStyles.miniLabel)
        {
            alignment = TextAnchor.MiddleCenter,
            fontStyle = FontStyle.Italic
        };

        public static GUIStyle SectionHeaderStyle => _sectionHeaderStyle ??= new GUIStyle(EditorStyles.boldLabel)
        {
            fontSize = 12,
            margin = new RectOffset(0, 0, 5, 5)
        };

        public static GUIStyle FooterStyle => _footerStyle ??= new GUIStyle(EditorStyles.miniLabel)
        {
            alignment = TextAnchor.MiddleCenter,
            fontStyle = FontStyle.Italic
        };

        public static GUIStyle TipStyle => _tipStyle ??= new GUIStyle(EditorStyles.wordWrappedMiniLabel)
        {
            richText = true
        };

        // ═══════════════════════════════════════════════════════════════════════
        //  HEADER & FOOTER
        // ═══════════════════════════════════════════════════════════════════════

        public static void DrawHeader()
        {
            EditorGUILayout.BeginHorizontal();
            GUILayout.FlexibleSpace();
            GUILayout.Label("SDF ShaderGraph Generator", TitleStyle);
            GUILayout.FlexibleSpace();
            EditorGUILayout.EndHorizontal();

            EditorGUILayout.BeginHorizontal();
            GUILayout.FlexibleSpace();
            GUILayout.Label("Procedural 2D Assets via Signed Distance Functions", SubtitleStyle);
            GUILayout.FlexibleSpace();
            EditorGUILayout.EndHorizontal();
        }

        public static void DrawFooter()
        {
            EditorGUILayout.BeginHorizontal();
            GUILayout.FlexibleSpace();
            GUILayout.Label("SDF ShaderGraph Generator v1.0 • Knowledge Base: 250+ Verified Primitives", FooterStyle);
            GUILayout.FlexibleSpace();
            EditorGUILayout.EndHorizontal();
        }

        public static void DrawSectionHeader(string title)
        {
            EditorGUILayout.LabelField(title, SectionHeaderStyle);
        }

        // ═══════════════════════════════════════════════════════════════════════
        //  PROMPT GUIDE
        // ═══════════════════════════════════════════════════════════════════════

        /// <summary>
        /// Draws the prompt writing guide with example buttons.
        /// Returns the selected example prompt if a button was clicked, null otherwise.
        /// </summary>
        public static string DrawPromptGuide()
        {
            string selectedExample = null;

            EditorGUILayout.BeginVertical(EditorStyles.helpBox);

            // Good Practices
            EditorGUILayout.LabelField("✅ Good Prompt Practices", EditorStyles.boldLabel);
            EditorGUILayout.LabelField(
                "• <b>Be specific about shape type:</b> \"a 5-pointed star\", \"hexagon\", \"rounded rectangle\"\n" +
                "• <b>Mention adjustable parameters:</b> \"with adjustable size, rotation, and color\"\n" +
                "• <b>Describe visual features:</b> \"with smooth edges\", \"with outline stroke\"\n" +
                "• <b>Specify centering:</b> \"centered at UV 0.5, 0.5\"",
                TipStyle);

            EditorGUILayout.Space(8);

            // Examples
            EditorGUILayout.LabelField("💡 Example Prompts", EditorStyles.boldLabel);

            if (GUILayout.Button("Circle with outline", EditorStyles.miniButton))
                selectedExample = "a circle with adjustable radius, fill color, outline thickness, and outline color, centered";

            if (GUILayout.Button("Rounded rectangle", EditorStyles.miniButton))
                selectedExample = "a rounded rectangle with adjustable width, height, corner radius, and color, centered";

            if (GUILayout.Button("5-pointed star", EditorStyles.miniButton))
                selectedExample = "a 5-pointed star with adjustable size, inner radius ratio, rotation, and color, centered";

            if (GUILayout.Button("Heart shape", EditorStyles.miniButton))
                selectedExample = "a heart shape with adjustable size, color, and rotation, smooth anti-aliased edges, centered";

            if (GUILayout.Button("Gear/cog icon", EditorStyles.miniButton))
                selectedExample = "a gear shape with adjustable tooth count, outer radius, inner radius, tooth depth, and color";

            EditorGUILayout.Space(8);

            // What to Avoid
            EditorGUILayout.LabelField("⚠️ What to Avoid", EditorStyles.boldLabel);
            EditorGUILayout.LabelField(
                "• <b>Vague descriptions:</b> \"something cool\" → Be specific!\n" +
                "• <b>3D requests:</b> This tool generates 2D SDF shapes only\n" +
                "• <b>Textures/images:</b> Procedural math only, no external assets\n" +
                "• <b>Animation:</b> Shapes are static (parameters can be animated externally)",
                TipStyle);

            EditorGUILayout.EndVertical();

            return selectedExample;
        }

        // ═══════════════════════════════════════════════════════════════════════
        //  HLSL REQUIREMENTS INFO
        // ═══════════════════════════════════════════════════════════════════════

        public static void DrawHLSLRequirementsInfo()
        {
            EditorGUILayout.HelpBox(
                "HLSL Function Requirements:\n" +
                "• Signature: void FunctionName_float(float2 UV, [...params], out float4 outColor)\n" +
                "• First parameter must be float2 UV\n" +
                "• Last parameter must be out float4 outColor\n" +
                "• Parameters with 'color' in name → Color properties\n" +
                "• Define helper functions before main function",
                MessageType.Info);
        }

        // ═══════════════════════════════════════════════════════════════════════
        //  CONFIG WARNING
        // ═══════════════════════════════════════════════════════════════════════

        public static void DrawConfigMissingWarning()
        {
            EditorGUILayout.HelpBox(
                "Config not found! Create a ShaderGraphGeneratorConfig asset at:\n" +
                "Assets/ShaderGraphGeneratorConfig.asset\n\n" +
                "Right-click in Project → Create → ShaderGraphGenerator → Config",
                MessageType.Warning);
        }
    }
}
