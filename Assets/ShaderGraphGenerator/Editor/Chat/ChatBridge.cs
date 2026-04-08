using System;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using Newtonsoft.Json;
using UnityEditor;
using UnityEngine;
using ShaderGraphGenerator.RAG;
using ShaderGraphGenerator.Editor;
using ShaderGraphGenerator.KnowledgeBase;
using System.Text.RegularExpressions;

namespace ShaderGraphGenerator.Chat
{
    [InitializeOnLoad]
    public static class ChatBridge
    {
        // ── config ──────────────────────────────────────────────────────────
        public const int PORT = 7723;

        // ── state ───────────────────────────────────────────────────────────
        private static HttpListener          _listener;
        private static Thread                _thread;
        private static CancellationTokenSource _cts;

        private static string  _statusMsg   = "";
        private static string  _lastPreview = ""; // absolute path to latest preview PNG

        public static string StatusMsg => _statusMsg;

        // contact form scratch
        private static string _contactName  = "";
        private static string _contactEmail = "";

        // ── Unity hooks ─────────────────────────────────────────────────────
        static ChatBridge() { Start(); }

        public static void Start()
        {
            if (_listener != null) return;
            _listener = new HttpListener();
            _listener.Prefixes.Add($"http://localhost:{PORT}/");
            try { _listener.Start(); }
            catch (Exception e) { Debug.LogWarning($"[ChatBridge] Could not start: {e.Message}"); return; }

            _thread = new Thread(ListenLoop) { IsBackground = true };
            _thread.Start();
            Debug.Log($"[ChatBridge] Running on http://localhost:{PORT}/");
        }

        public static void Stop()
        {
            _listener?.Stop();
            _listener = null;
        }

        // ── HTTP loop ────────────────────────────────────────────────────────
        private static void ListenLoop()
        {
            while (_listener != null && _listener.IsListening)
            {
                try
                {
                    var ctx = _listener.GetContext();
                    ThreadPool.QueueUserWorkItem(_ => HandleRequest(ctx));
                }
                catch { break; }
            }
        }

        private static void HandleRequest(HttpListenerContext ctx)
        {
            var req  = ctx.Request;
            var resp = ctx.Response;
            resp.Headers.Add("Access-Control-Allow-Origin", "*");
            resp.Headers.Add("Access-Control-Allow-Methods", "GET,POST,OPTIONS");
            resp.Headers.Add("Access-Control-Allow-Headers", "Content-Type");

            if (req.HttpMethod == "OPTIONS") { resp.StatusCode = 204; resp.Close(); return; }

            try
            {
                string body = "";
                if (req.HasEntityBody)
                    using (var sr = new StreamReader(req.InputStream, Encoding.UTF8))
                        body = sr.ReadToEnd();

                object result = null;

                if (req.Url.AbsolutePath == "/chat" || req.Url.AbsolutePath == "/")
                {
                    string htmlFile = Path.Combine(Application.dataPath,
                        "ShaderGraphGenerator/Editor/Chat/chat.html");
                    if (File.Exists(htmlFile))
                    {
                        byte[] html = File.ReadAllBytes(htmlFile);
                        resp.ContentType = "text/html; charset=utf-8";
                        resp.ContentLength64 = html.Length;
                        resp.OutputStream.Write(html, 0, html.Length);
                        resp.Close();
                        return;
                    }
                }

                if (req.Url.AbsolutePath == "/send")
                    result = HandleSend(body);
                else if (req.Url.AbsolutePath == "/status")
                    result = new { status = _statusMsg, preview = _lastPreview };
                else if (req.Url.AbsolutePath == "/abort")
                    result = HandleAbort();
                else if (req.Url.AbsolutePath == "/history")
                    result = BuildHistoryPayload();
                else if (req.Url.AbsolutePath == "/image")
                    result = HandleImageUpload(body);
                else
                    result = new { error = "not found" };

                var json = JsonConvert.SerializeObject(result);
                var bytes = Encoding.UTF8.GetBytes(json);
                resp.ContentType = "application/json; charset=utf-8";
                resp.ContentLength64 = bytes.Length;
                resp.OutputStream.Write(bytes, 0, bytes.Length);
            }
            catch (Exception e)
            {
                Debug.LogError($"[ChatBridge] {e}");
            }
            finally { resp.Close(); }
        }

