using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net;
using System.Reflection;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using Newtonsoft.Json;
using UnityEditor;
using UnityEngine;
using ShaderGraphGenerator;
using ShaderGraphGenerator.RAG;
using ShaderGraphGenerator.Editor;
using ShaderGraphGenerator.KnowledgeBase;
using System.Text.RegularExpressions;

namespace ShaderGraphGenerator.Chat
{
    /// <summary>
    /// HTTP bridge between the chatbot UI and Unity's editor pipelines.
    ///
    /// Responsibilities:
    ///   • Runs a local HTTP server on <see cref="PORT"/> (localhost:7723) so that
    ///     the web-based chat UI (chat.html) can communicate with the Unity editor.
    ///   • Routes incoming /send messages through <see cref="ChatSession"/>'s state machine.
    ///   • Triggers all generation, edit, animation, and effect pipelines.
    ///   • Manages a shared <see cref="CancellationTokenSource"/> so any in-flight
    ///     pipeline can be aborted via the /abort endpoint.
    ///
    /// HTTP endpoints:
    ///   GET  /          → Serve chat.html (web UI)
    ///   POST /send      → Main message handler; drives state transitions and pipeline launches
    ///   POST /image     → Accept base64-encoded reference image
    ///   GET  /status    → Return current status message and last preview image path
    ///   GET  /abort     → Cancel the current pipeline and return to MainMenu
    ///   GET  /history   → Return full chat history, current state, and state config (quick replies)
    ///
    /// The [InitializeOnLoad] attribute ensures the HTTP listener starts automatically
    /// when Unity loads the editor (or after domain reloads).
    /// </summary>
    [InitializeOnLoad]
    public static class ChatBridge
    {
        // ── config ──────────────────────────────────────────────────────────
        /// <summary>Local port the HTTP server listens on. Change if 7723 is in use.</summary>
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
                            ChatSession.State = ChatState.Edit_Attach;
                            botReplies.Add("Please attach the material you want to edit.");
                            break;
                        case "animate":
                            ChatSession.State = ChatState.Animate_Attach;
                            botReplies.Add("Please attach the material.");
                            break;
                        case "effect":
                            ChatSession.State = ChatState.Effect_Attach;
                            botReplies.Add("Please attach the material you want to apply an effect to.");
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
                    switch (msg)
                    {
                        case "effect":
                            ChatSession.State = ChatState.Effect_Pick;
                            botReplies.Add("Good idea. There are some effects you can choose from. Adding an effect can make your asset ready for a specific game style.");
                            break;
                        case "back":
                            ChatSession.State = ChatState.MainMenu;
                            botReplies.Add("You're welcome! What else can I help you with?");
                            break;
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

                // ── edit: attach material (main-menu entry) ───────────
                case ChatState.Edit_Attach:
                    if (msg == "back") { ChatSession.State = ChatState.MainMenu; botReplies.Add("Ok, back to main menu."); break; }
                    if (msg == "material_attached")
                    {
                        ChatSession.State = ChatState.Edit_Describe;
                        botReplies.Add("Got it. What changes do you want to make to this material?");
                    }
                    break;

                // ── edit ──────────────────────────────────────────────
                case ChatState.Edit_Describe:
                    if (msg == "back") { ChatSession.State = ChatState.MainMenu; botReplies.Add("Ok, back to main menu."); break; }
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

                // ── effect: attach material (main-menu entry) ────────
                case ChatState.Effect_Attach:
                    if (msg == "back") { ChatSession.State = ChatState.MainMenu; botReplies.Add("Ok, back to main menu."); break; }
                    if (msg == "material_attached")
                    {
                        ChatSession.State = ChatState.Effect_Pick;
                        botReplies.Add("Good idea. There are some effects you can choose from. Adding an effect can make your asset ready for a specific game style.");
                    }
                    break;

                // ── effect ────────────────────────────────────────────
                case ChatState.Effect_Pick:
                    if (msg == "effect_pixel")
                    {
                        botReplies.Add("Applying pixelation effect… This might take a few minutes, please be patient.");
                        ChatSession.State = ChatState.Animate_Running;
                        TriggerEffect("pixelation");
                    }
                    else if (msg == "effect_glow")
                    {
                        botReplies.Add("Applying glow effect! I'll switch your colour properties to HDR mode and add a glowIntensity multiplier so URP Bloom picks them up. I'll also add a Post-Processing Volume with Bloom to your scene if one isn't already there.");
                        ChatSession.State = ChatState.Animate_Running;
                        TriggerEffect("glow");
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
                    ChatSession.PendingMaterialPath = result.materialPath ?? "";
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
                    ChatSession.PendingMaterialPath = result.materialPath ?? "";
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
                    ChatSession.PendingMaterialPath = result.materialPath ?? "";
                    ChatSession.State = ChatState.Reviewing;
                    ChatSession.AddBot("Here is the updated result. How do you rate it on a scale of 1 to 10?", _lastPreview);
                }
                catch (OperationCanceledException) { }
                catch (Exception e) { PushError($"Retry failed: {e.Message}"); }
            };
        }
        
