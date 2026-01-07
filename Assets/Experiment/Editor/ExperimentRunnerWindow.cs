using UnityEditor;
using UnityEngine;
using System;
using System.IO;
using System.Collections.Generic;
using System.Threading.Tasks;
using System.Diagnostics;
using Newtonsoft.Json;
using UnityEngine.Networking;

using ShaderGraphGenerator;
using ShaderGraphGenerator.Editor;                 // HLSLFunctionInfo, ShaderGraphJSONGenerator, LLMShaderResponse, LLMShaderProperty
                                                   // ShaderGraphGeneratorConfig (your config asset)

namespace ShaderGraphExperiments.Editor
{
    public enum ProviderChoice { OpenAI, Gemini }

    [Serializable]
    public class ExperimentRun
    {
        public string run_id;
        public string timestamp_utc;

        public string shape_set;               // Simple / Complex
        public string code_provider;           // OpenAI / Gemini
        public string eval_provider;           // OpenAI / Gemini

        public int max_iterations;
        public int success_threshold;          // e.g. 7
        public bool require_human_score;       // true => wait for human rating

        public List<ShapeRunResult> shapes = new List<ShapeRunResult>();
    }

    [Serializable]
    public class ShapeRunResult
    {
        public string prompt;
        public bool success;
        public int iterations_used;

        public double total_time_ms;

        public int final_vlm_score;
        public string final_vlm_explanation;

        public int human_score;               // 0 if not provided
        public bool accepted_by_human;

        public List<IterationResult> iterations = new List<IterationResult>();
    }

    [Serializable]
    public class IterationResult
    {
        public int iteration_index;
        public double iteration_time_ms;

        public string generated_file_name;
        public string llm_raw_json;

        public string hlsl_asset_path;
        public string shadergraph_asset_path;
        public string material_asset_path;

        public bool compile_ok;

        public string screenshot_path;

        public int vlm_score;
        public string vlm_explanation;
    }

    [Serializable]
    public class VLMScore
    {
        public int score;
        public string explanation;
    }

    public class ExperimentRunnerWindow : EditorWindow
    {
        // --------- UI inputs ---------
        private string simpleShapesPath = "Assets/Experiment/ShapeSets/Shapes_Simple.txt";
        private string complexShapesPath = "Assets/Experiment/ShapeSets/Shapes_Complex.txt";

        private string hlslOutFolder = "Assets/Experiment/Generated/HLSL";
        private string graphOutFolder = "Assets/Experiment/Generated/Graphs";
        private string previewOutFolder = "Assets/Experiment/Generated/Previews";
        private string resultsFolder = "Assets/Experiment/Results";

        private int maxIterations = 4;
        private int successThreshold = 7;
        private bool requireHumanScore = true;

        // Run selection
        private bool runAllEightGroups = true;
        private ProviderChoice singleCodeProvider = ProviderChoice.Gemini;
        private ProviderChoice singleEvalProvider = ProviderChoice.OpenAI;
        private bool runSimple = true;
        private bool runComplex = true;

        // Config
        private ShaderGraphGeneratorConfig config;

        // State
        private bool isRunning = false;
        private Vector2 scroll;
        private string status = "";

        // Human scoring panel
        private Texture2D pendingPreview;
        private string pendingPrompt;
        private TaskCompletionSource<int> humanScoreTcs;
        private int humanScoreSlider = 7;

        [MenuItem("Tools/ShaderGraph Experiments/Experiment Runner")]
        public static void ShowWindow()
        {
            GetWindow<ExperimentRunnerWindow>("Experiment Runner");
        }

        private void OnEnable()
        {
            // Same config asset path as your existing tool.
            config = AssetDatabase.LoadAssetAtPath<ShaderGraphGeneratorConfig>("Assets/ShaderGraphGeneratorConfig.asset");
        }