        // ── /send ────────────────────────────────────────────────────────────
        internal static object HandleSend(string body)
        {
            var payload = JsonConvert.DeserializeObject<Dictionary<string, string>>(body);
            string msg         = payload.ContainsKey("message") ? payload["message"] : "";
            string displayText = payload.ContainsKey("display") ? payload["display"] : msg;

            ChatSession.AddUser(displayText);
            var botReplies = new List<string>();

            switch (ChatSession.State)
            {
                // ── main menu ──────────────────────────────────────────
                case ChatState.MainMenu:
                    switch (msg)
                    {
                        case "new_shape":
                            ChatSession.State = ChatState.NewShape_InputMode;
                            botReplies.Add("Perfect. I can create a shape for you with ShaderGraph and HLSL. You can easily define what specific features you want to be editable in your shape. Now tell me, do you have an image reference for your shape? Or do you want to fully define it as text?");
                            break;
                        case "edit":
                            ChatSession.State = ChatState.Edit_Describe;
                            botReplies.Add("Oh I see. First of all, please note that you can always change editable features manually in material props. If you can't achieve what you need there, let me know how you want to update the current shape.");
                            break;
                        case "animate":
                            ChatSession.State = ChatState.Animate_Attach; // Go to Attach state first
                            botReplies.Add("Please attach the material.");
                            break;
                        case "hlsl":
                            ChatSession.State = ChatState.HLSL_Attach;
                            ChatSession.AddBot("No problem. Please attach the file.");
                            break;
                        
                        case "explain":
                            ChatSession.State = ChatState.Explain;
                            botReplies.Add(GetExplanationText());
                            break;
                        case "contact":
                            ChatSession.State = ChatState.Contact_Name;
                            botReplies.Add("What should we call you?");
                            break;
                        default:
                            botReplies.Add("Please choose one of the options.");
                            break;
                    }
                    break;

                case ChatState.HLSL_Attach:
                    if (msg == "back") { ChatSession.State = ChatState.MainMenu; ChatSession.AddBot("Ok, back to main menu."); break; }
                    if (msg == "file_attached")
                    {
                        ChatSession.State = ChatState.HLSL_Running;
                        ChatSession.AddBot("Please wait while I process your file.");
                        TriggerHLSLGeneration(ChatSession.PendingHLSLPath);
                    }
                    break;

                case ChatState.HLSL_Running:
                    if (msg == "abort") { HandleAbort(); break; }
                    break;

                case ChatState.HLSL_Done:
                    if (msg == "back") 
                    { 
                        ChatSession.State = ChatState.MainMenu; 
                        botReplies.Add("You're welcome! What else can I help you with?"); 
                    }
                    break;

                // ── new shape: pick mode ───────────────────────────────
                case ChatState.NewShape_InputMode:
                    switch (msg)
                    {
                        case "image":
                            ChatSession.State = ChatState.NewShape_Image;
                            botReplies.Add("Please attach your image. Also, you can specify with text how exactly editable you want your shape to be.");
                            break;
                        case "text":
                            ChatSession.State = ChatState.NewShape_Text;
                            botReplies.Add("Please fully explain how you want your 2D shape to look like and what parts and parameters you want to be editable.");
                            break;
                        case "back":
                            ChatSession.State = ChatState.MainMenu;
                            botReplies.Add("No problem. What else can I help you with?");
                            break;
                    }
                    break;

                // ── new shape: text prompt ─────────────────────────────
                case ChatState.NewShape_Text:
                    if (msg == "back") { ChatSession.State = ChatState.MainMenu; botReplies.Add("Ok, back to main menu."); break; }
                    if (msg == "switch_image") { ChatSession.State = ChatState.NewShape_Image; botReplies.Add("Sure! Please attach your image."); break; }
                    ChatSession.PendingPrompt = msg;
                    botReplies.Add("Please wait until your result is ready. This might take up to a few minutes, so be patient.");
                    ChatSession.State = ChatState.Generating;
                    TriggerTextGeneration(msg);
                    break;

                // ── new shape: image mode ──────────────────────────────
                case ChatState.NewShape_Image:
                    if (msg == "back") { ChatSession.State = ChatState.MainMenu; botReplies.Add("Ok, back to main menu."); break; }
                    if (ChatSession.PendingImageBase64 == null) { botReplies.Add("Please attach an image first using the image button."); break; }
                    ChatSession.PendingPrompt = msg;
                    botReplies.Add("Please wait until your result is ready. This might take up to a few minutes, so be patient.");
                    ChatSession.State = ChatState.Generating;
                    TriggerImageGeneration(ChatSession.PendingImageBase64, msg);
                    break;

                // ── review ─────────────────────────────────────────────
                case ChatState.Reviewing:
                    if (msg == "abort") { HandleAbort(); ChatSession.State = ChatState.MainMenu; botReplies.Add("Aborted. What else can I help you with?"); break; }
                    if (int.TryParse(msg, out int score))
                    {
                        ChatSession.LastScore = score;
                        if (score >= 7)
                        {
                            ChatSession.State = ChatState.PostGen;
                            botReplies.Add($"I'm glad you liked it! You can always edit specific features through material properties inside your project. What else can we do here?");
                        }
                        else
                        {
                            botReplies.Add("I see, let me try to improve it. Please wait…");
                            ChatSession.State = ChatState.Generating;
                            TriggerRetry($"Previous score was {score}. Please improve the result.");
                        }
                    }
                    break;

                // ── post-gen ───────────────────────────────────────────
                case ChatState.PostGen:
                    switch (msg)
                    {
                        case "edit":
                            ChatSession.State = ChatState.Edit_Describe;
                            botReplies.Add("Oh I see. First of all, please note that you can always change editable features manually in material props. If you can't achieve what you need there, let me know how you want to update the current shape.");
                            break;
                        case "animate":
                            ChatSession.State = ChatState.Animate_Describe;
                            botReplies.Add("Ok for sure. Let me know what and how do you want this shape to be animated.");
                            break;
                        case "effect":
                            ChatSession.State = ChatState.Effect_Pick;
                            botReplies.Add("Good idea. There are some effects you can choose from. Adding an effect can make your asset ready for a specific game style.");
                            break;
                        case "back":
                            ChatSession.State = ChatState.MainMenu;
                            botReplies.Add("Sure! What can I help you with?");
                            break;
                    }
                    break;

                // ── edit ──────────────────────────────────────────────
                case ChatState.Edit_Describe:
                    if (msg == "back") { ChatSession.State = ChatState.MainMenu; botReplies.Add("Ok, back to main menu."); break; }
                    botReplies.Add("Let me first see how I should achieve this.");
                    ChatSession.State = ChatState.Edit_Running;
                    TriggerEdit(msg);
                    break;

                // ── animate ───────────────────────────────────────────
                case ChatState.Animate_Attach:
                    if (msg == "back") { ChatSession.State = ChatState.MainMenu; botReplies.Add("Ok, back to main menu."); break; }
                    if (msg == "material_attached")
                    {
                        ChatSession.State = ChatState.Animate_Describe;
                        botReplies.Add("Ok for sure. Let me know what and how do you want this shape to be animated. [some animate prompt guide]");
                    }
                    break;
                
                case ChatState.Animate_Describe:
                    if (msg == "back") { ChatSession.State = ChatState.MainMenu; botReplies.Add("Ok, back to main menu."); break; }
                    botReplies.Add("Let me first see how I should achieve this.");
                    ChatSession.State = ChatState.Animate_Running;
                    TriggerAnimation(msg);
                    break;

                // ── effect ────────────────────────────────────────────
                case ChatState.Effect_Pick:
                    if (msg == "effect_pixel")
                    {
                        botReplies.Add("Applying pixelation effect…");
                        ChatSession.State = ChatState.Generating;
                        TriggerEffect("pixelation");
                    }
                    else if (msg == "back") { ChatSession.State = ChatState.MainMenu; botReplies.Add("Ok!"); }
                    break;

                // ── explain ───────────────────────────────────────────
                case ChatState.Explain:
                    ChatSession.State = ChatState.MainMenu;
                    botReplies.Add("What else can I help you with?");
                    break;

                // ── contact ───────────────────────────────────────────
                case ChatState.Contact_Name:
                    _contactName = msg;
                    ChatSession.State = ChatState.Contact_Intent;
                    botReplies.Add($"Dear {msg}, I am so grateful you are using my tool! I hope it is useful for you. My name is Nili and I have developed this tool for my master thesis. If you want to know more about me or connect, check out my personal website niloufarmj.github.io. I would also be happy to hear questions or feedback & malfunction reports.");
                    break;

                case ChatState.Contact_Intent:
                    switch (msg)
                    {
                        case "contact_send":
                            ChatSession.State = ChatState.Contact_Email;
                            botReplies.Add("Could you please provide me with an email? I can later answer you through this email.");
                            break;
                        case "contact_skip_all":
                            ChatSession.State = ChatState.MainMenu;
                            botReplies.Add("No worries! Feel free to reach out any time. Is there anything else I can help you with?");
                            break;
                    }
                    break;

                case ChatState.Contact_Email:
                    if (msg == "contact_skip")
                    {
                        ChatSession.State = ChatState.MainMenu;
                        botReplies.Add("No worries! Feel free to reach out any time. Is there anything else I can help you with?");
                        break;
                    }
                    _contactEmail = msg;
                    ChatSession.State = ChatState.Contact_Message;
                    botReplies.Add("Thank you. Now you can type your message. I will reach out as soon as possible.");
                    break;

                case ChatState.Contact_Message:
                    if (msg == "contact_skip")
                    {
                        ChatSession.State = ChatState.MainMenu;
                        botReplies.Add("No worries! Feel free to reach out any time. Is there anything else I can help you with?");
                        break;
                    }
                    SaveContactMessage(_contactName, _contactEmail, msg);
                    ChatSession.State = ChatState.MainMenu;
                    botReplies.Add("Thank you! I will reach out as soon as possible. Is there anything else I can help you with?");
                    break;
            }