        private static void TriggerEdit(string description)
        {
            _cts = new CancellationTokenSource();
            var token = _cts.Token;

            EditorApplication.delayCall += async () =>
            {
                try
                {
                    // ── Step 1: inform user we're analysing ───────────────────
                    ChatSession.AddBot("Let me first see how I should achieve this.");
                    _statusMsg = "thinking...";

                    var config = LoadConfig();
                    var kb     = LoadKB();
                    if (config == null) { PushError("Config asset not found."); return; }

                    // ── Step 2: resolve material ──────────────────────────────
                    string matPath = ChatSession.PendingMaterialPath;
                    if (!string.IsNullOrEmpty(matPath) && matPath.StartsWith(Application.dataPath))
                        matPath = "Assets" + matPath.Substring(Application.dataPath.Length);

                    Material sourceMat = AssetDatabase.LoadAssetAtPath<Material>(matPath);
                    if (sourceMat == null) { PushError($"Could not load material at: {matPath}"); return; }

                    // ── Step 3: classify ──────────────────────────────────────
                    var properties = AnimationScriptGenerator.ExtractMaterialProperties(sourceMat);
                    var cls = await EditClassifier.ClassifyEditRequestAsync(
                        description, sourceMat.name, properties, config.geminiKey);
                    if (token.IsCancellationRequested) return;

                    if (!cls.needs_hlsl_change)
                    {
                        // ── PATH A: change existing property values only ───────
                        string summary = BuildEditSummary(cls.material_changes);
                        ChatSession.AddBot($"Good news! This edit can be achieved by simply updating {summary} in your material. Let me apply that for you.");
                        _statusMsg = "crafting...";

                        ApplyMaterialPropertyChanges(sourceMat, cls.material_changes);
                        EditorUtility.SetDirty(sourceMat);
                        AssetDatabase.SaveAssets();
                        if (token.IsCancellationRequested) return;

                        // Show the updated material on a quad so the user can see it
                        var quad = GameObject.CreatePrimitive(PrimitiveType.Quad);
                        quad.name = $"Edit Preview — {sourceMat.name}";
                        quad.GetComponent<Renderer>().material = sourceMat;
                        Selection.activeGameObject = quad;
                        if (SceneView.lastActiveSceneView != null)
                            SceneView.lastActiveSceneView.FrameSelected();

                        _statusMsg = "";
                        ChatSession.State = ChatState.PostGen;
                        ChatSession.AddBot(
                            $"Done! I've updated the material. A preview quad '{quad.name}' has been added to your scene.\n" +
                            $"Material path: {matPath}");
                    }
                    else
                    {
                        // ── PATH B: HLSL update needed ────────────────────────
                        ChatSession.AddBot($"This edit requires changes to the shader itself. {cls.reason} This might take a few minutes — please be patient.");
                        _statusMsg = "crafting...";

                        string updateRequest = !string.IsNullOrWhiteSpace(cls.hlsl_update_request)
                            ? cls.hlsl_update_request
                            : description;

                        var result = await HLSLUpdatePipelineManager.RunUpdatePipelineAsync(
                            originalMaterial: sourceMat,
                            updateRequest:    updateRequest,
                            knowledgeBase:    kb,
                            config:           config,
                            maxVlmIterations: 2);
                        if (token.IsCancellationRequested) return;

                        _statusMsg = "";

                        // Use updated material if available, else fall back to original
                        Material resultMat     = sourceMat;
                        string   resultMatPath = matPath;
                        if (!string.IsNullOrEmpty(result.materialPath))
                        {
                            var m = AssetDatabase.LoadAssetAtPath<Material>(result.materialPath);
                            if (m != null) { resultMat = m; resultMatPath = result.materialPath; }
                        }

                        // Remove the generic UpdatePreview quad and replace with a named one
                        var tempQuad = GameObject.Find($"UpdatePreview — {resultMat.name}");
                        if (tempQuad != null) GameObject.DestroyImmediate(tempQuad);

                        var quad = GameObject.CreatePrimitive(PrimitiveType.Quad);
                        quad.name = $"Edit Result — {resultMat.name}";
                        quad.GetComponent<Renderer>().material = resultMat;
                        Selection.activeGameObject = quad;
                        if (SceneView.lastActiveSceneView != null)
                            SceneView.lastActiveSceneView.FrameSelected();

                        string previewPath = result.afterImagePath ?? _lastPreview;
                        _lastPreview                    = previewPath ?? "";
                        ChatSession.PendingMaterialPath = resultMatPath;
                        ChatSession.State               = ChatState.PostGen;

                        ChatSession.AddBot(
                            $"Done! Updated material saved at:\n{resultMatPath}\n\n" +
                            $"A preview quad '{quad.name}' has been added to your scene.",
                            _lastPreview);
                    }
                }
                catch (OperationCanceledException) { }
                catch (Exception e) { PushError($"Edit failed: {e.Message}"); }
            };
        }

