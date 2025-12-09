using UnityEditor;
using UnityEngine;
using System;
using System.IO; // For file saving
using System.Collections.Generic; // For the queue
using ShaderGraphGenerator; // Import the runtime namespace
using System.Text;
using UnityEditor.Rendering;

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

            sb.AppendLine("\n=== CRITICAL RULES (FOLLOW EXACTLY) ===");
            sb.AppendLine("1. Function signature MUST be: void FunctionName_float(float2 UV, [other inputs...], out float4 outColor)");
            sb.AppendLine("2. First parameter is ALWAYS `float2 UV`");
            sb.AppendLine("3. Last parameter is ALWAYS `out float4 outColor`");
            sb.AppendLine("4. UV coordinates range from (0,0) to (1,1). Center is (0.5, 0.5)");
            sb.AppendLine("5. ALWAYS write to outColor before returning (no early returns without setting outColor)");
            sb.AppendLine("6. Use float/float2/float3/float4 types ONLY");
            sb.AppendLine("7. Common HLSL functions available: length, dot, cross, normalize, lerp, saturate, step, smoothstep, sin, cos, atan2, fmod, abs, min, max, clamp, pow, exp, sqrt, frac, floor, ceil");
            sb.AppendLine("8. For shapes: calculate signed distance fields (SDF) for best results");
            sb.AppendLine($"9. Alpha channel usage: {(useTransparency ? "OUTPUT alpha in outColor.a (1.0 = opaque, 0.0 = transparent)" : "Always set alpha to 1.0 (opaque)")}");
            sb.AppendLine("- For transparency: compute a mask in [0,1] and always do");
            sb.AppendLine("  outColor = float4(Color.rgb * mask, mask);");

            sb.AppendLine("\n=== ALLOWED HLSL INTRINSICS (UNITY) ===");
            sb.AppendLine("You are writing HLSL, NOT GLSL. You may ONLY use these built-in functions without defining them:");
            sb.AppendLine("- Arithmetic / math: abs, sign, min, max, clamp, saturate, floor, ceil, round, frac, fmod,");
            sb.AppendLine("  pow, sqrt, rsqrt, exp, exp2, log, log2, sin, cos, tan, asin, acos, atan, atan2;");
            sb.AppendLine("- Vector math: dot, cross, length, distance, normalize;");
            sb.AppendLine("- Interpolation / step: lerp, smoothstep, step;");
            sb.AppendLine("- Derivatives / AA: fwidth, ddx, ddy;");
            sb.AppendLine("- Other: any standard HLSL function that Unity supports.");
            sb.AppendLine();
            sb.AppendLine("Do NOT use GLSL-specific functions like mix, fract, mod, inversesqrt, etc.");
            sb.AppendLine("If you want GLSL-like behavior, use the HLSL equivalents:");
            sb.AppendLine("- mix(a,b,t)  → lerp(a,b,t)");
            sb.AppendLine("- fract(x)    → frac(x)");
            sb.AppendLine("- mod(x,y)    → fmod(x,y)");
            sb.AppendLine();
            sb.AppendLine("If you want to use ANY function that is not in this list or a built-in HLSL intrinsic,");
            sb.AppendLine("you MUST define that function yourself ABOVE the main shape function in hlsl_code.");

            sb.AppendLine("\n=== REQUIRED JSON STRUCTURE ===");
            sb.AppendLine("{");
            sb.AppendLine("  \"file_name\": \"DescriptiveName\",");
            sb.AppendLine("  \"hlsl_code\": \"void FunctionName_float(float2 UV, float param1, out float4 outColor) { ... }\",");
            sb.AppendLine("  \"properties\": [");
            sb.AppendLine("    {\"name\": \"param1\", \"type\": \"float\", \"default_value\": {\"x\": 0.5, \"y\": 0, \"z\": 0, \"w\": 0}}");
            sb.AppendLine("  ]");
            sb.AppendLine("}");
            sb.AppendLine("- For color parameters, use \"type\": \"color\" and provide RGBA defaults:");
            sb.AppendLine("  { \"name\": \"Color\", \"type\": \"color\",");
            sb.AppendLine("    \"default_value\": { \"x\": 1.0, \"y\": 0.5, \"z\": 0.2, \"w\": 1.0 } }");

            sb.AppendLine("\n=== HLSL CODE REQUIREMENTS ===");
            sb.AppendLine("- Use descriptive variable names");
            sb.AppendLine("- Include comments for complex calculations");
            sb.AppendLine("- Center shapes at UV (0.5, 0.5) by default using: float2 centered = UV - 0.5;");
            sb.AppendLine("- Make size parameters control actual visual size (0.5 = half screen)");
            sb.AppendLine("- For rotation: use cos/sin with angle in radians");
            sb.AppendLine("- CRITICAL: ALWAYS use smoothstep() for anti-aliasing, NEVER use if/else for edges");
            sb.AppendLine("- CRITICAL: Use Signed Distance Fields (SDF) for shapes whenever possible");
            sb.AppendLine("- Anti-aliasing pattern: float edge = smoothstep(0.01, -0.01, sdf);");
            sb.AppendLine("- Final output pattern: outColor = float4(Color * edge, edge);");

            sb.AppendLine("\n=== COMMON SHAPE SDFs ===");
            sb.AppendLine("Circle: float dist = length(centered) - radius;");
            sb.AppendLine("Box/Rectangle: float2 d = abs(centered) - size; float dist = length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);");
            sb.AppendLine("Rounded Box: Same as box but subtract corner radius from result");
            sb.AppendLine("Triangle (Equilateral): Use the reference from Inigo Quilez");
            sb.AppendLine("Pentagon/Hexagon: Use polar coordinates: float angle = atan2(centered.y, centered.x);");
            sb.AppendLine("Star: Combine angular repetition with distance calculation");
            sb.AppendLine("Remember: All SDFs should output negative values INSIDE the shape, positive OUTSIDE");

            sb.AppendLine("\n=== SDF TEMPLATE ===");
            sb.AppendLine("1. Center UV: float2 centered = UV - 0.5;");
            sb.AppendLine("2. Scale by size: centered /= Size;");
            sb.AppendLine("3. Calculate SDF: float dist = [your SDF formula];");
            sb.AppendLine("4. Anti-alias: float edge = smoothstep(0.01, -0.01, dist);");
            sb.AppendLine("5. Output: outColor = float4(Color * edge, edge);");

            sb.AppendLine("\n=== WORKING EXAMPLE ===");
            sb.AppendLine("{");
            sb.AppendLine("  \"file_name\": \"CircleShape\",");
            sb.AppendLine("  \"hlsl_code\": \"void CircleShape_float(float2 UV, float Size, float4 Color, out float4 outColor) {\\n    // Center UV coordinates\\n    float2 centered = UV - 0.5;\\n    \\n    // Circle SDF\\n    float dist = length(centered) - Size;\\n    \\n    // Anti-aliased edge\\n    float edge = smoothstep(0.01, -0.01, dist);\\n    \\n    // Output with smooth alpha\\n    outColor = float4(Color * edge, edge);\\n}\",");
            sb.AppendLine("  \"properties\": [");
            sb.AppendLine("    {\"name\": \"Size\", \"type\": \"float\", \"default_value\": {\"x\": 0.3, \"y\": 0, \"z\": 0, \"w\": 0}},");
            sb.AppendLine("    {\"name\": \"Color\", \"type\": \"color\", \"default_value\": {\"x\": 1.0, \"y\": 0.0, \"z\": 1.0, \"w\": 0}}");
            sb.AppendLine("  ]");
            sb.AppendLine("}");

            sb.AppendLine("\n=== BAD EXAMPLE (DO NOT DO THIS) ===");
            sb.AppendLine("bad: if (dist < size) outColor = float4(1,1,1,1); else outColor = float4(0,0,0,0);");
            sb.AppendLine("good: float edge = smoothstep(0.01, -0.01, dist); outColor = float4(Color * edge, edge);");
            sb.AppendLine("bad: Complex nested calculations without SDF");
            sb.AppendLine("good: Clean SDF calculation with smoothstep anti-aliasing");
            sb.AppendLine("bad: const float PI = 3.14159265; will lead to compile error");
            sb.AppendLine("good: define PI outside the function like this #ifndef PI #define PI 3.14159265359 #endif");

            AppendPrimitiveLibraryDocs(sb);

            sb.AppendLine("\n=== SPECIAL SHAPES (MUST USE PRIMITIVE RECIPES) ===");
            sb.AppendLine("When the user asks for shapes like star, moon, heart, or right triangle,");
            sb.AppendLine("you MUST build them from simpler SDF primitives (circles, boxes, etc.)");
            sb.AppendLine("instead of inventing a brand new formula from scratch.");

            sb.AppendLine("\n=== CRITICAL SDF RULES ===");
            sb.AppendLine("You MUST obey all of the following:");
            sb.AppendLine("1. You are NOT allowed to invent new SDF formulas.");
            sb.AppendLine("2. You can ONLY build shapes using:");
            sb.AppendLine("   - sdCircle, sdBox, sdRoundedBox, sdSegment");
            sb.AppendLine("   - rotate2D, simple translate/scale (p - offset, p * scale)");
            sb.AppendLine("   - opUnion, opIntersection, opSubtract, opSmoothUnion");
            sb.AppendLine("3. Any complex shape (heart, moon, star, arrow, etc.) must be defined");
            sb.AppendLine("   as a combination of these primitives through transforms + CSG.");
            sb.AppendLine("4. Every shape MUST be resizable via at least one size parameter");
            sb.AppendLine("   (radius, halfExtents, size, etc.). Scaling must stay clean.");
            sb.AppendLine("5. You must declare helper functions BEFORE they are called.");

            sb.AppendLine("- FINAL COLOR PATTERN (IMPORTANT):");
            sb.AppendLine("  * Color parameters are float4 RGBA.");
            sb.AppendLine("  * Never call float4(Color * mask, mask) because Color is float4 and that");
            sb.AppendLine("    would be 5 components (float4 + float) → compile error.");
            sb.AppendLine("  * Instead, ALWAYS do one of these:");
            sb.AppendLine("      outColor = float4(Color.rgb * mask, mask);");
            sb.AppendLine("      // or: outColor = float4(Color.rgb * mask, Color.a * mask);");
            sb.AppendLine("  * Do NOT use compound assignments (+=, -=, *=, /=) on outColor.");
            sb.AppendLine("    Just assign once: outColor = <final value>;");


            sb.AppendLine("- CONSTANT DEFINITIONS RULE (IMPORTANT):");
            sb.AppendLine("  You MUST NOT declare numeric constants inside functions (e.g. `const float PI = ...;`).");
            sb.AppendLine("  Unity HLSL will produce compile errors such as 'unexpected float constant'.");
            sb.AppendLine("  Instead, ALWAYS define constants using preprocessor macros at the TOP of the file:");
            sb.AppendLine("  #ifndef PI");
            sb.AppendLine("  #define PI 3.14159265359");
            sb.AppendLine("  #endif");
            sb.AppendLine("  If you need TAU or HALF_PI, define them the same way.");
            sb.AppendLine("  Never place constant definitions inside the main function or helper functions.");
            sb.AppendLine("  If you use ANY constant value more than once, promote it to a #define at the top.");
            sb.AppendLine("  This ensures compatibility with Unity ShaderGraph's HLSL injection system.");  

            sb.AppendLine("\n=== LIBRARY & COMPOSITION RULES ===");
            sb.AppendLine("1. If a shape can be built from existing primitives (circle, box, rectangle, etc.),");
            sb.AppendLine("   you MUST use those primitives and boolean operations (min/max/smooth union).");
            sb.AppendLine("2. Only write a brand new SDF if composition is clearly impossible.");
            sb.AppendLine("3. For star, moon, heart, right triangle, ALWAYS use the SPECIAL SHAPES recipes above.");
            sb.AppendLine("4. Any new shape must have at least one explicit size parameter that scales it cleanly.");
            sb.AppendLine("5. Helper functions MUST be declared before they are used (no forward references).");

            sb.AppendLine("- COLOR PARAMETERS RULES (IMPORTANT):");
            sb.AppendLine("  * Any parameter that represents a color MUST be a float4 in HLSL (RGBA).");
            sb.AppendLine("  * Never use float3 for colors.");
            sb.AppendLine("  * Name color parameters with 'Color' in the name, e.g. 'Color', 'FillColor', 'StrokeColor'.");
            sb.AppendLine("  * Example: 'float4 Color' or 'float4 FillColor, float4 StrokeColor'.");

            sb.AppendLine("\n=== DEFAULT VALUES GUIDE ===");
            sb.AppendLine("float (Size/Thickness): 0.3 to 0.5 (visible but not huge)");
            sb.AppendLine("float (Rotation): 0.0 radians (use radians, not degrees)");
            sb.AppendLine("float2 (Position): {0.5, 0.5} (center of screen)");
            sb.AppendLine("float3 (Color RGB): {1.0, 0.0, 1.0} (bright magenta)");
            sb.AppendLine("float4 (Color RGBA): {1.0, 0.0, 1.0, 1.0} (bright magenta, opaque)");
            sb.AppendLine("MANDATORY: The generated ShaderGraph or HLSL instructions must set center01 = float2(0.5, 0.5). Never leave the center at (0,0). So the Default value for center x and center y should be 0.5 and 0.5. Never output any other default. The rendered object must appear centered.");

            sb.AppendLine("\n=== REMEMBER ===");
            sb.AppendLine("- Test your logic mentally before outputting");
            sb.AppendLine("- Shapes should be VISIBLE with default values");
            sb.AppendLine("- EVERY parameter except UV must be in properties array");
            sb.AppendLine("- Match parameter names EXACTLY between function signature and properties");
            sb.AppendLine("- Return hlsl_code as normal multi-line HLSL code.");
            sb.AppendLine("- Do NOT manually insert literal \"\\n\" sequences; just use real line breaks.");
            sb.AppendLine("- The API will handle JSON escaping; you only need to output valid JSON structure.");

            sb.AppendLine("\n=== IMPLEMENTATION STRATEGY (MANDATORY) ===");
            sb.AppendLine("- Before writing the final SDF math, write a short step-by-step plan as HLSL comments");
            sb.AppendLine("  at the top of the function. Example:");
            sb.AppendLine("  // PLAN:");
            sb.AppendLine("  // 1) Remap UV to centered coords and scale by Size.");
            sb.AppendLine("  // 2) Build two circle SDFs for the top of the heart.");
            sb.AppendLine("  // 3) Build a bottom triangle SDF.");
            sb.AppendLine("  // 4) Combine with min()/max() to form the heart.");
            sb.AppendLine("  // 5) Use smoothstep for anti-aliasing and output color.");
            sb.AppendLine("- Stick to this plan when implementing the code.");

            sb.AppendLine("\n=== IMPLEMENTATION PATTERN ===");
            sb.AppendLine("At the top of each generated HLSL function, write a short PLAN as comments.");
            sb.AppendLine("Example for a crescent moon:");
            sb.AppendLine("// PLAN:");
            sb.AppendLine("// 1) Map uv01 to local p in [-1,1] around center.");
            sb.AppendLine("// 2) Compute dOuter = sdCircle(p, radius).");
            sb.AppendLine("// 3) Compute dInner = sdCircle(p + float2(offset, 0), radius).");
            sb.AppendLine("// 4) Crescent = opSubtract(dOuter, dInner).");
            sb.AppendLine("// 5) mask = shapeMaskAA(dist); outColor = color * mask;");
            sb.AppendLine("Then implement exactly this plan using ONLY the allowed SDF toolkit.");

            sb.AppendLine("\n=== FILE SCOPE / DEPENDENCIES (IMPORTANT) ===");
            sb.AppendLine("You are generating a SINGLE, STANDALONE .hlsl file.");
            sb.AppendLine("The code will be compiled as-is inside a Unity ShaderGraph Custom Function node.");
            sb.AppendLine("You DO NOT have access to any other project files, includes, or helper functions.");
            sb.AppendLine("The primitive/library code shown below is FOR REFERENCE ONLY, not automatically included.");
            sb.AppendLine("You DO NOT have access to any project helpers. Only HLSL intrinsics above are allowed");
            sb.AppendLine("without definition. Any other function you call must be fully defined earlier in the same file.");

            sb.AppendLine("You MUST obey ALL of the following:");
            sb.AppendLine("- Do NOT call any function unless it is either:");
            sb.AppendLine("  (a) a built-in HLSL intrinsic (abs, dot, length, min, max, step, smoothstep, sin, cos, atan2, etc.), or");
            sb.AppendLine("  (b) fully defined earlier in the SAME hlsl_code string you are outputting.");
            sb.AppendLine("- If you want to use a helper from the reference library, you MUST:");
            sb.AppendLine("  1) Copy its full definition into your hlsl_code,");
            sb.AppendLine("  2) Paste it ABOVE the main shape function,");
            sb.AppendLine("  3) Then call it.");
            sb.AppendLine("- Never assume external includes, cginc files, or previously defined functions exist.");
            sb.AppendLine("- Helper functions must be declared BEFORE they are used (no forward declarations).");



            return sb.ToString();
        }
        private static void AppendPrimitiveLibraryDocs(StringBuilder sb)
        {
            sb.AppendLine("\n=== REFERENCE: PRIMITIVE LIBRARY DOCS (Examples, You Can Learn From Them) ===");
            string basePath = "Assets/ShaderGraphs/Primitives"; // wherever your six files live
            string[] files = {
                "PrimitiveFunction5.hlsl",
                "PrimitiveFunction6.hlsl",
            };

            foreach (var file in files)
            {
                string path = Path.Combine(basePath, file);
                if (File.Exists(path))
                {
                    sb.AppendLine($"\n// --- {file} ---");
                    // You can choose to strip comments or only include header blocks here.
                    sb.AppendLine(File.ReadAllText(path));
                }
            }

            sb.AppendLine("\n=== REFERENCE: PRIMITIVE LIBRARY (DO NOT ASSUME THESE ARE AVAILABLE) ===");
            sb.AppendLine("The following HLSL snippets show how existing primitives are implemented in this project.");
            sb.AppendLine("They are provided ONLY as examples of style, patterns, naming, and SDF conventions.");
            sb.AppendLine("In your final hlsl_code you MUST NOT call these functions by name unless you");
            sb.AppendLine("have also copied their full definitions into the same file, above your main function.");
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
        public static void SetDefaultMaterialProperties(
            Material material,
            List<LLMShaderProperty> properties)
        {
            if (material == null || properties == null) return;

            foreach (var prop in properties)
            {
                // 1. Resolve the actual shader property name
                string propName = prop.name;
                if (!material.HasProperty(propName))
                {
                    string alt = "_" + prop.name;
                    if (material.HasProperty(alt))
                    {
                        propName = alt;
                    }
                    else
                    {
                        Debug.LogWarning(
                            $"Material '{material.name}' does not have property '{prop.name}' or '{alt}'. Skipping.");
                        continue;
                    }
                }

                var val = prop.default_value;
                string type = prop.type?.ToLowerInvariant() ?? "";

                try
                {
                    switch (type)
                    {
                        case "float":
                            material.SetFloat(propName, val.x);
                            break;

                        case "float2":
                            material.SetVector(propName, new Vector4(val.x, val.y, 0f, 0f));
                            break;

                        case "float3":
                            material.SetVector(propName, new Vector4(val.x, val.y, val.z, 0f));
                            break;

                        case "float4":
                        case "color":
                            // Treat as generic float4 / color
                            material.SetVector(propName, new Vector4(val.x, val.y, val.z, val.w));
                            break;

                        default:
                            Debug.LogWarning(
                                $"Unsupported LLM property type '{prop.type}' for '{prop.name}'.");
                            break;
                    }
                }
                catch (System.Exception ex)
                {
                    Debug.LogWarning(
                        $"Failed to set material property '{propName}' from LLM defaults: {ex.Message}");
                }
            }

            // Force center parameters
            foreach (var prop in properties)
            {
                if (prop.name.ToLower().Contains("center"))
                {
                    if (material.HasVector(prop.name))
                    {
                        material.SetVector(prop.name, new Vector4(0.5f, 0.5f, 0f, 0f));
                    }
                }
            }
            Debug.Log($"✓ Set default LLM properties on material: {material.name}");
        }

        #if UNITY_EDITOR
        public static bool HasShaderCompileErrors(Shader shader)
        {
            if (shader == null)
                return true;

            // Clear any old messages
            ShaderUtil.ClearShaderMessages(shader);

            // Force the shader asset to reimport/compile
            var path = AssetDatabase.GetAssetPath(shader);
            if (!string.IsNullOrEmpty(path))
            {
                AssetDatabase.ImportAsset(path, ImportAssetOptions.ForceUpdate);
            }

            // Now read messages
            var messages = ShaderUtil.GetShaderMessages(shader);
            foreach (var msg in messages)
            {
                if (msg.severity == ShaderCompilerMessageSeverity.Error)
                {
                    Debug.LogError(
                        $"Shader compile error in '{shader.name}': {msg.message} " +
                        $"(file: {msg.file}, line: {msg.line})");
                    return true;
                }
            }

            return false;
        }
        #endif
    }
}