            foreach (var r in botReplies)
                ChatSession.AddBot(r);

            return BuildHistoryPayload();
        }

        // ── /abort ────────────────────────────────────────────────────────────
        private static object HandleAbort()
        {
            _cts?.Cancel();
            _statusMsg = "";
            ChatSession.State = ChatState.MainMenu;
            ChatSession.AddBot("Process aborted. What else can I help you with?");
            return BuildHistoryPayload();
        }

        // ── /image ────────────────────────────────────────────────────────────
        private static object HandleImageUpload(string body)
        {
            var payload = JsonConvert.DeserializeObject<Dictionary<string, string>>(body);
            ChatSession.PendingImageBase64 = payload.ContainsKey("base64") ? payload["base64"] : null;
            ChatSession.AddUser("[image attached]");
            ChatSession.AddBot("Image received! Now tell me what editable features you want, or just send to start generation.");
            return BuildHistoryPayload();
        }

        // ── pipeline triggers ─────────────────────────────────────────────────
        private static void TriggerTextGeneration(string prompt)
        {
            _cts = new CancellationTokenSource();
            var token = _cts.Token;
            EditorApplication.delayCall += async () =>
            {
                try
                {
                    _statusMsg = "crafting...";
                    var config = LoadConfig();
                    var kb     = LoadKB();
                    if (config == null) { PushError("ShaderGraphGeneratorConfig asset not found."); return; }
                    if (kb     == null) { PushError("Knowledge base (shape_metadata.json) not found."); return; }

                    var result = await RAGPipelineManager.RunCompletePipelineAsync(prompt, kb, config);
                    if (token.IsCancellationRequested) return;

                    _statusMsg = "";
                    if (!result.success && !string.IsNullOrEmpty(result.errorMessage))
                    {
                        PushError(result.errorMessage);
                        return;
                    }

                    _lastPreview = result.previewImagePath ?? "";
                    ChatSession.State = ChatState.Reviewing;
                    ChatSession.AddBot("Here is the result, how do you rate it on a scale of 1 to 10?", _lastPreview);
                }
                catch (OperationCanceledException) { }
                catch (Exception e) { PushError($"Generation failed: {e.Message}"); }
            };
        }