        private void OnGUI()
        {
            scroll = EditorGUILayout.BeginScrollView(scroll);

            GUILayout.Label("Experiment Runner (New Tool)", EditorStyles.boldLabel);
            EditorGUILayout.Space(6);

            EditorGUILayout.HelpBox(
                "Runs the full 8-group experiment:\n" +
                "2 shape sets (Simple/Complex) × 2 Code LLMs (OpenAI/Gemini) × 2 Eval VLMs (OpenAI/Gemini).\n" +
                "Logs per-iteration time, iterations-to-success, VLM score, and optional human score.\n" +
                "Saves JSON after each shape.",
                MessageType.Info
            );

            EditorGUILayout.Space(10);

            GUILayout.Label("Input Shape Lists", EditorStyles.boldLabel);
            simpleShapesPath = EditorGUILayout.TextField("Simple Shapes TXT", simpleShapesPath);
            complexShapesPath = EditorGUILayout.TextField("Complex Shapes TXT", complexShapesPath);

            EditorGUILayout.Space(10);
            GUILayout.Label("Output Folders", EditorStyles.boldLabel);
            hlslOutFolder = EditorGUILayout.TextField("HLSL Folder", hlslOutFolder);
            graphOutFolder = EditorGUILayout.TextField("Graph Folder", graphOutFolder);
            previewOutFolder = EditorGUILayout.TextField("Preview Folder", previewOutFolder);
            resultsFolder = EditorGUILayout.TextField("Results Folder", resultsFolder);

            EditorGUILayout.Space(10);
            GUILayout.Label("Experiment Settings", EditorStyles.boldLabel);
            maxIterations = EditorGUILayout.IntSlider("Max Iterations", maxIterations, 1, 10);
            successThreshold = EditorGUILayout.IntSlider("Success Threshold", successThreshold, 1, 10);
            requireHumanScore = EditorGUILayout.Toggle("Require Human Score", requireHumanScore);

            EditorGUILayout.Space(10);
            GUILayout.Label("Run Mode", EditorStyles.boldLabel);

            runAllEightGroups = EditorGUILayout.ToggleLeft("Run ALL 8 Groups (recommended)", runAllEightGroups);

            EditorGUI.BeginDisabledGroup(runAllEightGroups);
            singleCodeProvider = (ProviderChoice)EditorGUILayout.EnumPopup("Code Provider", singleCodeProvider);
            singleEvalProvider = (ProviderChoice)EditorGUILayout.EnumPopup("Eval Provider", singleEvalProvider);
            runSimple = EditorGUILayout.ToggleLeft("Run Simple Set", runSimple);
            runComplex = EditorGUILayout.ToggleLeft("Run Complex Set", runComplex);
            EditorGUI.EndDisabledGroup();

            EditorGUILayout.Space(10);

            EditorGUI.BeginDisabledGroup(isRunning || config == null);
            if (GUILayout.Button(isRunning ? "Running..." : "Start Experiment"))
            {
                _ = StartExperimentAsync();
            }
            EditorGUI.EndDisabledGroup();

            if (config == null)
            {
                EditorGUILayout.HelpBox("Config asset not found at Assets/ShaderGraphGeneratorConfig.asset", MessageType.Warning);
            }

            EditorGUILayout.Space(10);
            EditorGUILayout.LabelField("Status:", EditorStyles.boldLabel);
            EditorGUILayout.TextArea(status, GUILayout.MinHeight(60));

            // ---------- Human score panel ----------
            if (humanScoreTcs != null)
            {
                EditorGUILayout.Space(12);
                EditorGUILayout.LabelField("Human Evaluation Required", EditorStyles.boldLabel);

                if (pendingPreview != null)
                {
                    float w = Mathf.Min(position.width - 40, 512);
                    float h = w;
                    Rect r = GUILayoutUtility.GetRect(w, h, GUILayout.ExpandWidth(false));
                    EditorGUI.DrawPreviewTexture(r, pendingPreview, null, ScaleMode.ScaleToFit);
                }

                EditorGUILayout.LabelField("Prompt:");
                EditorGUILayout.TextArea(pendingPrompt, GUILayout.MinHeight(40));

                humanScoreSlider = EditorGUILayout.IntSlider("Human Score (1–10)", humanScoreSlider, 1, 10);

                EditorGUILayout.BeginHorizontal();
                if (GUILayout.Button("Submit Score"))
                {
                    humanScoreTcs.TrySetResult(humanScoreSlider);
                    ClearHumanPanel();
                }
                if (GUILayout.Button("Reject (Score=1)"))
                {
                    humanScoreTcs.TrySetResult(1);
                    ClearHumanPanel();
                }
                EditorGUILayout.EndHorizontal();

                EditorGUILayout.HelpBox(
                    "Tool is paused until you submit a score. This score is used as part of the final success metric.",
                    MessageType.Info
                );
            }

            EditorGUILayout.EndScrollView();
        }