        /// <summary>Applies LLM-specified property changes directly to the material.</summary>
        private static void ApplyMaterialPropertyChanges(Material mat, List<MaterialPropertyChange> changes)
        {
            if (changes == null || changes.Count == 0) return;
            foreach (var c in changes)
            {
                if (!mat.HasProperty(c.property_name))
                {
                    Debug.LogWarning($"[EditApply] Property '{c.property_name}' not found on material '{mat.name}' — skipping.");
                    continue;
                }
                switch (c.property_type?.ToLower())
                {
                    case "float":
                    case "range":
                        mat.SetFloat(c.property_name, c.float_value);
                        Debug.Log($"[EditApply] SetFloat({c.property_name}, {c.float_value})");
                        break;
                    case "color":
                        mat.SetColor(c.property_name, new Color(c.r, c.g, c.b, c.a));
                        Debug.Log($"[EditApply] SetColor({c.property_name}, rgba({c.r},{c.g},{c.b},{c.a}))");
                        break;
                    case "vector":
                        mat.SetVector(c.property_name, new Vector4(c.x, c.y, c.z, c.w));
                        Debug.Log($"[EditApply] SetVector({c.property_name}, ({c.x},{c.y},{c.z},{c.w}))");
                        break;
                    default:
                        Debug.LogWarning($"[EditApply] Unknown property type '{c.property_type}' for '{c.property_name}' — skipping.");
                        break;
                }
            }
        }

        /// <summary>Builds a short human-readable summary of the property changes for the bot message.</summary>
        private static string BuildEditSummary(List<MaterialPropertyChange> changes)
        {
            if (changes == null || changes.Count == 0) return "the material properties";
            var parts = new List<string>();
            foreach (var c in changes)
                parts.Add(!string.IsNullOrEmpty(c.description) ? c.description : $"'{c.property_name}'");
            if (parts.Count == 1) return parts[0];
            return string.Join(", ", parts.GetRange(0, parts.Count - 1)) + " and " + parts[parts.Count - 1];
        }

