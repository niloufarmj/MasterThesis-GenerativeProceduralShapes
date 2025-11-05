using UnityEditor;
using UnityEngine;
using System;
using System.IO; // For file saving
using System.Collections.Generic; // For the queue
using ShaderGraphGenerator; // Import the runtime namespace
using System.Text;

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

        /// <summary>
        /// NEW: Builds the master prompt to send to the LLM.
        /// </summary>
        public static string BuildLLMPrompt(string userInput)
        {
            var sb = new StringBuilder();
            sb.AppendLine("You are a Unity HLSL shader expert. Your sole purpose is to generate code for a Unity ShaderGraph Custom Function Node.");
            sb.AppendLine("Your entire response MUST be a single, raw JSON object and nothing else. Do not use markdown ticks (```json) or any other formatting.");
            sb.AppendLine("\nThe user wants a shader function based on this description:");
            sb.AppendLine($"--- USER DESCRIPTION ---");
            sb.AppendLine(userInput);
            sb.AppendLine($"--- END DESCRIPTION ---");
            sb.AppendLine("\nFollow these rules STRICTLY:");
            sb.AppendLine("1. The HLSL function must be `void FunctionName_float(...)`.");
            sb.AppendLine("2. The *first* parameter MUST be `float2 UV`.");
            sb.AppendLine("3. The *last* parameter MUST be `out float4 outColor`.");
            sb.AppendLine("4. All other 'dynamic' parameters from the user's prompt (like 'dynamic size') MUST be input parameters (e.g., `float size`, `float rotation`).");
            sb.AppendLine("5. The generated JSON object must have this exact structure:");
            sb.AppendLine("{\"file_name\": \"YourFileName\", \"hlsl_code\": \"YourHLSLCode...\", \"properties\": [ ... ]}");
            sb.AppendLine("6. `file_name` should be a PascalCase version of the function name, without '_float'.");
            sb.AppendLine("7. `hlsl_code` must be a valid, complete HLSL function as a JSON string.");
            sb.AppendLine("8. `properties` must be a JSON array of *only* the input parameters (excluding `UV`).");
            sb.AppendLine("9. Each object in `properties` MUST have this structure:");
            sb.AppendLine("{\"name\": \"paramName\", \"type\": \"paramType\", \"default_value\": {\"x\":0.0, \"y\":0.0, \"z\":0.0, \"w\":0.0}}");
            sb.AppendLine("10. For `default_value`, provide reasonable values that create a visible, centered result:");
            sb.AppendLine("   - For `float`: {\"x\": 0.5, \"y\": 0, \"z\": 0, \"w\": 0}");
            sb.AppendLine("   - For `float2`: {\"x\": 0.5, \"y\": 0.5, \"z\": 0, \"w\": 0}");
            sb.AppendLine("   - For `float3`: {\"x\": 1.0, \"y\": 0.0, \"z\": 1.0, \"w\": 0} (e.g., a color)");
            sb.AppendLine("   - For `float4`/`Color`: {\"x\": 1.0, \"y\": 0.0, \"z\": 1.0, \"w\": 1.0} (e.g., a color with alpha)");
            return sb.ToString();
        }

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
            bool captureScreenshot = false,
            string screenshotPath = null) 
        {
            GameObject quad = GameObject.CreatePrimitive(PrimitiveType.Quad);
            quad.name = $"{material.shader.name} Preview Quad";

            quad.GetComponent<MeshRenderer>().sharedMaterial = material;
            
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

        /// <summary>
        /// NEW: Creates the .hlsl file on disk from the LLM response.
        /// </summary>
        public static string CreateHLSLFile(string fileName, string hlslCode, string folderPath = "Assets/ShaderGraphs/Generated/HLSL")
        {
            if (!Directory.Exists(folderPath))
            {
                Directory.CreateDirectory(folderPath);
            }

            string filePath = Path.Combine(folderPath, $"{fileName}.hlsl");
            File.WriteAllText(filePath, hlslCode);

            AssetDatabase.ImportAsset(filePath);
            Debug.Log($"✓ Created HLSL file at: {filePath}");
            return filePath;
        }
        
        /// <summary>
        /// NEW: Sets specific properties on a material from the LLM response.
        /// </summary>
        public static void SetDefaultMaterialProperties(Material material, List<LLMShaderProperty> properties)
        {
            if (material == null || properties == null) return;

            foreach (var prop in properties)
            {
                if (!material.HasProperty(prop.name))
                {
                    Debug.LogWarning($"Material '{material.name}' does not have property '{prop.name}'. Skipping.");
                    continue;
                }

                var val = prop.default_value;
                switch (prop.type.ToLower())
                {
                    case "float":
                        material.SetFloat(prop.name, val.x);
                        break;
                    case "float2":
                        material.SetVector(prop.name, new Vector4(val.x, val.y, 0, 0));
                        break;
                    case "float3":
                        material.SetVector(prop.name, new Vector4(val.x, val.y, val.z, 0));
                        break;
                    case "float4":
                        material.SetVector(prop.name, new Vector4(val.x, val.y, val.z, val.w));
                        break;
                    default:
                        Debug.LogWarning($"Unsupported property type: {prop.type}");
                        break;
                }
            }
            Debug.Log($"✓ Set default properties on material: {material.name}");
        }
    }
}