        private static void TriggerImageGeneration(string base64, string hints)
        {
            _cts = new CancellationTokenSource();
            var token = _cts.Token;
            EditorApplication.delayCall += async () =>
            {
                try
                {
                    _statusMsg = "crafting...";
                    var config = LoadConfig();
                    var kb     = LoadKB();
                    if (config == null) { PushError("ShaderGraphGeneratorConfig asset not found."); return; }
                    if (kb     == null) { PushError("Knowledge base (shape_metadata.json) not found."); return; }

                    // Decode base64 reference image to a temp file the pipeline can read
                    string tempPath = Path.Combine(Path.GetTempPath(), "chat_ref_image.png");
                    File.WriteAllBytes(tempPath, Convert.FromBase64String(base64));

                    var result = await ImageToShaderPipelineManager.RunPipelineAsync(
                        tempPath, hints ?? "", kb, config);
                    if (token.IsCancellationRequested) return;

                    _statusMsg = "";
                    if (!result.success && !string.IsNullOrEmpty(result.errorMessage))
                    {
                        PushError(result.errorMessage);
                        return;
                    }

                    _lastPreview = result.previewImagePath ?? "";
                    ChatSession.State = ChatState.Reviewing;
                    ChatSession.AddBot("Here is the result, how do you rate it on a scale of 1 to 10?", _lastPreview);
                }
                catch (OperationCanceledException) { }
                catch (Exception e) { PushError($"Generation failed: {e.Message}"); }
            };
        }

