using UnityEditor;
using UnityEngine;
using System;
using System.IO; // For file saving
using System.Collections.Generic; // For the queue
using ShaderGraphGenerator; // Import the runtime namespace

namespace ShaderGraphGenerator.Editor
{
    /// <summary>
    /// Shared utility functions for the ShaderGraph Generator editor tools
    /// </summary>
    public static class ShaderGraphGeneratorEditorUtility
    {
        // We use a queue to ensure screenshots happen *after* the current
        // editor script is finished and a new frame has been rendered.
        private static Queue<Action> s_UpdateQueue = new Queue<Action>();

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

        public static GameObject CreatePreviewQuad(
            Material material,
            HLSLFunctionInfo functionInfo,
            bool captureScreenshot = false,
            string screenshotPath = null) 
        {
            GameObject quad = GameObject.CreatePrimitive(PrimitiveType.Quad);
            quad.name = $"{material.shader.name} Preview Quad";

            quad.GetComponent<MeshRenderer>().sharedMaterial = material;
            SetRandomMaterialProperties(material, functionInfo);
            Selection.activeGameObject = quad;

            if (SceneView.lastActiveSceneView != null)
            {
                SceneView.lastActiveSceneView.FrameSelected();
            }

            // --- NEW: Queue the screenshot ---
            if (captureScreenshot)
            {
                // If no path is given, create one based on the material path
                if (string.IsNullOrEmpty(screenshotPath))
                {
                    screenshotPath = AssetDatabase.GetAssetPath(material).Replace(".mat", ".png");
                }

                // Ensure the directory exists
                string directory = Path.GetDirectoryName(screenshotPath);
                if (!Directory.Exists(directory))
                {
                    Directory.CreateDirectory(directory);
                }

                // Get the main camera (you can change this if needed)
                Camera camera = Camera.main;
                if (camera == null)
                {
                    Debug.LogWarning("Cannot capture screenshot: No main camera found.");
                }
                else
                {
                    QueueOnUpdate(() => CaptureAndSaveView(camera, screenshotPath));
                }
            }
            // --- END NEW ---

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

        /// <summary>
        /// Schedules an action to be run on the next EditorApplication.update
        /// </summary>
        private static void QueueOnUpdate(Action action)
        {
            if (s_UpdateQueue.Count == 0)
            {
                // If this is the first item, subscribe to the update loop
                EditorApplication.update += ProcessUpdateQueue;
            }
            s_UpdateQueue.Enqueue(action);
        }
        
        /// <summary>
        /// Runs once on the next editor update, executes all queued actions,
        /// and then unsubscribes itself.
        /// </summary>
        private static void ProcessUpdateQueue()
        {
            // Unsubscribe immediately so this only runs once
            EditorApplication.update -= ProcessUpdateQueue;

            // Run all actions
            while (s_UpdateQueue.Count > 0)
            {
                try
                {
                    Action action = s_UpdateQueue.Dequeue();
                    action?.Invoke();
                }
                catch (Exception ex)
                {
                    Debug.LogError($"Error in queued editor action: {ex.Message}");
                }
            }
        }

        /// <summary>
        /// Renders a camera's view to a texture and saves it as a PNG.
        /// </summary>
        private static void CaptureAndSaveView(Camera camera, string filePath, int width = 512, int height = 512)
        {
            if (camera == null)
            {
                Debug.LogError($"Cannot capture screenshot: Camera is null.");
                return;
            }

            // 1. Create a RenderTexture
            RenderTexture rt = new RenderTexture(width, height, 24);
            rt.Create();

            // 2. Temporarily set the camera's target to our RenderTexture
            RenderTexture previousTarget = camera.targetTexture;
            camera.targetTexture = rt;

            // 3. Render the camera's view
            camera.Render();

            // 4. Restore the camera's original target
            camera.targetTexture = previousTarget;

            // 5. Read the pixels from the RenderTexture
            RenderTexture previousActive = RenderTexture.active;
            RenderTexture.active = rt;
            
            Texture2D tex = new Texture2D(width, height, TextureFormat.RGB24, false);
            tex.ReadPixels(new Rect(0, 0, width, height), 0, 0);
            tex.Apply();

            RenderTexture.active = previousActive;

            // 6. Encode to PNG and save
            try
            {
                byte[] bytes = tex.EncodeToPNG();
                File.WriteAllBytes(filePath, bytes);

                Debug.Log($"✓ Screenshot saved to: {filePath}");

                // 7. Refresh AssetDatabase to show the new file
                AssetDatabase.ImportAsset(filePath);
            }
            catch (Exception ex)
            {
                Debug.LogError($"Failed to save screenshot: {ex.Message}");
            }
            finally
            {
                // 8. Clean up
                UnityEngine.Object.DestroyImmediate(tex);
                rt.Release();
                UnityEngine.Object.DestroyImmediate(rt);
            }
        }
    }
}