        private void ClearHumanPanel()
        {
            pendingPreview = null;
            pendingPrompt = null;
            humanScoreTcs = null;
            humanScoreSlider = 7;
            Repaint();
        }

        private async Task<int> WaitForHumanScoreAsync(string prompt, string previewPath)
        {
            pendingPrompt = prompt;
            pendingPreview = AssetDatabase.LoadAssetAtPath<Texture2D>(previewPath);

            humanScoreTcs = new TaskCompletionSource<int>();
            Repaint();
            return await humanScoreTcs.Task;
        }

        // ----------------- Main entry -----------------
        private async Task StartExperimentAsync()
        {
            if (isRunning) return;

            isRunning = true;
            status = "Starting...\n";
            Repaint();

            try
            {
                EnsureFolders();

                if (runAllEightGroups)
                {
                    // 8 groups: 2 shape sets × 2 code × 2 eval
                    if (File.Exists(simpleShapesPath))
                        await RunShapeSetAsync("Simple", simpleShapesPath, ProviderChoice.OpenAI, ProviderChoice.OpenAI);
                    if (File.Exists(simpleShapesPath))
                        await RunShapeSetAsync("Simple", simpleShapesPath, ProviderChoice.OpenAI, ProviderChoice.Gemini);
                    if (File.Exists(simpleShapesPath))
                        await RunShapeSetAsync("Simple", simpleShapesPath, ProviderChoice.Gemini, ProviderChoice.OpenAI);
                    if (File.Exists(simpleShapesPath))
                        await RunShapeSetAsync("Simple", simpleShapesPath, ProviderChoice.Gemini, ProviderChoice.Gemini);

                    if (File.Exists(complexShapesPath))
                        await RunShapeSetAsync("Complex", complexShapesPath, ProviderChoice.OpenAI, ProviderChoice.OpenAI);
                    if (File.Exists(complexShapesPath))
                        await RunShapeSetAsync("Complex", complexShapesPath, ProviderChoice.OpenAI, ProviderChoice.Gemini);
                    if (File.Exists(complexShapesPath))
                        await RunShapeSetAsync("Complex", complexShapesPath, ProviderChoice.Gemini, ProviderChoice.OpenAI);
                    if (File.Exists(complexShapesPath))
                        await RunShapeSetAsync("Complex", complexShapesPath, ProviderChoice.Gemini, ProviderChoice.Gemini);
                }
                else
                {
                    if (runSimple && File.Exists(simpleShapesPath))
                        await RunShapeSetAsync("Simple", simpleShapesPath, singleCodeProvider, singleEvalProvider);
                    if (runComplex && File.Exists(complexShapesPath))
                        await RunShapeSetAsync("Complex", complexShapesPath, singleCodeProvider, singleEvalProvider);
                }

                AppendStatus("\n✓ All selected runs finished.");
            }
            catch (Exception ex)
            {
                AppendStatus($"\nERROR: {ex.Message}\n{ex.StackTrace}");
                UnityEngine.Debug.LogException(ex);
            }
            finally
            {
                isRunning = false;
                Repaint();
            }
        }

        private void EnsureFolders()
        {
            Directory.CreateDirectory(hlslOutFolder);
            Directory.CreateDirectory(graphOutFolder);
            Directory.CreateDirectory(previewOutFolder);
            Directory.CreateDirectory(resultsFolder);
            AssetDatabase.Refresh();
        }

        private void AppendStatus(string msg)
        {
            status += msg + "\n";
            Repaint();
        }