        private static void TriggerRetry(string feedback)
        {
            _cts = new CancellationTokenSource();
            var token = _cts.Token;
            EditorApplication.delayCall += async () =>
            {
                try
                {
                    _statusMsg = "crafting...";
                    var config = LoadConfig();
                    var kb     = LoadKB();
                    if (config == null) { PushError("ShaderGraphGeneratorConfig asset not found."); return; }
                    if (kb     == null) { PushError("Knowledge base (shape_metadata.json) not found."); return; }

                    string refinedPrompt = string.IsNullOrEmpty(ChatSession.PendingPrompt)
                        ? feedback
                        : $"{ChatSession.PendingPrompt}\n\n[Refinement feedback]: {feedback}";

                    var result = await RAGPipelineManager.RunCompletePipelineAsync(refinedPrompt, kb, config);
                    if (token.IsCancellationRequested) return;

                    _statusMsg = "";
                    if (!result.success && !string.IsNullOrEmpty(result.errorMessage))
                    {
                        PushError(result.errorMessage);
                        return;
                    }

                    _lastPreview = result.previewImagePath ?? "";
                    ChatSession.State = ChatState.Reviewing;
                    ChatSession.AddBot("Here is the updated result. How do you rate it on a scale of 1 to 10?", _lastPreview);
                }
                catch (OperationCanceledException) { }
                catch (Exception e) { PushError($"Retry failed: {e.Message}"); }
            };
        }
        
        private static void TriggerEdit(string description)
        {
            EditorApplication.delayCall += async () =>
            {
                try
                {
                    _statusMsg = "thinking...";
                    // TODO: wire to your existing edit logic in UnifiedGeneratorWindow
                    // For now: re-run generation with the edit as extra context
                    await Task.Delay(500);
                    _statusMsg = "crafting...";
                    await Task.Delay(1000);
                    _statusMsg = "";
                    ChatSession.State = ChatState.PostGen;
                    ChatSession.AddBot("Good news. I was able to achieve this by changing some material props.");
                }
                catch (Exception e) { PushError(e.Message); }
            };
        }

