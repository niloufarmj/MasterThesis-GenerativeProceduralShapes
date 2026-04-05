using System;
using System.Collections.Generic;
using System.IO;
using UnityEditor;
using UnityEditor.Rendering;
using UnityEngine;

namespace ShaderGraphGenerator.Editor
{
    /// <summary>
    /// Helpers for creating materials, preview quads, screenshots, and setting material properties.
    /// </summary>
    public static class MaterialPreviewHelper
    {
        // Screenshot actions are queued so they run after the current editor frame is rendered.
        private static Queue<Action> s_UpdateQueue = new Queue<Action>();

        // ─── Material creation ────────────────────────────────────────────────

        public static Material CreateMaterialForShaderGraph(string shaderGraphPath)
        {
            try
            {
                Shader shader = AssetDatabase.LoadAssetAtPath<Shader>(shaderGraphPath);
                if (shader == null)
                {
                    System.Threading.Thread.Sleep(100);
                    shader = AssetDatabase.LoadAssetAtPath<Shader>(shaderGraphPath);
                    if (shader == null)
                    {
                        Debug.LogError($"Could not load shader at path: {shaderGraphPath}. Material not created.");
                        return null;
                    }
                }

                Material mat     = new Material(shader);
                string matPath   = shaderGraphPath.Replace(".shadergraph", ".mat");
                matPath          = AssetDatabase.GenerateUniqueAssetPath(matPath);
                AssetDatabase.CreateAsset(mat, matPath);
                Debug.Log($"✓ Created Material: {matPath}");
                return mat;
            }
            catch (Exception ex)
            {
                Debug.LogError($"Failed to create material for {shaderGraphPath}: {ex.Message}");
                return null;
            }
        }

        // ─── Preview quad ─────────────────────────────────────────────────────

        public static GameObject CreatePreviewQuad(
            Material material,
            bool captureScreenshot = false,
            string screenshotPath  = null)
        {
            GameObject quad = GameObject.CreatePrimitive(PrimitiveType.Quad);
            quad.name = $"{material.shader.name} Preview Quad";
            quad.GetComponent<MeshRenderer>().sharedMaterial = material;
            Selection.activeGameObject = quad;

            if (SceneView.lastActiveSceneView != null)
                SceneView.lastActiveSceneView.FrameSelected();

            if (captureScreenshot)
            {
                if (string.IsNullOrEmpty(screenshotPath))
                    screenshotPath = AssetDatabase.GetAssetPath(material).Replace(".mat", ".png");

                string directory = Path.GetDirectoryName(screenshotPath);
                if (!Directory.Exists(directory))
                    Directory.CreateDirectory(directory);

                Camera camera = Camera.main;
                if (camera == null)
                    Debug.LogWarning("Cannot capture screenshot: No main camera found.");
                else
                    QueueOnUpdate(() => CaptureAndSaveView(camera, screenshotPath));
            }

            return quad;
        }

        // ─── Screenshot capture ───────────────────────────────────────────────

        private static void QueueOnUpdate(Action action)
        {
            if (s_UpdateQueue.Count == 0)
                EditorApplication.update += ProcessUpdateQueue;
            s_UpdateQueue.Enqueue(action);
        }

        private static void ProcessUpdateQueue()
        {
            EditorApplication.update -= ProcessUpdateQueue;
            while (s_UpdateQueue.Count > 0)
            {
                try   { s_UpdateQueue.Dequeue()?.Invoke(); }
                catch (Exception ex) { Debug.LogError($"Error in queued editor action: {ex.Message}"); }
            }
        }

        private static void CaptureAndSaveView(Camera camera, string filePath, int width = 512, int height = 512)
        {
            if (camera == null)
            {
                Debug.LogError("Cannot capture screenshot: Camera is null.");
                return;
            }

            RenderTexture rt             = new RenderTexture(width, height, 24);
            rt.Create();
            RenderTexture previousTarget = camera.targetTexture;
            camera.targetTexture         = rt;
            camera.Render();
            camera.targetTexture         = previousTarget;

            RenderTexture previousActive = RenderTexture.active;
            RenderTexture.active         = rt;

            Texture2D tex = new Texture2D(width, height, TextureFormat.RGB24, false);
            tex.ReadPixels(new Rect(0, 0, width, height), 0, 0);
            tex.Apply();
            RenderTexture.active = previousActive;

            try
            {
                File.WriteAllBytes(filePath, tex.EncodeToPNG());
                Debug.Log($"✓ Screenshot saved to: {filePath}");
                AssetDatabase.ImportAsset(filePath);
            }
            catch (Exception ex) { Debug.LogError($"Failed to save screenshot: {ex.Message}"); }
            finally
            {
                UnityEngine.Object.DestroyImmediate(tex);
                rt.Release();
                UnityEngine.Object.DestroyImmediate(rt);
            }
        }

        // ─── HLSL file creation ───────────────────────────────────────────────

        public static string CreateHLSLFile(
            string fileName,
            string hlslCode,
            string folderPath = "Assets/ShaderGraphs/Generated/HLSL")
        {
            if (!Directory.Exists(folderPath))
                Directory.CreateDirectory(folderPath);

            string filePath = Path.Combine(folderPath, $"{fileName}.hlsl");
            File.WriteAllText(filePath, hlslCode);
            AssetDatabase.ImportAsset(filePath);
            Debug.Log($"✓ Created HLSL file at: {filePath}");
            return filePath;
        }