        // ----------------- Run one (shapeSet, codeProvider, evalProvider) -----------------
        private async Task RunShapeSetAsync(string shapeSetName, string shapeTxtPath, ProviderChoice codeProvider, ProviderChoice evalProvider)
        {
            AppendStatus($"=== RUN: {shapeSetName} | Code={codeProvider} | Eval={evalProvider} ===");

            var run = new ExperimentRun
            {
                run_id = Guid.NewGuid().ToString("N"),
                timestamp_utc = DateTime.UtcNow.ToString("o"),
                shape_set = shapeSetName,
                code_provider = codeProvider.ToString(),
                eval_provider = evalProvider.ToString(),
                max_iterations = maxIterations,
                success_threshold = successThreshold,
                require_human_score = requireHumanScore
            };

            string[] prompts = LoadPrompts(shapeTxtPath);
            if (prompts.Length == 0)
            {
                AppendStatus($"(No prompts found in {shapeTxtPath})");
                return;
            }

            string runJsonPath = Path.Combine(resultsFolder, $"experiment_{shapeSetName}_{codeProvider}_{evalProvider}_{DateTime.UtcNow:yyyyMMdd_HHmmss}_{run.run_id}.json");

            for (int i = 0; i < prompts.Length; i++)
            {
                string userPrompt = prompts[i].Trim();
                if (string.IsNullOrWhiteSpace(userPrompt)) continue;

                AppendStatus($"-- Shape {i + 1}/{prompts.Length}: {Short(userPrompt, 60)}");

                ShapeRunResult shapeResult = await RunSingleShapeAsync(
                    userPrompt,
                    shapeSetName,
                    codeProvider,
                    evalProvider
                );

                run.shapes.Add(shapeResult);

                // Save after each shape (overwrite)
                File.WriteAllText(runJsonPath, JsonConvert.SerializeObject(run, Formatting.Indented));
                AssetDatabase.Refresh();
                AppendStatus($"   Saved JSON: {runJsonPath}");
            }

            AppendStatus($"=== END RUN: {shapeSetName} | Code={codeProvider} | Eval={evalProvider} ===\n");
        }

        private static string[] LoadPrompts(string path)
        {
            // Supports one prompt per line; empty lines ignored
            var lines = File.ReadAllLines(path);
            var list = new List<string>();
            foreach (var l in lines)
            {
                var t = l.Trim();
                if (string.IsNullOrWhiteSpace(t)) continue;
                list.Add(t);
            }
            return list.ToArray();
        }

        // ----------------- Single shape core loop -----------------
        private async Task<ShapeRunResult> RunSingleShapeAsync(string userPrompt, string shapeSetName, ProviderChoice codeProvider, ProviderChoice evalProvider)
        {
            var shapeResult = new ShapeRunResult { prompt = userPrompt };
            var totalSw = Stopwatch.StartNew();

            const bool useTransparency = true;

            // First prompt to code LLM
            string currentPrompt = ShaderGraphGeneratorEditorUtility.BuildLLMPrompt(userPrompt, useTransparency);
            LLMShaderResponse llmResponse = null;

            for (int iter = 1; iter <= maxIterations; iter++)
            {
                var iterSw = Stopwatch.StartNew();
                var it = new IterationResult { iteration_index = iter };

                // 1) Generate JSON shader response from selected Code LLM
                string llmRawJson = await CallCodeProviderAsync(codeProvider, currentPrompt);
                it.llm_raw_json = llmRawJson;

                if (string.IsNullOrWhiteSpace(llmRawJson))
                {
                    it.compile_ok = false;
                    it.vlm_score = 1;
                    it.vlm_explanation = "Empty LLM response.";
                    iterSw.Stop();
                    it.iteration_time_ms = iterSw.Elapsed.TotalMilliseconds;
                    shapeResult.iterations.Add(it);
                    continue;
                }

                try
                {
                    llmResponse = JsonConvert.DeserializeObject<LLMShaderResponse>(llmRawJson);
                }
                catch
                {
                    it.compile_ok = false;
                    it.vlm_score = 1;
                    it.vlm_explanation = "LLM returned invalid JSON for the expected schema.";
                    iterSw.Stop();
                    it.iteration_time_ms = iterSw.Elapsed.TotalMilliseconds;
                    shapeResult.iterations.Add(it);
                    continue;
                }

                it.generated_file_name = llmResponse.file_name;

                // 2) Deterministic build pipeline (HLSL → Graph → Material → Screenshot)
                string previewPath;
                bool compileOk;

                try
                {
                    previewPath = await BuildPipelineOnceAsync(llmResponse, useTransparency, it);
                    compileOk = true;
                }
                catch (Exception ex)
                {
                    // compile / graph / screenshot failure
                    previewPath = null;
                    compileOk = false;
                    it.vlm_score = 1;
                    it.vlm_explanation = $"Pipeline failure: {ex.Message}";
                }

                it.compile_ok = compileOk;
                it.screenshot_path = previewPath;

                // 3) Evaluate with selected Eval VLM (only if we have an image)
                if (compileOk && !string.IsNullOrEmpty(previewPath))
                {
                    string evalJson = await CallEvalProviderAsync(evalProvider, userPrompt, llmResponse, previewPath);
                    if (!string.IsNullOrWhiteSpace(evalJson))
                    {
                        try
                        {
                            var score = JsonConvert.DeserializeObject<VLMScore>(evalJson);
                            it.vlm_score = score.score;
                            it.vlm_explanation = score.explanation;
                        }
                        catch
                        {
                            it.vlm_score = 1;
                            it.vlm_explanation = "Eval model returned invalid JSON.";
                        }
                    }
                    else
                    {
                        it.vlm_score = 1;
                        it.vlm_explanation = "Empty eval response.";
                    }
                }

                iterSw.Stop();
                it.iteration_time_ms = iterSw.Elapsed.TotalMilliseconds;
                shapeResult.iterations.Add(it);

                AppendStatus($"   Iter {iter}: compile={it.compile_ok} score={it.vlm_score} time={Mathf.RoundToInt((float)it.iteration_time_ms)}ms");

                // 4) Success / refinement
                if (it.compile_ok && it.vlm_score >= successThreshold)
                {
                    shapeResult.final_vlm_score = it.vlm_score;
                    shapeResult.final_vlm_explanation = it.vlm_explanation;
                    shapeResult.iterations_used = iter;

                    // Human score gate (optional)
                    if (requireHumanScore && !string.IsNullOrEmpty(previewPath))
                    {
                        int human = await WaitForHumanScoreAsync(userPrompt, previewPath);
                        shapeResult.human_score = human;
                        shapeResult.accepted_by_human = (human >= successThreshold);
                        shapeResult.success = shapeResult.accepted_by_human;
                    }
                    else
                    {
                        shapeResult.success = true;
                        shapeResult.accepted_by_human = false;
                        shapeResult.human_score = 0;
                    }

                    break;
                }
                else
                {
                    // Build refinement prompt using your existing refinement utility (uses prev response + feedback)
                    string feedback = it.vlm_explanation ?? "No feedback.";
                    currentPrompt = ShaderGraphGeneratorEditorUtility.BuildRefinementPrompt(userPrompt, llmResponse, feedback);
                }
            }

            totalSw.Stop();
            shapeResult.total_time_ms = totalSw.Elapsed.TotalMilliseconds;

            // If loop ended without success:
            if (!shapeResult.success && shapeResult.iterations_used == 0)
            {
                shapeResult.iterations_used = shapeResult.iterations.Count;
                if (shapeResult.iterations.Count > 0)
                {
                    var last = shapeResult.iterations[shapeResult.iterations.Count - 1];
                    shapeResult.final_vlm_score = last.vlm_score;
                    shapeResult.final_vlm_explanation = last.vlm_explanation;
                }
            }

            return shapeResult;
        }