        private static void TriggerAnimation(string description)
        {
            _cts = new CancellationTokenSource();
            var token = _cts.Token;

            EditorApplication.delayCall += async () =>
            {
                try
                {
                    // ── Step 1: Inform the user we're analysing the request ────
                    ChatSession.AddBot("Let me first see how I should achieve this.");
                    _statusMsg = "thinking...";

                    var config = LoadConfig();
                    var kb     = LoadKB();
                    if (config == null) { PushError("Config asset not found."); return; }

                    // ── Step 2: Resolve the attached material ─────────────────
                    string matPath = ChatSession.PendingMaterialPath;
                    if (!string.IsNullOrEmpty(matPath) && matPath.StartsWith(Application.dataPath))
                        matPath = "Assets" + matPath.Substring(Application.dataPath.Length);

                    Material sourceMat = AssetDatabase.LoadAssetAtPath<Material>(matPath);
                    if (sourceMat == null) { PushError($"Could not load material at: {matPath}"); return; }

                    // ── Step 3: Classify — C# only vs HLSL change needed ──────
                    var properties = AnimationScriptGenerator.ExtractMaterialProperties(sourceMat);
                    var cls = await AnimationScriptGenerator.ClassifyAnimationRequirementsAsync(
                        description, sourceMat.name, properties, config.geminiKey);
                    if (token.IsCancellationRequested) return;

                    if (!cls.needs_hlsl_change)
                    {
                        // ── PATH A: animate existing properties with C# only ──
                        ChatSession.AddBot("Good news. I can achieve this only by animating the existing material properties. Let me craft the animation script.");
                        _statusMsg = "crafting...";

                        var result = await MaterialAnimatorPipelineManager.RunPipelineAsync(
                            sourceMaterial:   sourceMat,
                            animationRequest: description,
                            config:           config,
                            kb:               kb,
                            useKB:            true,
                            userFeedback:     null,
                            onProgress:       s => { _statusMsg = s; });
                        if (token.IsCancellationRequested) return;

                        _statusMsg = "";
                        if (!result.success) { PushError($"Animation generation failed: {result.errorMessage}"); return; }

                        ChatSession.State = ChatState.PostGen;
                        ChatSession.AddBot($"Animation complete! I generated the script '{result.fileName}' at {result.scriptAssetPath}. Unity will now recompile to apply it.");
                    }
                    else
                    {
                        // ── PATH B: update HLSL first, then animate ───────────
                        // Build a human-readable summary of what's missing for the bot message
                        string missingSummary = cls.missing_properties != null && cls.missing_properties.Count > 0
                            ? string.Join(", ", cls.missing_properties.ConvertAll(p => $"'{p.name}'"))
                            : "some shader properties";
                        ChatSession.AddBot($"Hmm. To achieve this animation I first need to update the HLSL shader — specifically, {missingSummary} {(cls.missing_properties?.Count == 1 ? "is" : "are")} missing. Let me do that first, then generate the animation script. This might take a few minutes — please be patient.");
                        _statusMsg = "crafting...";

                        // Step B-1: update the material/HLSL using the precise request from the classifier
                        // cls.hlsl_update_request describes exactly what property to add and how it should behave,
                        // so the VLM comparison can correctly verify the change was applied.
                        string updateRequest = !string.IsNullOrWhiteSpace(cls.hlsl_update_request)
                            ? cls.hlsl_update_request
                            : $"Add the shader properties needed to support this animation: {description}";
                        var updateResult = await HLSLUpdatePipelineManager.RunUpdatePipelineAsync(
                            originalMaterial: sourceMat,
                            updateRequest:    updateRequest,
                            knowledgeBase:    kb,
                            config:           config,
                            maxVlmIterations: 2);
                        if (token.IsCancellationRequested) return;

                        // Use updated material if available, otherwise fall back to original
                        Material animMat = sourceMat;
                        if (!string.IsNullOrEmpty(updateResult.materialPath))
                        {
                            var updatedMat = AssetDatabase.LoadAssetAtPath<Material>(updateResult.materialPath);
                            if (updatedMat != null) animMat = updatedMat;
                        }

                        // Step B-2: generate the C# animation script for the (updated) material
                        var animResult = await MaterialAnimatorPipelineManager.RunPipelineAsync(
                            sourceMaterial:   animMat,
                            animationRequest: description,
                            config:           config,
                            kb:               kb,
                            useKB:            true,
                            userFeedback:     null,
                            onProgress:       s => { _statusMsg = s; });
                        if (token.IsCancellationRequested) return;

                        _statusMsg = "";
                        if (!animResult.success) { PushError($"Animation generation failed: {animResult.errorMessage}"); return; }

                        ChatSession.State = ChatState.PostGen;
                        ChatSession.AddBot($"Animation complete! I generated the script '{animResult.fileName}' at {animResult.scriptAssetPath}. Unity will now recompile to apply it.");
                    }
                }
                catch (OperationCanceledException) { }
                catch (Exception e) { PushError($"Animation failed: {e.Message}"); }
            };
        }

        private static void TriggerEffect(string effectName)
        {
            _cts = new CancellationTokenSource();
            var token = _cts.Token;

            EditorApplication.delayCall += async () =>
            {
                try
                {
                    _statusMsg = "crafting...";

                    // Resolve material
                    string matPath = ChatSession.PendingMaterialPath;
                    if (!string.IsNullOrEmpty(matPath) && matPath.StartsWith(Application.dataPath))
                        matPath = "Assets" + matPath.Substring(Application.dataPath.Length);

                    Material sourceMat = AssetDatabase.LoadAssetAtPath<Material>(matPath);
                    if (sourceMat == null) { PushError($"Could not load material at: {matPath}"); return; }

                    switch (effectName.ToLower())
                    {
                        case "pixelation":
                            await ApplyPixelationEffect(sourceMat, token);
                            break;
                        case "glow":
                            await ApplyGlowEffect(sourceMat, token);
                            break;
                        default:
                            PushError($"Unknown effect: {effectName}");
                            break;
                    }
                }
                catch (OperationCanceledException) { }
                catch (Exception e) { PushError($"Effect failed: {e.Message}"); }
            };
        }

