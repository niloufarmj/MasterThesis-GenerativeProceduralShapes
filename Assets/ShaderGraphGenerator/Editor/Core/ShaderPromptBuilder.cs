using System.IO;
using System.Text;
using Newtonsoft.Json;

namespace ShaderGraphGenerator.Editor
{
    /// <summary>
    /// Builds LLM prompts for HLSL generation and iterative refinement.
    /// </summary>
    public static class ShaderPromptBuilder
    {
        /// <summary>
        /// Builds the master generation prompt sent to the LLM.
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
            sb.AppendLine("    {\"name\": \"param2\", \"type\": \"float2\", \"default_value\": {\"x\": 0.5, \"y\": 0.5, \"z\": 0, \"w\": 0}}");
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
            sb.AppendLine("- Add one line of comment in the hlsl code that says what was the exact user request (the described shape).");

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
            string basePath = "Assets/ShaderGraphs/Primitives";
            string[] files  = { "PrimitiveFunction5.hlsl", "PrimitiveFunction6.hlsl" };

            foreach (var file in files)
            {
                string path = Path.Combine(basePath, file);
                if (File.Exists(path))
                {
                    sb.AppendLine($"\n// --- {file} ---");
                    sb.AppendLine(File.ReadAllText(path));
                }
            }

            sb.AppendLine("\n=== REFERENCE: PRIMITIVE LIBRARY (DO NOT ASSUME THESE ARE AVAILABLE) ===");
            sb.AppendLine("The following HLSL snippets show how existing primitives are implemented in this project.");
            sb.AppendLine("They are provided ONLY as examples of style, patterns, naming, and SDF conventions.");
            sb.AppendLine("In your final hlsl_code you MUST NOT call these functions by name unless you");
            sb.AppendLine("have also copied their full definitions into the same file, above your main function.");
        }

        /// <summary>
        /// Builds the refinement prompt when the previous attempt scored too low.
        /// </summary>
        public static string BuildRefinementPrompt(
            string originalUserPrompt,
            LLMShaderResponse previous,
            string feedback)
        {
            var sb = new StringBuilder();
            sb.AppendLine("Your previous shader result was not correct.");
            sb.AppendLine("PREVIOUS REQUEST:");
            sb.AppendLine(originalUserPrompt);
            sb.AppendLine("FEEDBACK FROM IMAGE EVALUATION:");
            sb.AppendLine(feedback);
            sb.AppendLine("YOUR PREVIOUS HLSL CODE:");
            sb.AppendLine(previous.hlsl_code);
            sb.AppendLine("PREVIOUS PROPERTIES:");
            sb.AppendLine(JsonConvert.SerializeObject(previous.properties, Formatting.Indented));
            sb.AppendLine("Please FIX all issues and regenerate a NEW JSON reply with improved HLSL.");
            sb.AppendLine("IMPORTANT: Output ONLY the JSON with the same structure as before.");
            return sb.ToString();
        }
    }
}