        private void DisableAllPreviewQuads()
        {
            foreach (var quad in GameObject.FindObjectsOfType<MeshRenderer>())
            {
                if (quad.name.Contains("Preview Quad"))
                    quad.gameObject.SetActive(false);
            }
        }

        // ----------------- Deterministic pipeline (copied pattern, new tool) -----------------
        private async Task<string> BuildPipelineOnceAsync(LLMShaderResponse llmResponse, bool useTransparency, IterationResult it)
        {
            // 🔴 VERY IMPORTANT: hide previous previews
            DisableAllPreviewQuads();

            // 1) Write HLSL file
            string hlslPath = ShaderGraphGeneratorEditorUtility.CreateHLSLFile(
                llmResponse.file_name,
                llmResponse.hlsl_code,
                hlslOutFolder
            );
            it.hlsl_asset_path = hlslPath;

            string hlslGuid = AssetDatabase.AssetPathToGUID(hlslPath);
            AssetDatabase.Refresh();

            // 2) Create ShaderGraph
            string graphPath = Path.Combine(graphOutFolder, llmResponse.file_name + ".shadergraph").Replace("\\", "/");
            HLSLFunctionInfo functionInfo = ShaderGraphJSONGenerator.GenerateFromHLSL(
                hlslPath,
                hlslGuid,
                graphPath,
                useTransparency, 
                false
            );
            it.shadergraph_asset_path = graphPath;

            AssetDatabase.Refresh();

            // 3) Create Material
            Material mat = ShaderGraphGeneratorEditorUtility.CreateMaterialForShaderGraph(graphPath);
            if (mat == null)
                throw new Exception("Material creation failed.");
            it.material_asset_path = AssetDatabase.GetAssetPath(mat);

            // 4) Apply defaults
            ShaderGraphGeneratorEditorUtility.SetDefaultMaterialProperties(mat, llmResponse.properties);

            // 5) Compile check
            if (ShaderGraphGeneratorEditorUtility.HasShaderCompileErrors(mat.shader))
                throw new Exception("Shader compile error.");

            // 6) Preview + Screenshot
            Directory.CreateDirectory(previewOutFolder);

            string previewPath = Path.Combine(previewOutFolder, $"{llmResponse.file_name}_{Guid.NewGuid():N}.png").Replace("\\", "/");

            ShaderGraphGeneratorEditorUtility.CreatePreviewQuad(
                mat,
                true,
                previewPath
            );

            bool ready = await WaitForPreviewFileAsync(previewPath);
            if (!ready) throw new Exception("Screenshot not produced in time.");

            return previewPath;
        }