        /// <summary>
        /// Applies pixelation by regenerating the ShaderGraph with usePixelation=true.
        /// No LLM calls — purely client-side ShaderGraph node injection.
        /// </summary>
        private static async Task ApplyPixelationEffect(Material sourceMat, CancellationToken token)
        {
            // ── 1. Find the HLSL source behind this material's shadergraph ────
            string hlslPath = HLSLUpdatePipelineManager.ExtractHlslPathFromMaterial(sourceMat);
            if (string.IsNullOrEmpty(hlslPath))
            {
                PushError("Could not find the HLSL source for this material. Make sure it was generated by this tool.");
                return;
            }

            string hlslGuid = AssetDatabase.AssetPathToGUID(hlslPath);
            if (string.IsNullOrEmpty(hlslGuid)) { PushError($"Could not get GUID for: {hlslPath}"); return; }

            // ── 2. Regenerate the shadergraph with pixelation nodes injected ──
            const string EFFECT_DIR = "Assets/ShaderGraphs/Effects";
            if (!Directory.Exists(EFFECT_DIR)) Directory.CreateDirectory(EFFECT_DIR);

            // Detect if the source material already has glow, so we preserve it
            string existingShaderName = sourceMat.shader != null ? sourceMat.shader.name : "";
            bool alreadyGlow = existingShaderName.IndexOf("Glow", StringComparison.OrdinalIgnoreCase) >= 0
                            || existingShaderName.IndexOf("_Glow", StringComparison.OrdinalIgnoreCase) >= 0;

            string suffix      = alreadyGlow ? "_Glow_Pixelated" : "_Pixelated";
            string baseName    = Path.GetFileNameWithoutExtension(hlslPath) + suffix;
            string newGraphPath = $"{EFFECT_DIR}/{baseName}.shadergraph";

            ShaderGraphJSONGenerator.GenerateFromHLSL(
                hlslPath, hlslGuid, newGraphPath,
                useTransparency: true, usePixelation: true, useGlow: alreadyGlow);

            AssetDatabase.Refresh();
            await Task.Delay(1200);
            AssetDatabase.Refresh();
            await Task.Delay(400);
            if (token.IsCancellationRequested) return;

            // ── 3. Create material from the new shadergraph ───────────────────
            Material effectMat = MaterialPreviewHelper.CreateMaterialForShaderGraph(newGraphPath);
            if (effectMat == null) { PushError("Failed to create pixelated material."); return; }

            // ── 4. Copy all matching properties from original, then set PixelCount
            CopyMatchingMaterialProperties(sourceMat, effectMat);
            string pixelProp = effectMat.HasProperty("PixelCount") ? "PixelCount" : "_PixelCount";
            if (effectMat.HasProperty(pixelProp)) effectMat.SetFloat(pixelProp, 64f);
            EditorUtility.SetDirty(effectMat);
            AssetDatabase.SaveAssets();
            if (token.IsCancellationRequested) return;

            // ── 5. Create named preview quad in scene ─────────────────────────
            string previewDir  = "Assets/ShaderGraphs/Previews";
            if (!Directory.Exists(previewDir)) Directory.CreateDirectory(previewDir);
            string previewPath = $"{previewDir}/{baseName}.png";

            GameObject quad = MaterialPreviewHelper.CreatePreviewQuad(effectMat, true, previewPath);
            quad.name = $"Pixelation Effect — {sourceMat.name}";
            Selection.activeGameObject = quad;
            if (SceneView.lastActiveSceneView != null)
                SceneView.lastActiveSceneView.FrameSelected();

            // Wait for screenshot
            double t0 = EditorApplication.timeSinceStartup;
            while (!File.Exists(previewPath) && (EditorApplication.timeSinceStartup - t0) < 5.0)
                await Task.Delay(200);
            await Task.Delay(100);

            // ── 6. Push result to chat ────────────────────────────────────────
            string savedMatPath             = AssetDatabase.GetAssetPath(effectMat);
            _lastPreview                    = File.Exists(previewPath) ? previewPath : _lastPreview;
            ChatSession.PendingMaterialPath = savedMatPath;
            ChatSession.State               = ChatState.PostGen;
            _statusMsg                      = "";

            ChatSession.AddBot(
                $"Done! Pixelated material saved at:\n{savedMatPath}\n\n" +
                $"A preview quad '{quad.name}' has been added to your scene.",
                _lastPreview);
        }

