using UnityEditor;
using UnityEngine;
using ShaderGraphGenerator; // Import the runtime namespace
using System.Collections.Generic;
using System.Threading.Tasks;
using UnityEngine.Networking;
using System.IO;
using Newtonsoft.Json;
using System;

namespace ShaderGraphGenerator.Editor
{
    public class LLMMatchScoreResponse
    {
        public int score;          // 1–10
        public string explanation; // short text
    }

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
        private bool captureScreenshot = true;
        private string screenshotPath = "Assets/ShaderGraphs/Previews/GeneratedPreview.png";

        private string llmPrompt = "a pentagon with dynamic size and dynamic stroke, centered, with dynamic rotation and dynamic corner radius";

        private ShaderGraphGeneratorConfig config;
        private string llmHlslFolder = "Assets/ShaderGraphs/Generated/HLSL";
        private string llmGraphFolder = "Assets/ShaderGraphs/Generated/Graphs";
        private string llmPreviewFolder = "Assets/ShaderGraphs/Generated/Previews";
        private bool isGenerating = false;
        private Vector2 scrollPos;

        [MenuItem("Tools/ShaderGraph Generator")]
        public static void ShowWindow()
        {
            GetWindow<ShaderGraphGeneratorWindow>("ShaderGraph Generator");
        }

        private void OnEnable()
        {
            config = AssetDatabase.LoadAssetAtPath<ShaderGraphGeneratorConfig>(
                "Assets/ShaderGraphGeneratorConfig.asset"
            );
        }

