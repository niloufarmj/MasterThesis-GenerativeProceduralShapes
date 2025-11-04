using UnityEditor;
using UnityEngine;
using System;
using ShaderGraphGenerator; // Import the runtime namespace

namespace ShaderGraphGenerator.Editor
{
    /// <summary>
    /// Shared utility functions for the ShaderGraph Generator editor tools
    /// </summary>
    public static class ShaderGraphGeneratorEditorUtility
    {
        public static Material CreateMaterialForShaderGraph(string shaderGraphPath)
        {
            try
            {
                Shader shader = AssetDatabase.LoadAssetAtPath<Shader>(shaderGraphPath);
                if (shader == null)
                {
                    // Try to load again after a short delay, as AssetDatabase refresh might be slow
                    System.Threading.Thread.Sleep(100); // Small delay
                    shader = AssetDatabase.LoadAssetAtPath<Shader>(shaderGraphPath);
                    if (shader == null)
                    {
                        Debug.LogError($"Could not load shader at path: {shaderGraphPath}. Material not created.");
                        return null;
                    }
                }

                Material mat = new Material(shader);
                string materialPath = shaderGraphPath.Replace(".shadergraph", ".mat");

                // Ensure unique path
                materialPath = AssetDatabase.GenerateUniqueAssetPath(materialPath);

                AssetDatabase.CreateAsset(mat, materialPath);

                Debug.Log($"✓ Created Material: {materialPath}");
                return mat;
            }
            catch (Exception ex)
            {
                Debug.LogError($"Failed to create material for {shaderGraphPath}: {ex.Message}");
                return null;
            }
        }

        public static GameObject CreatePreviewQuad(Material material, HLSLFunctionInfo functionInfo)
        {
            GameObject quad = GameObject.CreatePrimitive(PrimitiveType.Quad);
            quad.name = $"{material.shader.name} Preview Quad";

            // Ensure we are getting the shared material, not an instance
            quad.GetComponent<MeshRenderer>().sharedMaterial = material;

            // Set random properties
            SetRandomMaterialProperties(material, functionInfo);

            // Select and frame it in the scene
            Selection.activeGameObject = quad;
            if (SceneView.lastActiveSceneView != null)
            {
                SceneView.lastActiveSceneView.FrameSelected();
            }

            return quad;
        }

        public static void SetRandomMaterialProperties(Material material, HLSLFunctionInfo functionInfo)
        {
            if (material == null || functionInfo == null) return;

            foreach (var param in functionInfo.InputParameters)
            {
                // Shader properties in the material are prefixed with _ by default, but
                // ShaderGraph properties (since v7) use the exact name.
                // We'll check for both, starting with the exact name.
                string propName = param.Name;
                if (!material.HasProperty(propName))
                {
                    // Fallback for older versions or non-graph properties
                    propName = $"_{param.Name}";
                    if (!material.HasProperty(propName))
                    {
                        continue; // Skip (e.g., this was the UV param)
                    }
                }

                try
                {
                    switch (param.Type.ToLower())
                    {
                        case "float":
                            material.SetFloat(propName, UnityEngine.Random.Range(0.1f, 0.45f));
                            break;
                        case "float2":
                            material.SetVector(propName, new Vector4(UnityEngine.Random.Range(0.3f, 0.6f), UnityEngine.Random.Range(0.3f, 0.6f), 0, 0));
                            break;
                        case "float3":
                            material.SetVector(propName, new Vector4(UnityEngine.Random.Range(0f, 1f), UnityEngine.Random.Range(0f, 1f), UnityEngine.Random.Range(0f, 1f), 0));
                            break;
                        case "float4":
                            if (param.IsColorProperty())
                            {
                                // Use a bright, saturated color
                                material.SetColor(propName, UnityEngine.Random.ColorHSV(0f, 1f, 0.8f, 1f, 1f, 1f, 1f, 1f));
                            }
                            else
                            {
                                material.SetVector(propName, new Vector4(UnityEngine.Random.Range(0f, 1f), UnityEngine.Random.Range(0f, 1f), UnityEngine.Random.Range(0f, 1f), UnityEngine.Random.Range(0f, 1f)));
                            }
                            break;
                    }
                }
                catch (Exception ex)
                {
                    Debug.LogWarning($"Could not set property {propName}: {ex.Message}");
                }
            }

            Debug.Log($"✓ Set random properties on material: {material.name}");
        }
    }
}