        /// <summary>
        /// Glow effect — entirely client-side, no LLM calls:
        ///   1. Regenerates the ShaderGraph with useGlow=true:
        ///      • All colour properties switched to HDR mode (colorMode=1) with warm default values > 1.
        ///      • A GlowDensity float property (default 2) added.
        ///      • A Multiply node inserted between the final colour output and BaseColor.
        ///   2. Creates a new material from the updated shadergraph.
        ///   3. Copies all non-colour properties from the original material.
        ///   4. Ensures a global URP Post-Processing Volume with Bloom (intensity=2) is in the scene.
        ///   5. Creates a named preview quad and shows result in chat.
        /// </summary>
        private static async Task ApplyGlowEffect(Material sourceMat, CancellationToken token)
        {
            // ── 1. Find the HLSL source ───────────────────────────────────────
            string hlslPath = HLSLUpdatePipelineManager.ExtractHlslPathFromMaterial(sourceMat);
            if (string.IsNullOrEmpty(hlslPath))
            {
                PushError("Could not find the HLSL source for this material. Make sure it was generated by this tool.");
                return;
            }

            string hlslGuid = AssetDatabase.AssetPathToGUID(hlslPath);
            if (string.IsNullOrEmpty(hlslGuid)) { PushError($"Could not get GUID for: {hlslPath}"); return; }

            // ── 2. Regenerate ShaderGraph with useGlow=true ───────────────────
            const string EFFECT_DIR = "Assets/ShaderGraphs/Effects";
            if (!Directory.Exists(EFFECT_DIR)) Directory.CreateDirectory(EFFECT_DIR);

            // Detect if the source material already has pixelation, so we preserve it
            string existingShaderName = sourceMat.shader != null ? sourceMat.shader.name : "";
            bool alreadyPixelated = existingShaderName.IndexOf("Pixelat", StringComparison.OrdinalIgnoreCase) >= 0;

            string suffix      = alreadyPixelated ? "_Glow_Pixelated" : "_Glow";
            string baseName    = Path.GetFileNameWithoutExtension(hlslPath) + suffix;
            string newGraphPath = $"{EFFECT_DIR}/{baseName}.shadergraph";

            ShaderGraphJSONGenerator.GenerateFromHLSL(
                hlslPath, hlslGuid, newGraphPath,
                useTransparency: true, usePixelation: alreadyPixelated, useGlow: true);

            AssetDatabase.Refresh();
            await Task.Delay(1200);
            AssetDatabase.Refresh();
            await Task.Delay(400);
            if (token.IsCancellationRequested) return;

            // ── 3. Create material from new shadergraph ───────────────────────
            Material effectMat = MaterialPreviewHelper.CreateMaterialForShaderGraph(newGraphPath);
            if (effectMat == null) { PushError("Failed to create glow material."); return; }

            // ── 4. Copy properties from original.
            //       When stacking on an already-pixelated material copy everything including
            //       colors (user's actual colors). When applying glow fresh, also copy colors —
            //       HDR mode comes from colorMode=1 in the shader property, not the value.
            CopyMatchingMaterialProperties(sourceMat, effectMat);

            // Ensure glowIntensity is explicitly set on the material instance
            if (effectMat.HasProperty("glowIntensity"))  effectMat.SetFloat("glowIntensity", 2f);
            if (effectMat.HasProperty("_GlowIntensity")) effectMat.SetFloat("_GlowIntensity", 2f);

            EditorUtility.SetDirty(effectMat);
            AssetDatabase.SaveAssets();
            if (token.IsCancellationRequested) return;

            // ── 5. Add Post-Processing Volume with Bloom to scene (if absent) ─
            EnsureBloomVolume();

            // ── 6. Create named preview quad ──────────────────────────────────
            string previewDir  = "Assets/ShaderGraphs/Previews";
            if (!Directory.Exists(previewDir)) Directory.CreateDirectory(previewDir);
            string previewPath = $"{previewDir}/{baseName}.png";

            GameObject quad = MaterialPreviewHelper.CreatePreviewQuad(effectMat, true, previewPath);
            quad.name = $"Glow Effect — {sourceMat.name}";
            Selection.activeGameObject = quad;
            if (SceneView.lastActiveSceneView != null)
                SceneView.lastActiveSceneView.FrameSelected();

            double t0 = EditorApplication.timeSinceStartup;
            while (!File.Exists(previewPath) && (EditorApplication.timeSinceStartup - t0) < 5.0)
                await Task.Delay(200);
            await Task.Delay(100);

            // ── 7. Push result to chat ────────────────────────────────────────
            string savedMatPath             = AssetDatabase.GetAssetPath(effectMat);
            _lastPreview                    = File.Exists(previewPath) ? previewPath : _lastPreview;
            ChatSession.PendingMaterialPath = savedMatPath;
            ChatSession.State               = ChatState.PostGen;
            _statusMsg                      = "";

            ChatSession.AddBot(
                $"Glow applied! Colour properties are now HDR and a glowIntensity (×2) multiplier drives URP Bloom.\n\n" +
                $"Material saved at:\n{savedMatPath}\n\n" +
                $"Quad '{quad.name}' added to your scene. Make sure Post-Processing is enabled on your camera and press Play to see the bloom.",
                _lastPreview);
        }