        // ─── Material property setters ────────────────────────────────────────

        /// <summary>
        /// Sets random values on material properties — useful for a quick visual preview.
        /// </summary>
        public static void SetRandomMaterialProperties(Material material, HLSLFunctionInfo functionInfo)
        {
            if (material == null || functionInfo == null) return;

            foreach (var param in functionInfo.InputParameters)
            {
                string propName = param.Name;
                if (!material.HasProperty(propName))
                {
                    propName = $"_{param.Name}";
                    if (!material.HasProperty(propName)) continue;
                }

                try
                {
                    switch (param.Type.ToLower())
                    {
                        case "float":
                            material.SetFloat(propName, UnityEngine.Random.Range(0.1f, 0.45f));
                            break;
                        case "float2":
                            material.SetVector(propName, new Vector4(
                                UnityEngine.Random.Range(0.3f, 0.6f),
                                UnityEngine.Random.Range(0.3f, 0.6f), 0, 0));
                            break;
                        case "float3":
                            material.SetVector(propName, new Vector4(
                                UnityEngine.Random.Range(0f, 1f),
                                UnityEngine.Random.Range(0f, 1f),
                                UnityEngine.Random.Range(0f, 1f), 0));
                            break;
                        case "float4":
                            if (param.IsColorProperty())
                                material.SetColor(propName,
                                    UnityEngine.Random.ColorHSV(0f, 1f, 0.8f, 1f, 1f, 1f, 1f, 1f));
                            else
                                material.SetVector(propName, new Vector4(
                                    UnityEngine.Random.Range(0f, 1f),
                                    UnityEngine.Random.Range(0f, 1f),
                                    UnityEngine.Random.Range(0f, 1f),
                                    UnityEngine.Random.Range(0f, 1f)));
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

        /// <summary>
        /// Applies LLM-suggested default values to a material's properties.
        /// Skips zero-valued properties so a random fallback from SetRandomMaterialProperties stays visible.
        /// </summary>
        public static void SetDefaultMaterialProperties(
            Material material,
            List<LLMShaderProperty> properties)
        {
            if (material == null || properties == null) return;

            foreach (var prop in properties)
            {
                string propName = prop.name;
                if (!material.HasProperty(propName))
                {
                    string alt = "_" + prop.name;
                    if (material.HasProperty(alt))
                        propName = alt;
                    else
                    {
                        Debug.LogWarning($"Material '{material.name}' has no property '{prop.name}' or '{alt}'. Skipping.");
                        continue;
                    }
                }

                var    val  = prop.default_value;
                string type = prop.type?.ToLowerInvariant() ?? "";

                try
                {
                    switch (type)
                    {
                        case "float":
                            if (Mathf.Abs(val.x) < 0.0001f)
                            {
                                Debug.LogWarning($"[SetDefaultProps] Skipping float '{prop.name}' = 0 (random fallback kept).");
                                break;
                            }
                            material.SetFloat(propName, val.x);
                            break;

                        case "vector2":
                        case "float2":
                            material.SetVector(propName, new Vector4(val.x, val.y, 0f, 0f));
                            break;

                        case "vector3":
                        case "float3":
                            material.SetVector(propName, new Vector4(val.x, val.y, val.z, 0f));
                            break;

                        case "vector4":
                        case "float4":
                        case "color":
                        {
                            bool allZero = val.x < 0.001f && val.y < 0.001f &&
                                           val.z < 0.001f && val.w < 0.001f;
                            if (allZero)
                            {
                                Debug.LogWarning($"[SetDefaultProps] Skipping '{prop.name}' — all zero. Random fallback kept.");
                                break;
                            }
                            float alpha = val.w < 0.001f ? 1f : val.w;
                            material.SetColor(propName, new Color(val.x, val.y, val.z, alpha));
                            break;
                        }

                        default:
                            Debug.LogWarning($"Unsupported LLM property type '{prop.type}' for '{prop.name}'.");
                            break;
                    }
                }
                catch (Exception ex)
                {
                    Debug.LogWarning($"Failed to set material property '{propName}': {ex.Message}");
                }
            }

            // Force center parameters to (0.5, 0.5) regardless of LLM output
            foreach (var prop in properties)
            {
                if (prop.name.ToLower().Contains("center") && material.HasVector(prop.name))
                    material.SetVector(prop.name, new Vector4(0.5f, 0.5f, 0f, 0f));
            }

            Debug.Log($"✓ Set default LLM properties on material: {material.name}");
        }

        // ─── Shader validation ────────────────────────────────────────────────

#if UNITY_EDITOR
        public static bool HasShaderCompileErrors(Shader shader)
        {
            if (shader == null) return true;

            ShaderUtil.ClearShaderMessages(shader);

            var path = AssetDatabase.GetAssetPath(shader);
            if (!string.IsNullOrEmpty(path))
                AssetDatabase.ImportAsset(path, ImportAssetOptions.ForceUpdate);

            var messages = ShaderUtil.GetShaderMessages(shader);
            foreach (var msg in messages)
            {
                if (msg.severity == ShaderCompilerMessageSeverity.Error)
                {
                    Debug.LogError($"Shader compile error in '{shader.name}': {msg.message} (file: {msg.file}, line: {msg.line})");
                    return true;
                }
            }

            return false;
        }
#endif
    }
}