        private static void TriggerAnimation(string description)
        {
            _cts = new CancellationTokenSource();
            var token = _cts.Token;
            
            EditorApplication.delayCall += async () =>
            {
                try
                {
                    _statusMsg = "thinking...";
                    
                    // 1. Add a small delay to simulate "thinking" before sending the follow-up message
                    await Task.Delay(1500, token);
                    if (token.IsCancellationRequested) return;

                    // 2. Push the message exactly as shown in your Figma mockup
                    ChatSession.AddBot("Hmm. It seems I have to change some stuff inside hlsl and then I can do the animating. This might take up to few minutes. please be patient until your result is ready.");
                    
                    _statusMsg = "crafting...";

                    // 3. Load configurations
                    var config = LoadConfig();
                    var kb     = LoadKB();
                    if (config == null) { PushError("Config asset not found."); return; }
                    // Note: KB can be null if it doesn't exist, the pipeline handles useKB=false safely

                    // 4. Resolve the attached material path
                    string matPath = ChatSession.PendingMaterialPath;
                    
                    // Convert absolute OS path to Unity relative path (e.g. "Assets/...")
                    if (!string.IsNullOrEmpty(matPath) && matPath.StartsWith(Application.dataPath))
                    {
                        matPath = "Assets" + matPath.Substring(Application.dataPath.Length);
                    }
                    
                    Material sourceMat = AssetDatabase.LoadAssetAtPath<Material>(matPath);
                    if (sourceMat == null)
                    {
                        PushError($"Could not load attached material at: {matPath}");
                        return;
                    }

                    // 5. Run the actual Animation Pipeline!
                    var result = await MaterialAnimatorPipelineManager.RunPipelineAsync(
                        sourceMaterial: sourceMat,
                        animationRequest: description,
                        config: config,
                        kb: kb,
                        useKB: true,
                        userFeedback: null,
                        onProgress: (status) => { _statusMsg = status; } // Maps pipeline progress to UI status
                    );

                    if (token.IsCancellationRequested) return;

                    _statusMsg = "";
                    
                    if (!result.success)
                    {
                        PushError($"Animation generation failed: {result.errorMessage}");
                        return;
                    }

                    // 6. Final success state
                    ChatSession.State = ChatState.PostGen;
                    ChatSession.AddBot($"Animation complete! I generated the script '{result.fileName}' at {result.scriptAssetPath}. Unity will now recompile to apply it.");
                }
                catch (OperationCanceledException) { }
                catch (Exception e) { PushError($"Animation failed: {e.Message}"); }
            };
}

        private static void TriggerEffect(string effectName)
        {
            EditorApplication.delayCall += async () =>
            {
                try
                {
                    _statusMsg = "crafting...";
                    await Task.Delay(500); // TODO: re-run with usePixelation=true
                    _statusMsg = "";
                    ChatSession.State = ChatState.PostGen;
                    ChatSession.AddBot("Your material is ready with the requested effect.", _lastPreview);
                }
                catch (Exception e) { PushError(e.Message); }
            };
        }

        // ── helpers ───────────────────────────────────────────────────────────
        private static void PushError(string msg)
        {
            _statusMsg = "";
            ChatSession.State = ChatState.MainMenu;
            ChatSession.AddBot($"Something went wrong: {msg} Please try again.");
        }

        private static object BuildHistoryPayload()
        {
            return new
            {
                history      = ChatSession.History,
                state        = ChatSession.State.ToString(),
                config       = ChatSession.GetConfig(),
                status       = _statusMsg,
                lastPreview  = _lastPreview
            };
        }

        private static string GetExplanationText() =>
            "This tool uses a RAG (Retrieval-Augmented Generation) pipeline. " +
            "When you describe a shape, it searches a knowledge base of HLSL shader examples " +
            "to find the most relevant building blocks. Then it uses an LLM (Gemini/GPT-4) to compose " +
            "a new custom HLSL shader tailored to your description. That HLSL is automatically wired into " +
            "a Unity ShaderGraph, a Material is created, and a visual preview is rendered — all without " +
            "you writing a single line of shader code.";

        private static void SaveContactMessage(string name, string email, string message)
        {
            var entry = new { name, email, message, timestamp = DateTime.Now.ToString("o") };
            string path = Path.Combine(Application.dataPath, "..", "contact_messages.json");
            var list = File.Exists(path)
                ? JsonConvert.DeserializeObject<List<object>>(File.ReadAllText(path))
                : new List<object>();
            list.Add(entry);
            File.WriteAllText(path, JsonConvert.SerializeObject(list, Formatting.Indented));
        }

        private static ShaderGraphGeneratorConfig LoadConfig()
        {
            var guids = AssetDatabase.FindAssets("t:ShaderGraphGeneratorConfig");
            if (guids.Length == 0) return null;
            return AssetDatabase.LoadAssetAtPath<ShaderGraphGeneratorConfig>(
                AssetDatabase.GUIDToAssetPath(guids[0]));
        }

