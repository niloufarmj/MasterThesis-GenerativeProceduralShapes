using UnityEditor;
using UnityEngine;
using ShaderGraphGenerator; // Import the runtime namespace

namespace ShaderGraphGenerator.Editor
{
    /// <summary>
    /// Context menu for generating ShaderGraph from HLSL file
    /// </summary>
    public static class HLSLContextMenu
    {
        [MenuItem("Assets/Generate ShaderGraph from HLSL (Opaque)", false, 100)]
        private static void GenerateShaderGraphOpaque()
        {
            GenerateShaderGraph(false, false);
        }

        [MenuItem("Assets/Generate ShaderGraph from HLSL (Transparent)", false, 101)]
        private static void GenerateShaderGraphTransparent()
        {
            GenerateShaderGraph(true, false);
        }

        [MenuItem("Assets/Generate ShaderGraph from HLSL (Puxelled)", false, 102)]
        private static void GenerateShaderGraphPixelation()
        {
            GenerateShaderGraph(true, true);
        }

        private static void GenerateShaderGraph(bool useTransparency, bool pixelation)
        {
            var selected = Selection.activeObject;
            if (selected == null) return;

            string hlslPath = AssetDatabase.GetAssetPath(selected);
            if (string.IsNullOrEmpty(hlslPath) || !hlslPath.EndsWith(".hlsl")) return;

            string guid = AssetDatabase.AssetPathToGUID(hlslPath);
            string outputPath = hlslPath.Replace(".hlsl", ".shadergraph");

            try
            {
                // 1. Generate ShaderGraph (and get info)
                HLSLFunctionInfo functionInfo = ShaderGraphJSONGenerator.GenerateFromHLSL(hlslPath, guid, outputPath, useTransparency, pixelation);

                // 2. Refresh to compile graph
                AssetDatabase.Refresh();

                // 3. Always create material for context menu
                // Use the new utility class
                Material mat = MaterialPreviewHelper.CreateMaterialForShaderGraph(outputPath);
                string successMessage = $"ShaderGraph generated:\n{outputPath}";

                if (mat != null)
                {
                    successMessage += $"\n\nMaterial created:\n{AssetDatabase.GetAssetPath(mat)}";

                    // 4. **MODIFIED**: Always create preview quad and request screenshot
                    if (functionInfo != null)
                    {
                        // We now call this *before* creating the quad.
                        MaterialPreviewHelper.SetRandomMaterialProperties(mat, functionInfo);

                        // We pass 'true' for captureScreenshot
                        // We pass 'null' for the path, so the utility creates a default path
                        GameObject quad = MaterialPreviewHelper.CreatePreviewQuad(
                            mat,
                            true,       // captureScreenshot
                            null);      // Use default path
                            
                        successMessage += $"\n\nCreated and selected Preview Quad: {quad.name}";
                    }
                }

                // 5. Refresh again to show material/quad
                AssetDatabase.Refresh();

                EditorUtility.DisplayDialog("Success", successMessage, "OK");
            }
            catch (System.Exception ex)
            {
                EditorUtility.DisplayDialog("Error", $"Failed:\n{ex.Message}", "OK");
            }
        }

        [MenuItem("Assets/Generate ShaderGraph from HLSL (Opaque)", true)]
        [MenuItem("Assets/Generate ShaderGraph from HLSL (Transparent)", true)]
        private static bool ValidateGenerateShaderGraph()
        {
            var selected = Selection.activeObject;
            if (selected == null) return false;

            string path = AssetDatabase.GetAssetPath(selected);
            return !string.IsNullOrEmpty(path) && path.EndsWith(".hlsl");
        }
    }
}