        private void OnGUI()
        {
            scrollPos = EditorGUILayout.BeginScrollView(scrollPos);

            GUILayout.Label("Generate from HLSL File", EditorStyles.boldLabel);
            EditorGUILayout.Space();

            hlslFile = EditorGUILayout.ObjectField("HLSL File", hlslFile, typeof(UnityEngine.Object), false);
            outputPath = EditorGUILayout.TextField("Output Path", outputPath);
            useTransparency = EditorGUILayout.Toggle("Use Transparency", useTransparency);
            createMaterial = EditorGUILayout.Toggle("Create Material", createMaterial);
            createPreviewQuad = EditorGUILayout.Toggle("Create Preview Quad", createPreviewQuad);

            EditorGUI.BeginDisabledGroup(!createPreviewQuad);
            captureScreenshot = EditorGUILayout.Toggle("Capture Screenshot", captureScreenshot);
            if (captureScreenshot)
            {
                screenshotPath = EditorGUILayout.TextField("Screenshot Path", screenshotPath);
            }
            if (GUILayout.Button("Generate ShaderGraph from File"))
            {
                GenerateFromFile(); // Renamed original button logic
            }
            EditorGUILayout.HelpBox("This tool parses HLSL functions and generates complete ShaderGraph JSON files.\n\n" +
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

            // --- Separator ---
            EditorGUILayout.Space(20);
            EditorGUILayout.LabelField("", GUI.skin.horizontalSlider);

            // --- New LLM Flow ---
            GUILayout.Label("Generate from Text (Experimental)", EditorStyles.boldLabel);

            GUILayout.Label("Describe your shader function:");
            llmPrompt = EditorGUILayout.TextArea(llmPrompt, GUILayout.Height(80));

            // --- New Button ---
            EditorGUI.BeginDisabledGroup(isGenerating);
            if (GUILayout.Button(isGenerating ? "Generating..." : "Generate with AI"))
            {
                GenerateFromLLMAsync();
            }
            EditorGUI.EndDisabledGroup();

            EditorGUILayout.Space();
            EditorGUILayout.HelpBox(
                "AI Generation requires a valid OpenAI API key and the `com.unity.nuget.newtonsoft-json` package.", 
                MessageType.Info);

            EditorGUILayout.EndScrollView();
;

        }

        private void GenerateFromFile()
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
                        // NEW: set random values so shapes are visible
                        if (functionInfo != null)
                        {
                            ShaderGraphGeneratorEditorUtility.SetRandomMaterialProperties(mat, functionInfo);
                        }
                        successMessage += $"\n\nMaterial created at:\n{AssetDatabase.GetAssetPath(mat)}";
                    }
                }

                // 4. **MODIFIED**: Create the quad if toggled (and material exists)
                if (createPreviewQuad && mat != null && functionInfo != null)
                {
                    // Pass the new screenshot parameters to the utility function
                    GameObject quad = ShaderGraphGeneratorEditorUtility.CreatePreviewQuad(
                        mat,
                        captureScreenshot,
                        screenshotPath); // Pass the path

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

        /// <summary>
        /// NEW: Async method to handle the entire LLM-to-Quad pipeline.
        /// </summary>
        private async void GenerateFromLLMAsync()
        {
            if (isGenerating) return;

            isGenerating = true;
            Repaint();

            const int maxIterations = 4;

            string firstPrompt = ShaderGraphGeneratorEditorUtility.BuildLLMPrompt(llmPrompt, true);
            string currentPrompt = firstPrompt;
            LLMShaderResponse llmResponse = null;
            int iteration = 0;

            while (iteration < maxIterations)
            {
                iteration++;
                Debug.Log($"=== ITERATION {iteration} ===");

                // 1. CALL GEMINI
                string jsonResponse = await CallGeminiAsync(currentPrompt, config.geminiKey);
                llmResponse = JsonConvert.DeserializeObject<LLMShaderResponse>(jsonResponse);

                // 2. BUILD PIPELINE → HLSL → ShaderGraph → Material → Screenshot
                string previewPath = await BuildPipelineOnce(llmResponse);

                // 3. EVALUATE PREVIEW
                var evalJson = await CallOpenAIEvalAsync(
                    llmPrompt,
                    llmResponse.hlsl_code,
                    llmResponse.properties,
                    previewPath,
                    config.openAIKey
                );

                var eval = JsonConvert.DeserializeObject<LLMMatchScoreResponse>(evalJson);

                Debug.Log($"Score = {eval.score}, Explanation = {eval.explanation}");

                if (eval.score >= 7)
                {
                    SaveSuccessfulResult(llmResponse);
                    EditorUtility.DisplayDialog("Success", "Shape looks correct!", "OK");
                    break;
                }

                // 4. PREPARE FEEDBACK PROMPT FOR NEXT ITERATION
                currentPrompt = ShaderGraphGeneratorEditorUtility.BuildRefinementPrompt(firstPrompt, llmResponse, eval.explanation);
            }

            if (iteration == maxIterations)
            {
                EditorUtility.DisplayDialog("Failure", "Max attempts reached. Shape not correct.", "OK");
            }

            isGenerating = false;
            Repaint();
        }

        private void SaveSuccessfulResult(LLMShaderResponse resp)
        {
            string folder = "Assets/ShaderGraphs/SuccessfulResults";
            if (!Directory.Exists(folder)) Directory.CreateDirectory(folder);

            string path = Path.Combine(folder, resp.file_name + ".hlsl");
            File.WriteAllText(path, resp.hlsl_code);
            AssetDatabase.ImportAsset(path);

            Debug.Log($"✓ Saved final successful result to {path}");
        }

        /// <summary>
        /// Runs ONE full generation pipeline:
        /// HLSL → ShaderGraph → Material → Preview Quad → Screenshot.
        /// Returns the path to the screenshot.
        /// </summary>
        private async Task<string> BuildPipelineOnce(LLMShaderResponse llmResponse)
        {
            // -----------------------
            // 1. Write HLSL file
            // -----------------------
            string hlslPath = ShaderGraphGeneratorEditorUtility.CreateHLSLFile(
                llmResponse.file_name,
                llmResponse.hlsl_code,
                llmHlslFolder
            );

            string hlslGuid = AssetDatabase.AssetPathToGUID(hlslPath);
            AssetDatabase.Refresh();

            // -----------------------
            // 2. Create ShaderGraph
            // -----------------------
            string graphPath = Path.Combine(llmGraphFolder, llmResponse.file_name + ".shadergraph");
            HLSLFunctionInfo functionInfo = ShaderGraphJSONGenerator.GenerateFromHLSL(
                hlslPath,
                hlslGuid,
                graphPath,
                true
            );

            AssetDatabase.Refresh();

            // -----------------------
            // 3. Create Material
            // -----------------------
            Material mat = ShaderGraphGeneratorEditorUtility.CreateMaterialForShaderGraph(graphPath);
            if (mat == null)
                throw new Exception("Failed to create material from generated ShaderGraph.");

            // -----------------------
            // 4. Apply defaults from LLM
            // -----------------------
            ShaderGraphGeneratorEditorUtility.SetDefaultMaterialProperties(mat, llmResponse.properties);

            // -----------------------
            // 5. Check for shader compile errors
            // -----------------------
            if (ShaderGraphGeneratorEditorUtility.HasShaderCompileErrors(mat.shader))
                throw new Exception("Shader compile error — stopping iteration.");

            // -----------------------
            // 6. Preview & Screenshot
            // -----------------------
            if (!Directory.Exists(llmPreviewFolder))
                Directory.CreateDirectory(llmPreviewFolder);

            // To avoid overwriting the previous preview:
            string previewPath = Path.Combine(llmPreviewFolder, $"{llmResponse.file_name}_{Guid.NewGuid()}.png");

            GameObject quad = ShaderGraphGeneratorEditorUtility.CreatePreviewQuad(
                mat,
                true, // capture screenshot
                previewPath
            );

            // Wait until file exists
            bool ready = await WaitForPreviewFileAsync(previewPath);
            if (!ready)
                throw new Exception("Screenshot not produced in time.");

            return previewPath;
        }




        /// <summary>
        /// NEW: Handles the raw web request to OpenAI
        /// </summary>
        private async Task<string> CallClaudeAsync(string prompt, string apiKey)
        {
            string url = "https://api.anthropic.com/v1/messages";

            // ── JSON Schema مخصوص پروژه تو ─────────────────────────────
            var schema = new
            {
                type = "object",
                properties = new
                {
                    file_name = new { type = "string" },
                    hlsl_code = new { type = "string" },
                    properties = new
                    {
                        type = "array",
                        items = new
                        {
                            type = "object",
                            properties = new {
                                name = new { type = "string" },
                                type = new { type = "string" },
                                default_value = new {
                                    type = "object",
                                    properties = new {
                                        x = new { type = "number" },
                                        y = new { type = "number" },
                                        z = new { type = "number" },
                                        w = new { type = "number" }
                                    },
                                    required = new[] { "x", "y", "z", "w" },
                                    additionalProperties = false
                                }
                            },
                            required = new[] { "name", "type", "default_value" },
                            additionalProperties = false
                        }
                    }
                },
                required = new[] { "file_name", "hlsl_code", "properties" },
                additionalProperties = false
            };

            var bodyObject = new
            {
                model = "claude-sonnet-4-5-20250929",
                max_tokens = 4096,
                messages = new object[]
                {
                    new {
                        role = "user",
                        content = new object[]
                        {
                            new { type = "text", text = prompt }
                        }
                    }
                },
                output_format = new {
                    type = "json_schema",
                    schema = schema
                },
                betas = new[] { "structured-outputs-2025-11-13" }
            };

            string jsonBody = JsonConvert.SerializeObject(bodyObject);
            byte[] raw = System.Text.Encoding.UTF8.GetBytes(jsonBody);

            using (UnityWebRequest www = new UnityWebRequest(url, "POST"))
            {
                www.uploadHandler = new UploadHandlerRaw(raw);
                www.downloadHandler = new DownloadHandlerBuffer();

                www.SetRequestHeader("content-type", "application/json");
                www.SetRequestHeader("x-api-key", apiKey);
                www.SetRequestHeader("anthropic-version", "2023-06-01");
                www.SetRequestHeader("anthropic-beta", "structured-outputs-2025-11-13");

                var op = www.SendWebRequest();
                while (!op.isDone)
                    await Task.Yield();

                if (www.result != UnityWebRequest.Result.Success)
                {
                    Debug.LogError("Claude API Error: " + www.error + "\n" + www.downloadHandler.text);
                    return null;
                }

                var rawResponse = www.downloadHandler.text;
                dynamic parsed = JsonConvert.DeserializeObject(rawResponse);

                // structured JSON always appears here:
                string jsonText = parsed.content[0].text;

                return jsonText;
            }
        }

        /// <summary>
        /// Calls OpenAI with image + text and asks for a 1–10 match score.
        /// </summary>
        private async Task<string> CallOpenAIEvalAsync(
            string userPrompt,
            string hlslCode,
            List<LLMShaderProperty> properties,
            string previewPath,
            string apiKey)
        {
            string url = "https://api.openai.com/v1/chat/completions";

            // 1) Read preview image and convert to data URL
            if (!File.Exists(previewPath))
            {
                Debug.LogError($"Preview image not found at: {previewPath}");
                return null;
            }

            byte[] imageBytes = File.ReadAllBytes(previewPath);
            string base64 = Convert.ToBase64String(imageBytes);
            string dataUrl = $"data:image/png;base64,{base64}";

            // 2) Build text content
            string propertiesJson = BuildPropertySummaryJson(properties);

            string textContent =
                "You are a strict visual evaluator for procedurally generated shapes.\n\n" +
                "User requested shape (natural language):\n" +
                userPrompt + "\n\n" +
                "HLSL code that produced the image:\n" +
                hlslCode + "\n\n" +
                "Shader properties (name, type, default_value) used for this preview:\n" +
                propertiesJson + "\n\n" +
                "Using ONLY the attached image and this information, rate from 1 to 10 how well " +
                "the rendered image matches the user's request. 1 = completely wrong, 10 = perfect match.\n\n" +
                "Return ONLY valid JSON with this structure:\n" +
                "{ \"score\": <integer 1-10>, \"explanation\": \"short explanation\" }";

            // 3) Build messages with multimodal content
            var bodyObject = new
            {
                model = "gpt-5.1",
                response_format = new { type = "json_object" },
                messages = new object[]
                {
                    new {
                        role = "system",
                        content = "You are a helpful assistant that only responds with valid, raw JSON. " +
                                "Do not include markdown or any other text outside the JSON object."
                    },
                    new {
                        role = "user",
                        content = new object[]
                        {
                            new { type = "text", text = textContent },
                            new { type = "image_url", image_url = new { url = dataUrl } }
                        }
                    }
                }
            };

            string jsonBody = JsonConvert.SerializeObject(bodyObject);
            byte[] bodyRaw = System.Text.Encoding.UTF8.GetBytes(jsonBody);

            using (UnityWebRequest www = new UnityWebRequest(url, "POST"))
            {
                www.uploadHandler = new UploadHandlerRaw(bodyRaw);
                www.downloadHandler = new DownloadHandlerBuffer();
                www.SetRequestHeader("Content-Type", "application/json");
                www.SetRequestHeader("Authorization", $"Bearer {apiKey}");

                var op = www.SendWebRequest();
                while (!op.isDone)
                {
                    await Task.Yield();
                }

                if (www.result == UnityWebRequest.Result.ConnectionError ||
                    www.result == UnityWebRequest.Result.ProtocolError)
                {
                    Debug.LogError($"OpenAI Eval API Error: {www.error}\n{www.downloadHandler.text}");
                    return null;
                }
                else
                {
                    string rawResponse = www.downloadHandler.text;
                    try
                    {
                        var openAiResponse = JsonConvert.DeserializeObject<dynamic>(rawResponse);
                        string jsonContent = openAiResponse.choices[0].message.content;
                        return jsonContent;
                    }
                    catch (System.Exception ex)
                    {
                        Debug.LogError($"Failed to parse OpenAI eval response shell: {ex.Message}\nRaw response: {rawResponse}");
                        // Fallback: sometimes the API just returns the content directly
                        return rawResponse;
                    }
                }
            }
        }

        private async Task<string> CallGeminiAsync(string prompt, string apiKey)
        {
            string model = "gemini-3-pro-preview";

            string url =
                $"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={apiKey}";

            var bodyObj = new
            {
                contents = new object[]
                {
                    new
                    {
                        parts = new object[]
                        {
                            new { text = prompt }
                        }
                    }
                }
            };

            string jsonBody = JsonConvert.SerializeObject(bodyObj);
            byte[] bodyRaw = System.Text.Encoding.UTF8.GetBytes(jsonBody);

            using (UnityWebRequest www = new UnityWebRequest(url, "POST"))
            {
                www.uploadHandler = new UploadHandlerRaw(bodyRaw);
                www.downloadHandler = new DownloadHandlerBuffer();
                www.SetRequestHeader("Content-Type", "application/json");

                var op = www.SendWebRequest();
                while (!op.isDone)
                    await Task.Yield();

                if (www.result == UnityWebRequest.Result.ConnectionError ||
                    www.result == UnityWebRequest.Result.ProtocolError)
                {
                    Debug.LogError($"Gemini API Error: {www.error}\n{www.downloadHandler.text}");
                    return null;
                }

                string raw = www.downloadHandler.text;

                try
                {
                    dynamic parsed = JsonConvert.DeserializeObject(raw);

                    string text =
                        parsed.candidates[0].content.parts[0].text;

                    return text;
                }
                catch (Exception ex)
                {
                    Debug.LogError($"Gemini parse error: {ex.Message}\nRaw: {raw}");
                    return null;
                }
            }
        }


        private string BuildPropertySummaryJson(List<LLMShaderProperty> properties)
        {
            if (properties == null) return "[]";
            return JsonConvert.SerializeObject(properties, Formatting.Indented);
        }

        private async Task<bool> WaitForPreviewFileAsync(string path, float timeoutSeconds = 5f)
        {
            double start = EditorApplication.timeSinceStartup;

            // Normalize slashes just in case
            path = path.Replace("\\", "/");

            while (!File.Exists(path) &&
                EditorApplication.timeSinceStartup - start < timeoutSeconds)
            {
                await Task.Delay(200); // wait 0.2s and check again
            }

            return File.Exists(path);
        }

    
    }



    [System.Serializable]
    public struct LLMValueObject
    {
        public float x;
        public float y;
        public float z;
        public float w;
    }

    [System.Serializable]
    public class LLMShaderProperty
    {
        public string name;
        public string type;
        public LLMValueObject default_value;
    }

    [System.Serializable]
    public class LLMShaderResponse
    {
        public string file_name;
        public string hlsl_code;
        public List<LLMShaderProperty> properties;
    }

}