        /// <summary>
        /// Adds a global URP Post-Processing Volume with Bloom (intensity 2, threshold 0.9)
        /// to the active scene, unless one already exists.
        /// Uses reflection for the Bloom component to avoid a hard URP assembly dependency.
        /// </summary>
        private static void EnsureBloomVolume()
        {
            // Volume is in com.unity.render-pipelines.core, always present in URP projects.
            var allVolumes = UnityEngine.Object.FindObjectsByType<UnityEngine.Rendering.Volume>(
                FindObjectsSortMode.None);

            // Check whether any existing volume profile already contains a Bloom component.
            foreach (var vol in allVolumes)
            {
                if (vol.sharedProfile == null && vol.profile == null) continue;
                var profile = vol.sharedProfile != null ? vol.sharedProfile : vol.profile;
                if (profile.components.Exists(c => c.GetType().Name == "Bloom" && c.active))
                {
                    Debug.Log("[GlowEffect] Bloom volume already present in scene — skipping creation.");
                    return;
                }
            }

            // No bloom volume found — create one.
            var go     = new GameObject("Glow Bloom Post-Processing");
            var volume = go.AddComponent<UnityEngine.Rendering.Volume>();
            volume.isGlobal = true;
            volume.priority = 1f;

            var profileAsset = ScriptableObject.CreateInstance<UnityEngine.Rendering.VolumeProfile>();
            volume.sharedProfile = profileAsset;

            // Locate the URP Bloom type via reflection (avoids hard dependency on URP assembly).
            Type bloomType = null;
            foreach (var asm in AppDomain.CurrentDomain.GetAssemblies())
            {
                try
                {
                    bloomType = asm.GetType("UnityEngine.Rendering.Universal.Bloom");
                    if (bloomType != null) break;
                }
                catch { /* skip assemblies that throw on GetType */ }
            }

            if (bloomType == null)
            {
                Debug.LogWarning("[GlowEffect] Could not find UnityEngine.Rendering.Universal.Bloom. " +
                                 "Please add a Post-Processing Volume with Bloom (intensity=2) manually.");
                UnityEngine.Object.DestroyImmediate(go);
                return;
            }

            // profile.Add<Bloom>(overrides: true) via reflection
            var addMethod = profileAsset.GetType()
                .GetMethods(System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.Instance)
                .FirstOrDefault(m => m.Name == "Add" && m.IsGenericMethodDefinition);

            if (addMethod == null)
            {
                Debug.LogWarning("[GlowEffect] VolumeProfile.Add<T> not found via reflection. Add Bloom manually.");
                UnityEngine.Object.DestroyImmediate(go);
                return;
            }

            var bloom = addMethod.MakeGenericMethod(bloomType).Invoke(profileAsset, new object[] { true });
            if (bloom == null)
            {
                Debug.LogWarning("[GlowEffect] Failed to add Bloom to volume profile. Add Bloom manually.");
                UnityEngine.Object.DestroyImmediate(go);
                return;
            }

            // Set only intensity = 2, leave all other parameters at default (not overridden)
            SetVolumeParameter(bloom, "intensity", 2f);

            Debug.Log("[GlowEffect] Created Post-Processing Volume with Bloom (intensity=2, threshold=0.9).");
        }

        /// <summary>
        /// Sets value and overrideState on a VolumeParameter field by name.
        /// In URP: overrideState is a public field; value is a property (backed by m_Value).
        /// Try both GetField and GetProperty so this works across URP versions.
        /// </summary>
        private static void SetVolumeParameter(object bloomObj, string fieldName, float value)
        {
            // intensity, threshold, etc. are public fields on the Bloom class itself
            var field = bloomObj.GetType().GetField(fieldName, BindingFlags.Public | BindingFlags.Instance);
            if (field == null) return;
            var param = field.GetValue(bloomObj);
            if (param == null) return;
            var paramType = param.GetType();

            // overrideState is defined on the base VolumeParameter class — walk up the hierarchy
            var t = paramType;
            while (t != null && t != typeof(object))
            {
                var f = t.GetField("overrideState", BindingFlags.Public | BindingFlags.Instance);
                if (f != null) { f.SetValue(param, true); break; }
                t = t.BaseType;
            }

            // value: property in Unity 6 URP (backed by m_Value field in older versions)
            var valueProp = paramType.GetProperty("value", BindingFlags.Public | BindingFlags.Instance);
            if (valueProp != null && valueProp.CanWrite)
                valueProp.SetValue(param, value);
            else
                paramType.GetField("m_Value", BindingFlags.NonPublic | BindingFlags.Instance)
                         ?.SetValue(param, value);
        }

