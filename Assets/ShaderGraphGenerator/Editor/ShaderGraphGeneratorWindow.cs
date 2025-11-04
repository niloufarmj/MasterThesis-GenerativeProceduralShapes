using UnityEditor;
using UnityEngine;
using ShaderGraphGenerator; // Import the runtime namespace

namespace ShaderGraphGenerator.Editor
{
    /// <summary>
    /// Unity Editor integration for easy ShaderGraph generation
    /// </summary>
    public class ShaderGraphGeneratorWindow : EditorWindow
    {
        private UnityEngine.Object hlslFile;
        private string outputPath = "Assets/ShaderGraphs/Generated.shadergraph";
        private bool useTransparency = false;
        private bool createMaterial = true;
        private bool createPreviewQuad = true;

        [MenuItem("Tools/ShaderGraph Generator")]
        public static void ShowWindow()
        {
            GetWindow<ShaderGraphGeneratorWindow>("ShaderGraph Generator");
        }

        private void OnGUI()
        {
            GUILayout.Label("HLSL to ShaderGraph Generator", EditorStyles.boldLabel);
            EditorGUILayout.Space();

            hlslFile = EditorGUILayout.ObjectField("HLSL File", hlslFile, typeof(UnityEngine.Object), false);
            outputPath = EditorGUILayout.TextField("Output Path", outputPath);
            useTransparency = EditorGUILayout.Toggle("Use Transparency", useTransparency);
            createMaterial = EditorGUILayout.Toggle("Create Material", createMaterial);
            createPreviewQuad = EditorGUILayout.Toggle("Create Preview Quad", createPreviewQuad);

            EditorGUILayout.Space();

            if (GUILayout.Button("Generate ShaderGraph"))
            {
                if (hlslFile == null)
                {
                    EditorUtility.DisplayDialog("Error", "Please select an HLSL file", "OK");
                    return;
                }

                string hlslPath = AssetDatabase.GetAssetPath(hlslFile);
                if (string.IsNullOrEmpty(hlslPath))
                {
                    EditorUtility.DisplayDialog("Error", "Could not get asset path for the selected object.", "OK");
                    return;
                }

                string guid = AssetDatabase.AssetPathToGUID(hlslPath);
                if (string.IsNullOrEmpty(guid))
                {
                    EditorUtility.DisplayDialog("Error", "Could not get GUID for the selected asset.", "OK");
                    return;
                }

                try
                {
                    // 1. Generate the ShaderGraph (and get function info back)
                    HLSLFunctionInfo functionInfo = ShaderGraphJSONGenerator.GenerateFromHLSL(hlslPath, guid, outputPath, useTransparency);

                    // 2. Refresh the AssetDatabase to compile the new graph
                    AssetDatabase.Refresh();

                    string successMessage = $"ShaderGraph generated at:\n{outputPath}";
                    Material mat = null;

                    // 3. Create the material if toggled
                    if (createMaterial)
                    {
                        // Use the new utility class
                        mat = ShaderGraphGeneratorEditorUtility.CreateMaterialForShaderGraph(outputPath);
                        if (mat != null)
                        {
                            successMessage += $"\n\nMaterial created at:\n{AssetDatabase.GetAssetPath(mat)}";
                        }
                    }

                    // 4. Create the quad if toggled (and material exists)
                    if (createPreviewQuad && mat != null && functionInfo != null)
                    {
                        // Use the new utility class
                        GameObject quad = ShaderGraphGeneratorEditorUtility.CreatePreviewQuad(mat, functionInfo);
                        successMessage += $"\n\nCreated and selected Preview Quad: {quad.name}";
                    }

                    // 5. Refresh again to show the new material/quad
                    AssetDatabase.Refresh();

                    EditorUtility.DisplayDialog("Success", successMessage, "OK");
                }
                catch (System.Exception ex)
                {
                    EditorUtility.DisplayDialog("Error", $"Failed to generate ShaderGraph:\n{ex.Message}", "OK");
                }
            }

            EditorGUILayout.Space();
            EditorGUILayout.HelpBox(
                "This tool parses HLSL functions and generates complete ShaderGraph JSON files.\n\n" +
                "Requirements:\n" +
                "• HLSL function must follow format: void FunctionName(params)\n" +
                "• Use 'out' modifier for output parameters\n" +
                "• The first float2 parameter is connected to a UV node\n" +
                "• float4 params with 'color' in the name become Color properties\n" +
                "• Other parameters become shader properties\n\n" +
                "Transparency:\n" +
                "• Check 'Use Transparency' for shaders with alpha output\n" +
                "• float4 outputs automatically connect RGB→BaseColor, A→Alpha",
                MessageType.Info);
        }
    }
}