using UnityEditor;
using UnityEngine;
using ShaderGraphGenerator; // Import the runtime namespace
using System.Collections.Generic;
using System.Threading.Tasks;
using UnityEngine.Networking;
using System.IO;
using Newtonsoft.Json;

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
        private bool captureScreenshot = true;
        private string screenshotPath = "Assets/ShaderGraphs/Previews/GeneratedPreview.png";

        private string llmPrompt = "a pentagon with dynamic size and dynamic stroke, centered, with dynamic rotation and dynamic corner radius";
        private string openAIKey = "MY_OPENAI_KEY";
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
            openAIKey = EditorGUILayout.PasswordField("OpenAI API Key", openAIKey);
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
            if (string.IsNullOrEmpty(openAIKey) || openAIKey == "sk-PASTE_YOUR_KEY_HERE")
            {
                EditorUtility.DisplayDialog("Error", "Please enter a valid OpenAI API Key.", "OK");
                return;
            }

            isGenerating = true;
            Repaint(); // Update button text to "Generating..."

            try
            {
                // 1. Build the meta prompt
                string metaPrompt = ShaderGraphGeneratorEditorUtility.BuildLLMPrompt(llmPrompt, true);

                // 2. Call OpenAI API
                EditorUtility.DisplayProgressBar("LLM", "Contacting OpenAI...", 0.2f);
                string jsonResponse = await CallOpenAIAsync(metaPrompt, openAIKey);

                if (string.IsNullOrEmpty(jsonResponse))
                {
                    throw new System.Exception("Received empty response from LLM.");
                }

                // 3. Parse JSON Response
                EditorUtility.DisplayProgressBar("LLM", "Parsing response...", 0.4f);
                LLMShaderResponse llmResponse = JsonConvert.DeserializeObject<LLMShaderResponse>(jsonResponse);

                if (llmResponse == null || string.IsNullOrEmpty(llmResponse.hlsl_code))
                {
                    throw new System.Exception($"Failed to parse LLM response. Raw response: {jsonResponse}");
                }

                // 4. Create the .hlsl file
                EditorUtility.DisplayProgressBar("LLM", "Creating HLSL file...", 0.5f);
                string hlslPath = ShaderGraphGeneratorEditorUtility.CreateHLSLFile(llmResponse.file_name, llmResponse.hlsl_code, llmHlslFolder);
                string hlslGuid = AssetDatabase.AssetPathToGUID(hlslPath);

                // 5. Refresh AssetDatabase and wait
                AssetDatabase.Refresh();

                // 6. Generate ShaderGraph
                EditorUtility.DisplayProgressBar("LLM", "Generating ShaderGraph...", 0.6f);
                if (!Directory.Exists(llmGraphFolder)) Directory.CreateDirectory(llmGraphFolder);
                string graphPath = Path.Combine(llmGraphFolder, $"{llmResponse.file_name}.shadergraph");

                // Assuming 'opaque' for now. You could ask the LLM for this too.
                HLSLFunctionInfo functionInfo = ShaderGraphJSONGenerator.GenerateFromHLSL(hlslPath, hlslGuid, graphPath, true);

                // 7. Refresh AssetDatabase again to compile shader
                EditorUtility.DisplayProgressBar("LLM", "Compiling shader...", 0.7f);
                AssetDatabase.Refresh();

                // 8. Create Material
                EditorUtility.DisplayProgressBar("LLM", "Creating material...", 0.8f);
                Material mat = ShaderGraphGeneratorEditorUtility.CreateMaterialForShaderGraph(graphPath);
                if (mat == null)
                {
                    throw new System.Exception("Failed to create material. Shader may not have compiled.");
                }

                // 9. Set Default Properties (from LLM)
                ShaderGraphGeneratorEditorUtility.SetDefaultMaterialProperties(mat, llmResponse.properties);

                // 10. Create Quad & Screenshot
                EditorUtility.DisplayProgressBar("LLM", "Creating preview...", 0.9f);
                if (!Directory.Exists(llmPreviewFolder)) Directory.CreateDirectory(llmPreviewFolder);
                string previewPath = Path.Combine(llmPreviewFolder, $"{llmResponse.file_name}.png");

                GameObject quad = ShaderGraphGeneratorEditorUtility.CreatePreviewQuad(
                    mat,
                    true, // captureScreenshot
                    previewPath);

                string successMessage = "AI Generation Complete!\n\n" +
                                        $"HLSL: {hlslPath}\n" +
                                        $"Graph: {graphPath}\n" +
                                        $"Material: {AssetDatabase.GetAssetPath(mat)}\n" +
                                        $"Preview: {previewPath}";

                EditorUtility.DisplayDialog("Success", successMessage, "OK");
            }
            catch (System.Exception ex)
            {
                Debug.LogError($"AI Generation Failed: {ex.ToString()}");
                EditorUtility.DisplayDialog("Error", $"AI Generation Failed:\n{ex.Message}", "OK");
            }
            finally
            {
                isGenerating = false;
                EditorUtility.ClearProgressBar();
                Repaint();
            }
        }

        /// <summary>
        /// NEW: Handles the raw web request to OpenAI
        /// </summary>
        private async Task<string> CallOpenAIAsync(string prompt, string apiKey)
        {
            string url = "https://api.openai.com/v1/chat/completions";

            // Manually craft the request body
            string jsonBody = JsonConvert.SerializeObject(new
            {
                model = "gpt-4-turbo",
                response_format = new { type = "json_object" },
                messages = new[]
               {
                   new { role = "system", content = "You are a helpful assistant that only responds with valid, raw JSON. Do not include markdown ticks or any other text outside the JSON object." },
                   new { role = "user", content = prompt }
               }
            });

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

                if (www.result == UnityWebRequest.Result.ConnectionError || www.result == UnityWebRequest.Result.ProtocolError)
                {
                    Debug.LogError($"OpenAI API Error: {www.error}\n{www.downloadHandler.text}");
                    return null;
                }
                else
                {
                    string rawResponse = www.downloadHandler.text;
                    try
                    {
                        // Parse the { "choices": [ ... ] } wrapper
                        var openAiResponse = JsonConvert.DeserializeObject<dynamic>(rawResponse);
                        string jsonContent = openAiResponse.choices[0].message.content;
                        return jsonContent;
                    }
                    catch (System.Exception ex)
                    {
                        Debug.LogError($"Failed to parse OpenAI response shell: {ex.Message}\nRaw response: {rawResponse}");
                        // Fallback: sometimes the API just returns the content directly
                        return rawResponse;
                    }
                }
            }
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