        private static void CopyMatchingMaterialProperties(Material src, Material dst)
        {
            if (src == null || dst == null) return;
            try
            {
                var props = MaterialEditor.GetMaterialProperties(new UnityEngine.Object[] { src });
                foreach (var p in props)
                {
                    if (!dst.HasProperty(p.name)) continue;
                    switch (p.type)
                    {
                        case MaterialProperty.PropType.Float:
                        case MaterialProperty.PropType.Range:
                            dst.SetFloat(p.name, p.floatValue);  break;
                        case MaterialProperty.PropType.Color:
                            dst.SetColor(p.name, p.colorValue);  break;
                        case MaterialProperty.PropType.Vector:
                            dst.SetVector(p.name, p.vectorValue); break;
                        case MaterialProperty.PropType.Texture:
                            if (p.textureValue != null) dst.SetTexture(p.name, p.textureValue); break;
                    }
                }
            }
            catch (Exception ex) { Debug.LogWarning($"[CopyProps] {ex.Message}"); }
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

        /// <summary>
        /// Reads the HLSL code and asks Gemini to suggest sensible default values for
        /// each input parameter. Returns a list in the LLMShaderProperty format so
        /// MaterialPreviewHelper.SetDefaultMaterialProperties can apply them directly.
        /// </summary>
        private static async Task<List<LLMShaderProperty>> SuggestMaterialPropertiesAsync(
            string hlslCode,
            HLSLFunctionInfo functionInfo,
            string geminiKey,
            CancellationToken token)
        {
            var sb = new StringBuilder();
            sb.AppendLine("You are a Unity shader expert. Read this HLSL shader function and suggest sensible, visually pleasing default values for its material properties.");
            sb.AppendLine("The values must make the shape clearly visible — never use zeros, fully-transparent, or extreme values that would hide or break the shape.");
            sb.AppendLine();
            sb.AppendLine("## HLSL CODE");
            sb.AppendLine(hlslCode);
            sb.AppendLine();
            sb.AppendLine("## INPUT PARAMETERS TO SET (ignore UV, ignore output params):");
            foreach (var p in functionInfo.InputParameters)
            {
                if (string.Equals(p.Name, "UV", StringComparison.OrdinalIgnoreCase)) continue;
                sb.AppendLine($"  {p.Name}  ({p.Type})");
            }
            sb.AppendLine();
            sb.AppendLine("## RULES");
            sb.AppendLine("- Colors (float4 whose name contains 'Color'): vivid RGBA in 0-1 range, alpha = 1.0.");
            sb.AppendLine("  Example: a fill color → warm or vivid hue; a stroke color → contrasting hue.");
            sb.AppendLine("- Sizes / widths / heights / radius (float): values that make the shape fill most of the 0-1 UV space, typically 0.3-0.8.");
            sb.AppendLine("- Positions / centers (float2): 0.5, 0.5 (centered) unless name implies edge/offset.");
            sb.AppendLine("- Counts / segment counts / petal counts (float): small positive integers 3-8.");
            sb.AppendLine("- Stroke / border widths (float): thin, 0.01-0.05.");
            sb.AppendLine("- Opacity / alpha standalone (float): 1.0.");
            sb.AppendLine("- Rotation / angle (float): 0.0.");
            sb.AppendLine("- Generic float4 non-color: sensible (x, y, z, w) based on context.");
            sb.AppendLine("- Skip UV parameters and output parameters.");
            sb.AppendLine();
            sb.AppendLine("## OUTPUT FORMAT — return ONLY valid JSON, no markdown, no preamble:");
            sb.AppendLine(@"{
  ""properties"": [
    { ""name"": ""Width"",       ""type"": ""float"",  ""default_value"": 0.6 },
    { ""name"": ""FillColor"",   ""type"": ""float4"", ""default_value"": { ""x"": 1.0, ""y"": 0.75, ""z"": 0.1, ""w"": 1.0 } },
    { ""name"": ""Center"",      ""type"": ""float2"", ""default_value"": { ""x"": 0.5, ""y"": 0.5 } },
    { ""name"": ""StrokeWidth"", ""type"": ""float"",  ""default_value"": 0.02 }
  ]
}");

            string raw = await GeminiApiService.CallGeminiAsync(sb.ToString(), geminiKey);
            if (string.IsNullOrEmpty(raw) || token.IsCancellationRequested) return null;

            var mFence = Regex.Match(raw, @"```(?:json)?\s*([\s\S]*?)```", RegexOptions.Multiline);
            raw = mFence.Success ? mFence.Groups[1].Value.Trim() : raw.Trim();

            try
            {
                var response = JsonConvert.DeserializeObject<LLMShaderResponse>(raw);
                if (response?.properties != null)
                    Debug.Log($"[PropSuggest] LLM suggested {response.properties.Count} property values.");
                return response?.properties;
            }
            catch (Exception ex)
            {
                Debug.LogWarning($"[PropSuggest] JSON parse failed: {ex.Message}");
                return null;
            }
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
                        // Apply random values first as a safe baseline (shape visible even if LLM fails)
                        MaterialPreviewHelper.SetRandomMaterialProperties(mat, functionInfo);

                        // Ask LLM to read the HLSL and suggest sensible values, then override
                        _statusMsg = "choosing good property values...";
                        var config = LoadConfig();
                        if (config != null)
                        {
                            string hlslContent = File.ReadAllText(relativeHlslPath);
                            var suggested = await SuggestMaterialPropertiesAsync(
                                hlslContent, functionInfo, config.geminiKey, token);
                            if (suggested != null && suggested.Count > 0)
                                MaterialPreviewHelper.SetDefaultMaterialProperties(mat, suggested);
                        }
                        EditorUtility.SetDirty(mat);
                        AssetDatabase.SaveAssets();
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
                    ChatSession.PendingMaterialPath = matPath;

                    string responseText = $"Here is the result. You can find the shadergraph in {graphPath} and the material in {matPath}.";
                    ChatSession.AddBot(responseText, _lastPreview);
                }
                catch (OperationCanceledException) { }
                catch (Exception e) { PushError($"HLSL processing failed: {e.Message}"); }
            };
        }
    }

}