        private async Task<bool> WaitForPreviewFileAsync(string path, float timeoutSeconds = 6f)
        {
            double start = EditorApplication.timeSinceStartup;
            path = path.Replace("\\", "/");

            while (!File.Exists(path) &&
                   (EditorApplication.timeSinceStartup - start) < timeoutSeconds)
            {
                await Task.Yield();
            }
            return File.Exists(path);
        }

        // ----------------- Providers (Code LLM) -----------------
        private async Task<string> CallCodeProviderAsync(ProviderChoice provider, string prompt)
        {
            if (provider == ProviderChoice.Gemini)
            {
                return await CallGeminiTextAsync(prompt, config.geminiKey, "gemini-3-pro-preview");
            }
            else
            {
                // you can change model name to whatever you want
                return await CallOpenAITextJsonAsync(prompt, config.openAIKey, "gpt-5.1");
            }
        }

        // ----------------- Providers (Eval VLM) -----------------
        private async Task<string> CallEvalProviderAsync(ProviderChoice provider, string userPrompt, LLMShaderResponse llmResponse, string previewPath)
        {
            string propsJson = JsonConvert.SerializeObject(llmResponse.properties, Formatting.Indented);

            if (provider == ProviderChoice.Gemini)
            {
                return await CallGeminiEvalAsync(userPrompt, llmResponse.hlsl_code, propsJson, previewPath, config.geminiKey, "gemini-3-pro-preview");
            }
            else
            {
                return await CallOpenAIEvalAsync(userPrompt, llmResponse.hlsl_code, propsJson, previewPath, config.openAIKey, "gpt-5.1");
            }
        }