        private static ShapeKnowledgeBase LoadKB()
        {
            const string path = "Assets/ShaderGraphGenerator/KnowledgeBase/shape_metadata.json";
            if (!File.Exists(path)) return null;
            var json = File.ReadAllText(path);
            return JsonConvert.DeserializeObject<ShapeKnowledgeBase>(json);
        }

        private static void TriggerHLSLGeneration(string absolutePath)
        {
            _cts = new CancellationTokenSource();
            var token = _cts.Token;
            EditorApplication.delayCall += async () =>
            {
                try
                {
                    _statusMsg = "crafting...";
                    
                    // 1. Extract the exact name of the file
                    string baseName = Path.GetFileNameWithoutExtension(absolutePath);
                    
                    // 2. Import the HLSL file into the Unity project so AssetDatabase can process it
                    string relativeHlslFolder = "Assets/ShaderGraphs/Generated/HLSL";
                    Directory.CreateDirectory(relativeHlslFolder);
                    string relativeHlslPath = $"{relativeHlslFolder}/{baseName}.hlsl";
                    
                    // Only copy if it's not already exactly the same file path
                    if (Path.GetFullPath(absolutePath) != Path.GetFullPath(Path.Combine(Application.dataPath, "..", relativeHlslPath)))
                    {
                        File.Copy(absolutePath, relativeHlslPath, true);
                        AssetDatabase.ImportAsset(relativeHlslPath, ImportAssetOptions.ForceUpdate);
                    }

                    string guid = AssetDatabase.AssetPathToGUID(relativeHlslPath);
                    if (string.IsNullOrEmpty(guid)) throw new Exception("Failed to get GUID for HLSL file.");

                    // 3. Generate the ShaderGraph using your actual generator
                    string graphFolder = "Assets/ShaderGraphs/Generated/Graphs";
                    Directory.CreateDirectory(graphFolder);
                    string graphPath = $"{graphFolder}/{baseName}.shadergraph";
                    
                    var functionInfo = ShaderGraphJSONGenerator.GenerateFromHLSL(relativeHlslPath, guid, graphPath, true, false);
                    AssetDatabase.Refresh();

                    // 4. Create the Material and set properties so it's visible
                    Material mat = MaterialPreviewHelper.CreateMaterialForShaderGraph(graphPath);
                    if (mat == null) throw new Exception("Failed to create material.");
                    
                    if (functionInfo != null)
                    {
                        MaterialPreviewHelper.SetRandomMaterialProperties(mat, functionInfo);
                    }

                    // 5. Create Preview Quad & Capture Screenshot
                    string previewFolder = "Assets/ShaderGraphs/Generated/Previews";
                    Directory.CreateDirectory(previewFolder);
                    string previewPath = $"{previewFolder}/{baseName}.png";
                    
                    GameObject quad = MaterialPreviewHelper.CreatePreviewQuad(mat, true, previewPath);
                    
                    // Critical: Wait for your Editor update loop to actually save the screenshot to disk
                    double start = EditorApplication.timeSinceStartup;
                    while (!File.Exists(previewPath) && (EditorApplication.timeSinceStartup - start) < 5.0)
                    {
                        await Task.Delay(200, token);
                        if (token.IsCancellationRequested) return;
                    }
                    await Task.Delay(100, token); // tiny buffer to let the OS release the file handle

                    // 6. Update the Chat UI with the real paths
                    _statusMsg = "";
                    ChatSession.State = ChatState.HLSL_Done;
                    _lastPreview = previewPath;
                    string matPath = AssetDatabase.GetAssetPath(mat);
                    
                    string responseText = $"Here is the result. You can find the shadergraph in {graphPath} and the material in {matPath}.";
                    ChatSession.AddBot(responseText, _lastPreview);
                }
                catch (OperationCanceledException) { }
                catch (Exception e) { PushError($"HLSL processing failed: {e.Message}"); }
            };
        }
    }

    class AnimationClassification
    {
        public bool needs_hlsl_change { get; set; }
    }
    
}
