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
        public static string BuildLLMPrompt(string userInput, bool useTransparency)
        {
            var sb = new StringBuilder();
            sb.AppendLine("You are a Unity HLSL shader expert. Your sole purpose is to generate VALID, COMPILABLE code for a Unity ShaderGraph Custom Function Node.");
            sb.AppendLine("Your entire response MUST be a single, raw JSON object and nothing else. Do not use markdown ticks (```json) or any other formatting.");

            sb.AppendLine("\n=== USER REQUEST ===");
            sb.AppendLine(userInput);
            sb.AppendLine("===================");

            sb.AppendLine("\n=== CRITICAL RULES / HLSL CODE REQUIREMENTS ===");
            sb.AppendLine("A final 'main' function, which ShaderGraph will call, MUST have this signature: void FunctionName_float(float2 UV, [other inputs...], out float4 outColor)");
            sb.AppendLine("HELPER FUNCTIONS: You are ENCOURAGED to write other helper functions (e.g., `float sdf_box(float2 p, float2 b)`) within the HLSL code. The 'main' function can then call these helpers. This is good practice for complex shapes.");
            sb.AppendLine("UV is [0..1]. Always center as float2 p = UV - 0.5; Do not remap to [-1,1].");
            sb.AppendLine("Inside means sd < 0. Use aa = max(fwidth(sd), 1e-5); and fill = 1 - smoothstep(0.0, aa, sd).");
            sb.AppendLine("Output outColor = float4(BaseColor * fill, 1.0) (or fill if transparent).");
            sb.AppendLine("Do not change vector dimensions: if the input is float2, keep float2 throughout unless explicitly building a float3.");
            sb.AppendLine("The JSON 'file_name' MUST match the function name prefix (<FileBase>).");
            sb.AppendLine("- FUNCTION ORDER: If you define any helper functions, they MUST appear *before* the main function {FileBase}_float.");
            sb.AppendLine("- Do NOT place helper functions below the main function — Unity’s HLSL compiler requires called functions to be declared earlier.");
            sb.AppendLine("- The main function {FileBase}_float must be the *last* function in the file.");
            sb.AppendLine("- RESIZABILITY: The final shape and any added features MUST be resizable via parameters even if not requested explicitly.");
            sb.AppendLine("  Include at least one explicit size/scale parameter (e.g., size or scale). When relevant, also expose radius and/or thickness.");
            sb.AppendLine("IMPLICIT/EQN SHAPES: If you use trigonometric/polar forms (e.g., atan2/sin/cos) they MUST produce a true signed distance.\r\n  Otherwise prefer a known SDF construction (box, circle, arcs, blends). Do not output mask-only formulas.");
            sb.AppendLine(" SCALING RULE: For any 'size'/'scale' parameter you MUST implement SDF scaling as:\r\n  sd_scaled(p) = scale * sd_base(p / scale). Do NOT scale coordinates as p *= size without compensating.\r\n\r\nAnd in your Forbidden Patterns add:");
            sb.AppendLine(" Direct coordinate scaling like 'p *= size;' or 'p = p * size;' (unless followed by 'sd = size * sd_base(p/size)')");
            sb.AppendLine("- Using atan2/sin/cos to return a mask without an actual signed distance");
            sb.AppendLine(" If a size/scale parameter exists, did you apply sd = size * sd0(p/size)?");
            sb.AppendLine(" If you used atan2/sin/cos, can you prove sd<0 inside and >0 outside with consistent units?");

            sb.AppendLine("\n=== REQUIRED JSON STRUCTURE ===");
            sb.AppendLine("{");
            sb.AppendLine("  \"file_name\": \"DescriptiveName\",");
            sb.AppendLine("  \"hlsl_code\": \"void FunctionName_float(float2 UV, float param1, out float4 outColor) { ... }\",");
            sb.AppendLine("  \"properties\": [");
            sb.AppendLine("    {\"name\": \"param1\", \"type\": \"float\", \"default_value\": {\"x\": 0.5, \"y\": 0, \"z\": 0, \"w\": 0}}");
            sb.AppendLine("  ]");
            sb.AppendLine("}");

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