        // ----------------- OpenAI JSON (text-only) -----------------
        private async Task<string> CallOpenAITextJsonAsync(string prompt, string apiKey, string model)
        {
            string url = "https://api.openai.com/v1/chat/completions";

            var bodyObject = new
            {
                model = model,
                response_format = new { type = "json_object" },
                messages = new object[]
                {
                    new { role = "system", content = "Return ONLY valid raw JSON. No markdown." },
                    new { role = "user", content = prompt }
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
                while (!op.isDone) await Task.Yield();

                if (www.result != UnityWebRequest.Result.Success)
                {
                    AppendStatus($"OpenAI Error: {www.error} {www.downloadHandler.text}");
                    return null;
                }

                dynamic parsed = JsonConvert.DeserializeObject(www.downloadHandler.text);
                return (string)parsed.choices[0].message.content;
            }
        }

        // ----------------- OpenAI Eval (image+text) -----------------
        private async Task<string> CallOpenAIEvalAsync(string userPrompt, string hlslCode, string propsJson, string previewPath, string apiKey, string model)
        {
            string url = "https://api.openai.com/v1/chat/completions";
            if (!File.Exists(previewPath)) return null;

            byte[] imageBytes = File.ReadAllBytes(previewPath);
            string dataUrl = $"data:image/png;base64,{Convert.ToBase64String(imageBytes)}";

            string textContent =
                "You are a strict visual evaluator for procedurally generated shapes.\n\n" +
                "User requested shape:\n" + userPrompt + "\n\n" +
                "HLSL code:\n" + hlslCode + "\n\n" +
                "Properties:\n" + propsJson + "\n\n" +
                "Return ONLY valid JSON:\n" +
                "{ \"score\": <integer 1-10>, \"explanation\": \"short\" }";

            var bodyObject = new
            {
                model = model,
                response_format = new { type = "json_object" },
                messages = new object[]
                {
                    new { role = "system", content = "Return ONLY valid raw JSON." },
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

            byte[] bodyRaw = System.Text.Encoding.UTF8.GetBytes(JsonConvert.SerializeObject(bodyObject));

            using (UnityWebRequest www = new UnityWebRequest(url, "POST"))
            {
                www.uploadHandler = new UploadHandlerRaw(bodyRaw);
                www.downloadHandler = new DownloadHandlerBuffer();
                www.SetRequestHeader("Content-Type", "application/json");
                www.SetRequestHeader("Authorization", $"Bearer {apiKey}");

                var op = www.SendWebRequest();
                while (!op.isDone) await Task.Yield();

                if (www.result != UnityWebRequest.Result.Success)
                {
                    AppendStatus($"OpenAI Eval Error: {www.error} {www.downloadHandler.text}");
                    return null;
                }

                dynamic parsed = JsonConvert.DeserializeObject(www.downloadHandler.text);
                return (string)parsed.choices[0].message.content;
            }
        }

        // ----------------- Gemini Text -----------------
        private async Task<string> CallGeminiTextAsync(string prompt, string apiKey, string model)
        {
            string url = $"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={apiKey}";

            var bodyObj = new
            {
                contents = new object[]
                {
                    new {
                        parts = new object[] { new { text = prompt } }
                    }
                }
            };

            byte[] bodyRaw = System.Text.Encoding.UTF8.GetBytes(JsonConvert.SerializeObject(bodyObj));

            using (UnityWebRequest www = new UnityWebRequest(url, "POST"))
            {
                www.uploadHandler = new UploadHandlerRaw(bodyRaw);
                www.downloadHandler = new DownloadHandlerBuffer();
                www.SetRequestHeader("Content-Type", "application/json");

                var op = www.SendWebRequest();
                while (!op.isDone) await Task.Yield();

                if (www.result != UnityWebRequest.Result.Success)
                {
                    AppendStatus($"Gemini Error: {www.error} {www.downloadHandler.text}");
                    return null;
                }

                dynamic parsed = JsonConvert.DeserializeObject(www.downloadHandler.text);
                return (string)parsed.candidates[0].content.parts[0].text;
            }
        }

        // ----------------- Gemini Eval (image+text) -----------------
        private async Task<string> CallGeminiEvalAsync(string userPrompt, string hlslCode, string propsJson, string previewPath, string apiKey, string model)
        {
            if (!File.Exists(previewPath)) return null;

            byte[] imageBytes = File.ReadAllBytes(previewPath);
            string base64 = Convert.ToBase64String(imageBytes);

            string evalPrompt =
                "You are a strict visual evaluator for procedurally generated shapes.\n\n" +
                "User requested shape:\n" + userPrompt + "\n\n" +
                "HLSL code:\n" + hlslCode + "\n\n" +
                "Properties:\n" + propsJson + "\n\n" +
                "Using ONLY the image, return ONLY valid JSON:\n" +
                "{ \"score\": <integer 1-10>, \"explanation\": \"short\" }";

            string url = $"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={apiKey}";

            var bodyObj = new
            {
                contents = new object[]
                {
                    new
                    {
                        parts = new object[]
                        {
                            new { text = evalPrompt },
                            new {
                                inline_data = new {
                                    mime_type = "image/png",
                                    data = base64
                                }
                            }
                        }
                    }
                }
            };

            byte[] bodyRaw = System.Text.Encoding.UTF8.GetBytes(JsonConvert.SerializeObject(bodyObj));

            using (UnityWebRequest www = new UnityWebRequest(url, "POST"))
            {
                www.uploadHandler = new UploadHandlerRaw(bodyRaw);
                www.downloadHandler = new DownloadHandlerBuffer();
                www.SetRequestHeader("Content-Type", "application/json");

                var op = www.SendWebRequest();
                while (!op.isDone) await Task.Yield();

                if (www.result != UnityWebRequest.Result.Success)
                {
                    AppendStatus($"Gemini Eval Error: {www.error} {www.downloadHandler.text}");
                    return null;
                }

                dynamic parsed = JsonConvert.DeserializeObject(www.downloadHandler.text);
                return (string)parsed.candidates[0].content.parts[0].text;
            }
        }

        private static string Short(string s, int max)
        {
            if (string.IsNullOrEmpty(s)) return "";
            return s.Length <= max ? s : s.Substring(0, max) + "...";
        }
    }
}
