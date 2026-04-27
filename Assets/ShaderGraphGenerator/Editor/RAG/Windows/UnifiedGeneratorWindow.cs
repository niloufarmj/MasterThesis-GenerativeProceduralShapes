using System;
using System.Collections.Generic;
using System.IO;
using System.Threading.Tasks;
using UnityEditor;
using UnityEngine;
using ShaderGraphGenerator.KnowledgeBase;
using ShaderGraphGenerator.Editor;

namespace ShaderGraphGenerator.RAG
{
    /// <summary>
    /// Tool 2.9 — Unified RAG Shape Generator
    ///
    /// The single entry point for all generation modes:
    ///   • Text prompt  → RAG pipeline (decompose → retrieve → Gemini → build → VLM)
    ///   • Image + text → Image-to-Shader pipeline (GPT-4o Vision describe → RAG → Gemini Vision)
    ///
    /// Shared options:
    ///   • Transparency toggle
    ///   • Pixelation effect (adds PixelCount property, retro look)
    ///   • VLM iterations (1–4)
    ///   • Human review + optional KB ingest
    ///   • Output path control
    /// </summary>
    public class UnifiedGeneratorWindow : EditorWindow
    {
        // ─── constants ────────────────────────────────────────────────────────
        private const int    MAX_VLM_ITER     = 4;
        private const int    MAX_HUMAN_ITER   = 4;
        private const int    KB_THRESHOLD     = 8;
        private const int    HUMAN_REJECT_MIN = 7;
        private const string KB_PATH          = "Assets/ShaderGraphGenerator/KnowledgeBase/shape_metadata.json";
        private const string OUTPUT_DIR       = "Assets/ShaderGraphs/RAG_Generated";
        private const string PREVIEW_DIR      = "Assets/ShaderGraphs/Previews";

        // ─── state machine ────────────────────────────────────────────────────
        private enum State { Idle, Running, AwaitingReview, Done }
        private State _state = State.Idle;

        // ─── mode ─────────────────────────────────────────────────────────────
        private enum InputMode { TextPrompt, ImageReference }
        private InputMode _mode = InputMode.TextPrompt;

        // ─── config / KB ──────────────────────────────────────────────────────
        private ShaderGraphGeneratorConfig _config;
        private ShapeKnowledgeBase         _kb;

        // ─── idle inputs ──────────────────────────────────────────────────────
        // Text mode
        private string _prompt = "a cute cartoon snowman with hat, scarf, stick arms and carrot nose";

        // Image mode
        private Texture2D _refImage;
        private string    _editableHints = "e.g. body color, hat color, scarf stripe count";

        // Shared generation options
        private bool _useTransparency = true;
        private bool _usePixelation   = false;
        private int  _pixelCount      = 50;
        private int  _vlmIterations   = 2;

        // Output options
        private bool   _createPreviewQuad = true;
        private string _outputDir         = OUTPUT_DIR;
        private bool   _showAdvanced      = false;

        // ─── pipeline result ──────────────────────────────────────────────────
        private RAGPipelineResult      _ragResult;
        private ImageToShaderResult    _imgResult;
        private Texture2D              _refTexDisplay;
        private Texture2D              _previewTex;

        // ─── review state ─────────────────────────────────────────────────────
        private int    _humanScore     = 8;
        private string _humanComment   = "";
        private int    _humanIteration = 1;
        private string _statusMsg      = "";
        private string _outcomeMsg     = "";
        private bool   _showVlmDetail  = false;

        private Vector2 _scroll;

        // ─── menu ─────────────────────────────────────────────────────────────
        [MenuItem("Tools/ShaderGraph Generator/2.9 Unified RAG Generator")]
        public static void ShowWindow()
        {
            var w = GetWindow<UnifiedGeneratorWindow>("2.9 Unified Generator");
            w.minSize = new Vector2(960, 740);
        }

        // ─── lifecycle ────────────────────────────────────────────────────────
        private void OnEnable() { LoadConfig(); LoadKB(); }

        private void LoadConfig()
        {
            var guids = AssetDatabase.FindAssets("t:ShaderGraphGeneratorConfig");
            if (guids.Length > 0)
                _config = AssetDatabase.LoadAssetAtPath<ShaderGraphGeneratorConfig>(
                    AssetDatabase.GUIDToAssetPath(guids[0]));
        }

        private void LoadKB()
        {
            if (File.Exists(KB_PATH))
                _kb = Newtonsoft.Json.JsonConvert.DeserializeObject<ShapeKnowledgeBase>(
                    File.ReadAllText(KB_PATH));
        }

        // ─── OnGUI ────────────────────────────────────────────────────────────
        private void OnGUI()
        {
            DrawHeader();

            if (_config == null || _kb == null)
            {
                EditorGUILayout.HelpBox("Config or Knowledge Base not found. Check project setup.", MessageType.Error);
                return;
            }

            _scroll = EditorGUILayout.BeginScrollView(_scroll);

            switch (_state)
            {
                case State.Idle:           DrawIdle();    break;
                case State.Running:        DrawRunning(); break;
                case State.AwaitingReview: DrawReview();  break;
                case State.Done:           DrawDone();    break;
            }

            EditorGUILayout.EndScrollView();
        }

        // ═══════════════════════════════════════════════════════════════════════
        //  HEADER
        // ═══════════════════════════════════════════════════════════════════════

        private void DrawHeader()
        {
            var headerStyle = new GUIStyle(EditorStyles.boldLabel)
                { fontSize = 14, alignment = TextAnchor.MiddleCenter };
            var subStyle = new GUIStyle(EditorStyles.centeredGreyMiniLabel)
                { wordWrap = true };

            EditorGUILayout.Space(6);
            GUILayout.Label("Unified RAG Shape Generator", headerStyle);
            GUILayout.Label(
                "Text prompt or reference image  →  RAG decompose & retrieve  →  LLM generate  →  VLM validate  →  Human review",
                subStyle);
            EditorGUILayout.Space(2);
            if (_kb != null)
                GUILayout.Label($"Knowledge Base: {_kb.totalShapes} verified shapes", EditorStyles.centeredGreyMiniLabel);
            DrawDivider();
        }

        // ═══════════════════════════════════════════════════════════════════════
        //  IDLE
        // ═══════════════════════════════════════════════════════════════════════

        private void DrawIdle()
        {
            // ── Input Mode Selector ───────────────────────────────────────────
            DrawSectionLabel("📥  Input Mode");
            EditorGUILayout.BeginHorizontal();
            DrawModeButton("💬  Text Prompt",    InputMode.TextPrompt);
            DrawModeButton("🖼️  Reference Image", InputMode.ImageReference);
            EditorGUILayout.EndHorizontal();
            EditorGUILayout.Space(10);

            // ── Input Area ────────────────────────────────────────────────────
            if (_mode == InputMode.TextPrompt)
                DrawTextInput();
            else
                DrawImageInput();

            EditorGUILayout.Space(10);

            // ── Generation Options ────────────────────────────────────────────
            DrawGenerationOptions();

            EditorGUILayout.Space(10);

            // ── Advanced Settings ─────────────────────────────────────────────
            _showAdvanced = EditorGUILayout.Foldout(_showAdvanced, "⚙  Advanced Settings", true);
            if (_showAdvanced) DrawAdvancedSettings();

            EditorGUILayout.Space(12);

            // ── Generate Button ───────────────────────────────────────────────
            bool ready = IsInputReady();
            GUI.enabled = ready;
            var btnStyle = new GUIStyle(GUI.skin.button) { fontSize = 13, fontStyle = FontStyle.Bold };
            string btnLabel = _mode == InputMode.TextPrompt
                ? "✨  Generate Shape"
                : "🖼  Generate Shader from Image";
            if (GUILayout.Button(btnLabel, btnStyle, GUILayout.Height(48)))
            {
                _humanIteration = 1;
                _ = RunPipelineAsync();
            }
            GUI.enabled = true;

            if (!ready)
                DrawWarning(_mode == InputMode.TextPrompt
                    ? "Enter a text prompt to generate."
                    : "Assign a reference image to generate.");
        }

        private void DrawModeButton(string label, InputMode mode)
        {
            bool active = _mode == mode;
            var style = new GUIStyle(GUI.skin.button)
            {
                fontStyle = active ? FontStyle.Bold : FontStyle.Normal,
                fixedHeight = 32
            };
            if (active)
            {
                GUI.backgroundColor = new Color(0.4f, 0.7f, 1f);
            }
            if (GUILayout.Button(label, style))
                _mode = mode;
            GUI.backgroundColor = Color.white;
        }

        // ── Text Input ────────────────────────────────────────────────────────

        private void DrawTextInput()
        {
            DrawSectionLabel("📝  Shape Description");
            EditorGUILayout.BeginVertical(EditorStyles.helpBox);
            EditorGUILayout.LabelField(
                "Describe the shape or scene you want to generate as a 2D procedural shader.",
                EditorStyles.wordWrappedMiniLabel);
            EditorGUILayout.Space(4);
            _prompt = EditorGUILayout.TextArea(_prompt, GUILayout.Height(80));
            EditorGUILayout.EndVertical();
        }

        // ── Image Input ───────────────────────────────────────────────────────

        private void DrawImageInput()
        {
            DrawSectionLabel("🖼️  Reference Image");
            EditorGUILayout.BeginVertical(EditorStyles.helpBox);
            EditorGUILayout.LabelField(
                "The AI will recreate this image as a procedural HLSL shader material.",
                EditorStyles.wordWrappedMiniLabel);
            EditorGUILayout.Space(4);

            var prev = _refImage;
            _refImage = (Texture2D)EditorGUILayout.ObjectField(
                _refImage, typeof(Texture2D), false, GUILayout.Height(80));
            if (_refImage != prev)
                _refTexDisplay = _refImage;

            // Inline image preview
            if (_refTexDisplay != null)
            {
                EditorGUILayout.Space(4);
                float w = Mathf.Min(280f, position.width - 40f);
                float h = w * (float)_refTexDisplay.height / Mathf.Max(1, _refTexDisplay.width);
                h = Mathf.Clamp(h, 60f, 240f);
                GUILayout.Label(_refTexDisplay, GUILayout.Width(w), GUILayout.Height(h));
            }

            EditorGUILayout.Space(6);
            EditorGUILayout.LabelField("Editable Properties Hint:", EditorStyles.boldLabel);
            EditorGUILayout.LabelField(
                "Which visual aspects should become editable material properties? (optional)",
                EditorStyles.wordWrappedMiniLabel);
            _editableHints = EditorGUILayout.TextArea(_editableHints, GUILayout.Height(48));
            EditorGUILayout.EndVertical();
        }

        // ── Generation Options ────────────────────────────────────────────────

        private void DrawGenerationOptions()
        {
            DrawSectionLabel("🔧  Generation Options");
            EditorGUILayout.BeginVertical(EditorStyles.helpBox);

            // ── Row 1: Transparency + Pixelation ─────────────────────────────
            EditorGUILayout.BeginHorizontal();

            EditorGUILayout.BeginVertical();
            EditorGUILayout.LabelField("Rendering", EditorStyles.boldLabel);
            _useTransparency = EditorGUILayout.Toggle(
                new GUIContent("Transparency",
                    "Enable alpha channel — shapes render with transparent background."),
                _useTransparency);

            // Pixelation with inline pixel count slider
            _usePixelation = EditorGUILayout.Toggle(
                new GUIContent("Pixelation Effect",
                    "Adds a PixelCount property to the shader. Lower values = chunkier pixels (retro look)."),
                _usePixelation);

            if (_usePixelation)
            {
                EditorGUI.indentLevel++;
                EditorGUILayout.BeginHorizontal();
                EditorGUILayout.LabelField("Pixel Count", GUILayout.Width(80));
                _pixelCount = Mathf.RoundToInt(
                    GUILayout.HorizontalSlider(_pixelCount, 4, 256, GUILayout.Width(160)));
                GUILayout.Label(_pixelCount.ToString(), GUILayout.Width(35));
                EditorGUILayout.EndHorizontal();

                // Visual hint
                string pixelHint = _pixelCount <= 16  ? "🕹️  Very retro (chunky)"
                                 : _pixelCount <= 40  ? "🎮  Retro (pixel art)"
                                 : _pixelCount <= 80  ? "📺  Moderate pixelation"
                                 : _pixelCount <= 150 ? "🖼️  Fine pixelation"
                                 :                      "🔍  Subtle (almost smooth)";
                EditorGUILayout.LabelField(pixelHint, EditorStyles.centeredGreyMiniLabel);
                EditorGUI.indentLevel--;
            }
            EditorGUILayout.EndVertical();

            GUILayout.Space(20);

            // ── VLM iterations ────────────────────────────────────────────────
            EditorGUILayout.BeginVertical();
            EditorGUILayout.LabelField("Quality Control", EditorStyles.boldLabel);

            EditorGUILayout.BeginHorizontal();
            EditorGUILayout.LabelField(
                new GUIContent("VLM Iterations",
                    "How many times the VLM can reject and request a re-generation. More = better quality but slower & more costly."),
                GUILayout.Width(100));
            _vlmIterations = EditorGUILayout.IntSlider(_vlmIterations, 1, MAX_VLM_ITER);
            EditorGUILayout.EndHorizontal();

            string iterHint = _vlmIterations == 1 ? "Fast, single attempt"
                            : _vlmIterations == 2 ? "Balanced (recommended)"
                            : _vlmIterations == 3 ? "High quality, slower"
                            :                       "Maximum quality (expensive)";
            EditorGUILayout.LabelField(iterHint, EditorStyles.centeredGreyMiniLabel);

            EditorGUILayout.Space(4);
            _createPreviewQuad = EditorGUILayout.Toggle(
                new GUIContent("Create Preview Quad",
                    "Spawn a quad in the scene after generation so you can see the result immediately."),
                _createPreviewQuad);
            EditorGUILayout.EndVertical();

            EditorGUILayout.EndHorizontal();
            EditorGUILayout.EndVertical();
        }

        private void DrawAdvancedSettings()
        {
            EditorGUILayout.BeginVertical(EditorStyles.helpBox);
            EditorGUILayout.LabelField("Output Directory:", EditorStyles.boldLabel);
            _outputDir = EditorGUILayout.TextField(_outputDir);
            EditorGUILayout.Space(4);
            EditorGUILayout.LabelField("Config Asset:", EditorStyles.boldLabel);
            _config = (ShaderGraphGeneratorConfig)EditorGUILayout.ObjectField(
                _config, typeof(ShaderGraphGeneratorConfig), false);
            EditorGUILayout.EndVertical();
        }

        // ═══════════════════════════════════════════════════════════════════════
        //  RUNNING
        // ═══════════════════════════════════════════════════════════════════════

        private void DrawRunning()
        {
            EditorGUILayout.Space(20);
            GUILayout.Label("⏳  Generating…", new GUIStyle(EditorStyles.boldLabel)
                { fontSize = 13, alignment = TextAnchor.MiddleCenter });
            EditorGUILayout.Space(8);

            if (!string.IsNullOrEmpty(_statusMsg))
                EditorGUILayout.HelpBox(_statusMsg, MessageType.Info);

            GUILayout.Label("This may take 30–120 seconds. Do not close the window.",
                EditorStyles.centeredGreyMiniLabel);
        }

        // ═══════════════════════════════════════════════════════════════════════
        //  REVIEW
        // ═══════════════════════════════════════════════════════════════════════

        private void DrawReview()
        {
            // ── Result summary bar ────────────────────────────────────────────
            string shapeName = _ragResult?.fileName ?? _imgResult?.fileName ?? "—";
            int    vlmScore  = _ragResult?.vmlScore  ?? _imgResult?.vlmScore  ?? 0;
            string vlmFeedback = _ragResult?.vmlFeedback ?? _imgResult?.vlmFeedback ?? "";

            DrawSectionLabel("📊  Pipeline Result");
            EditorGUILayout.BeginVertical(EditorStyles.helpBox);
            EditorGUILayout.LabelField($"Shape:      {shapeName}");
            EditorGUILayout.LabelField($"VLM Score:  {vlmScore}/10");
            EditorGUILayout.EndVertical();

            // VLM feedback toggle
            _showVlmDetail = EditorGUILayout.Foldout(_showVlmDetail, "VLM Feedback", true);
            if (_showVlmDetail && !string.IsNullOrEmpty(vlmFeedback))
                EditorGUILayout.TextArea(vlmFeedback, GUILayout.Height(70));

            EditorGUILayout.Space(8);

            // ── Side-by-side images ───────────────────────────────────────────
            float halfW = (position.width - 50f) * 0.5f;
            float imgH  = halfW;

            EditorGUILayout.BeginHorizontal();

            // Left: reference image (only for image mode) or placeholder
            EditorGUILayout.BeginVertical(GUILayout.Width(halfW));
            GUILayout.Label(_mode == InputMode.ImageReference ? "REFERENCE IMAGE" : "INPUT", EditorStyles.boldLabel);
            if (_mode == InputMode.ImageReference && _refTexDisplay != null)
                GUILayout.Label(_refTexDisplay, GUILayout.Width(halfW), GUILayout.Height(imgH));
            else
                EditorGUILayout.LabelField("(text prompt mode — no reference)", EditorStyles.miniLabel);
            EditorGUILayout.EndVertical();

            GUILayout.Space(8);

            // Right: rendered preview
            EditorGUILayout.BeginVertical(GUILayout.Width(halfW));
            GUILayout.Label("RENDERED PREVIEW", EditorStyles.boldLabel);
            if (_previewTex != null)
                GUILayout.Label(_previewTex, GUILayout.Width(halfW), GUILayout.Height(imgH));
            else
                EditorGUILayout.LabelField("(preview not available)", EditorStyles.miniLabel);
            EditorGUILayout.EndVertical();

            EditorGUILayout.EndHorizontal();

            EditorGUILayout.Space(12);

            // ── Human rating ──────────────────────────────────────────────────
            DrawSectionLabel($"⭐  Your Rating   (attempt {_humanIteration}/{MAX_HUMAN_ITER})");
            EditorGUILayout.BeginVertical(EditorStyles.helpBox);
            EditorGUILayout.LabelField(
                $"Score < {HUMAN_REJECT_MIN} → retry.   Both VLM & human ≥ {KB_THRESHOLD} → add to library.",
                EditorStyles.wordWrappedMiniLabel);

            EditorGUILayout.Space(4);
            EditorGUILayout.BeginHorizontal();
            GUILayout.Label("Score:", GUILayout.Width(48));
            _humanScore = Mathf.RoundToInt(GUILayout.HorizontalSlider(_humanScore, 0, 10, GUILayout.Width(340)));

            // Colored score badge
            var badgeStyle = new GUIStyle(EditorStyles.boldLabel) { fontSize = 16 };
            badgeStyle.normal.textColor = _humanScore >= 8 ? new Color(0.2f, 0.8f, 0.2f)
                                        : _humanScore >= 6 ? new Color(1f, 0.7f, 0.1f)
                                        : new Color(0.9f, 0.2f, 0.2f);
            GUILayout.Label(_humanScore.ToString(), badgeStyle, GUILayout.Width(30));
            EditorGUILayout.EndHorizontal();

            EditorGUILayout.Space(4);
            GUILayout.Label("Comment / feedback for retry (optional):");
            _humanComment = EditorGUILayout.TextField(_humanComment);
            EditorGUILayout.EndVertical();

            EditorGUILayout.Space(8);

            // ── Action buttons ────────────────────────────────────────────────
            EditorGUILayout.BeginHorizontal();

            bool canAccept = _humanScore >= HUMAN_REJECT_MIN;
            GUI.enabled = canAccept;
            GUI.backgroundColor = canAccept ? new Color(0.3f, 0.9f, 0.3f) : Color.white;
            if (GUILayout.Button($"✅  Accept  ({_humanScore}/10)", GUILayout.Height(36)))
                HandleAccept();
            GUI.backgroundColor = Color.white;
            GUI.enabled = true;

            bool canRetry = _humanIteration < MAX_HUMAN_ITER;
            GUI.enabled = canRetry;
            GUI.backgroundColor = new Color(1f, 0.85f, 0.3f);
            if (GUILayout.Button("🔄  Retry with Feedback", GUILayout.Height(36)))
                _ = RetryAsync();
            GUI.backgroundColor = Color.white;
            GUI.enabled = true;

            GUI.backgroundColor = new Color(1f, 0.4f, 0.4f);
            if (GUILayout.Button("🗑  Discard", GUILayout.Height(36)))
                ResetToIdle();
            GUI.backgroundColor = Color.white;

            EditorGUILayout.EndHorizontal();

            if (!canAccept)
                DrawWarning($"Raise score to at least {HUMAN_REJECT_MIN} to accept.");
            if (!canRetry)
                DrawWarning("Max human retries reached. Accept or discard.");
        }

        // ═══════════════════════════════════════════════════════════════════════
        //  DONE
        // ═══════════════════════════════════════════════════════════════════════

        private void DrawDone()
        {
            EditorGUILayout.Space(16);
            GUILayout.Label("✓  Generation Complete", new GUIStyle(EditorStyles.boldLabel)
                { fontSize = 13, alignment = TextAnchor.MiddleCenter });
            EditorGUILayout.Space(8);
            EditorGUILayout.TextArea(_outcomeMsg, EditorStyles.wordWrappedLabel, GUILayout.Height(80));

            string matPath = _ragResult?.materialPath ?? _imgResult?.materialPath;
            if (!string.IsNullOrEmpty(matPath))
            {
                EditorGUILayout.Space(6);
                if (GUILayout.Button("📂  Select Material in Project", GUILayout.Height(30)))
                {
                    var mat = AssetDatabase.LoadAssetAtPath<Material>(matPath);
                    if (mat) Selection.activeObject = mat;
                }
            }

            EditorGUILayout.Space(10);
            if (GUILayout.Button("🔁  Generate Another", GUILayout.Height(36)))
                ResetToIdle();
        }

        // ═══════════════════════════════════════════════════════════════════════
        //  PIPELINE EXECUTION
        // ═══════════════════════════════════════════════════════════════════════

        private async Task RunPipelineAsync(string extraFeedback = null)
        {
            _state    = State.Running;
            _ragResult = null;
            _imgResult = null;
            _previewTex = null;
            Repaint();

            try
            {
                if (_mode == InputMode.TextPrompt)
                    await RunTextPipelineAsync(extraFeedback);
                else
                    await RunImagePipelineAsync(extraFeedback);
            }
            catch (Exception ex)
            {
                Debug.LogError($"[UnifiedGen] Pipeline exception: {ex.Message}\n{ex.StackTrace}");
                EditorUtility.DisplayDialog("Pipeline Error", ex.Message, "OK");
                _state = State.Idle;
            }

            Repaint();
        }

        // ── Text pipeline ─────────────────────────────────────────────────────

        private async Task RunTextPipelineAsync(string extraFeedback)
        {
            string prompt = string.IsNullOrWhiteSpace(extraFeedback)
                ? _prompt
                : _prompt + "\n\n[Previous attempt feedback]: " + extraFeedback;

            _statusMsg = "Decomposing shape → retrieving primitives → generating HLSL…";
            Repaint();

            // Use the existing RAGPipelineManager but with pixelation passed through
            _ragResult = await RunRAGWithPixelationAsync(prompt);

            if (_ragResult == null || string.IsNullOrEmpty(_ragResult.materialPath))
            {
                EditorUtility.DisplayDialog("Error", _ragResult?.errorMessage ?? "Pipeline failed.", "OK");
                _state = State.Idle;
                return;
            }

            LoadPreview(_ragResult.previewImagePath);

            if (_createPreviewQuad && !string.IsNullOrEmpty(_ragResult.materialPath))
                SpawnPreviewQuad(_ragResult.materialPath, _ragResult.fileName);

            _state = State.AwaitingReview;
        }

        // ── Image pipeline ────────────────────────────────────────────────────

        private async Task RunImagePipelineAsync(string extraFeedback)
        {
            string assetPath = AssetDatabase.GetAssetPath(_refImage);
            string projectRoot = Path.GetDirectoryName(Application.dataPath);
            string absPath = string.IsNullOrEmpty(assetPath)
                ? null
                : Path.GetFullPath(Path.Combine(projectRoot, assetPath));

            if (string.IsNullOrEmpty(absPath) || !File.Exists(absPath))
            {
                EditorUtility.DisplayDialog("Error", "Cannot resolve image path on disk.", "OK");
                _state = State.Idle;
                return;
            }

            string hints = _editableHints;
            if (!string.IsNullOrWhiteSpace(extraFeedback))
                hints += "\n\n[Previous feedback]: " + extraFeedback;

            _statusMsg = "Step 1/4: GPT-4o Vision describing image…";
            Repaint();

            _imgResult = await ImageToShaderPipelineManager.RunPipelineAsync(
                absPath, hints, _kb, _config, _vlmIterations,
                usePixelation: _usePixelation, pixelCount: _pixelCount);

            if (_imgResult == null || string.IsNullOrEmpty(_imgResult.materialPath))
            {
                EditorUtility.DisplayDialog("Error", _imgResult?.errorMessage ?? "Pipeline failed.", "OK");
                _state = State.Idle;
                return;
            }

            LoadPreview(_imgResult.previewImagePath);

            if (_createPreviewQuad)
                SpawnPreviewQuad(_imgResult.materialPath, _imgResult.fileName);

            _state = State.AwaitingReview;
        }

        // ── RAG with pixelation support ───────────────────────────────────────
        // RAGPipelineManager doesn't expose pixelation yet, so we call the inner
        // pieces directly here to pass usePixelation to ShaderGraphBuilder.

        private async Task<RAGPipelineResult> RunRAGWithPixelationAsync(string userRequest)
        {
            var result = new RAGPipelineResult { userRequest = userRequest };

            try
            {
                if (!Directory.Exists(_outputDir)) Directory.CreateDirectory(_outputDir);
                if (!Directory.Exists(PREVIEW_DIR)) Directory.CreateDirectory(PREVIEW_DIR);

                _statusMsg = "Generating HLSL with RAG…";
                Repaint();

                var (llmResponse, _, __) = await RAGShapeGenerator.GenerateWithRAGAsync(
                    userRequest, _kb, _config, _useTransparency);

                if (llmResponse == null)
                {
                    result.errorMessage = "LLM generation failed.";
                    return result;
                }

                result.fileName   = llmResponse.file_name;
                result.hlslCode   = llmResponse.hlsl_code;
                result.properties = llmResponse.properties;

                // Save HLSL
                string hlslPath = Path.Combine(_outputDir, $"{llmResponse.file_name}.hlsl");
                File.WriteAllText(hlslPath, llmResponse.hlsl_code);
                AssetDatabase.Refresh();

                // Build ShaderGraph — pass usePixelation!
                _statusMsg = "Building ShaderGraph…";
                Repaint();
                string sgPath = Path.Combine(_outputDir, $"{llmResponse.file_name}.shadergraph");
                string hlslGuid = AssetDatabase.AssetPathToGUID(hlslPath);
                var functionInfo = ShaderGraphJSONGenerator.GenerateFromHLSL(
                    hlslPath, hlslGuid, sgPath, _useTransparency, _usePixelation);
                AssetDatabase.Refresh();
                result.shaderGraphPath = sgPath;

                await Task.Delay(1200);
                AssetDatabase.Refresh();
                await Task.Delay(400);

                var shader = AssetDatabase.LoadAssetAtPath<Shader>(sgPath);
                if (shader == null) { result.errorMessage = "Shader failed to load."; return result; }

                // Create Material
                string matPath = Path.Combine(_outputDir, $"{llmResponse.file_name}.mat");
                if (AssetDatabase.LoadAssetAtPath<UnityEngine.Object>(matPath) != null)
                    AssetDatabase.DeleteAsset(matPath);
                var mat = new Material(shader);
                AssetDatabase.CreateAsset(mat, matPath);
                AssetDatabase.SaveAssets();
                AssetDatabase.Refresh();
                mat = AssetDatabase.LoadAssetAtPath<Material>(matPath);

                // Apply properties
                if (functionInfo != null)
                    MaterialPreviewHelper.SetRandomMaterialProperties(mat, functionInfo);
                if (llmResponse.properties != null)
                    MaterialPreviewHelper.SetDefaultMaterialProperties(mat, llmResponse.properties);
                if (_usePixelation && mat.HasProperty("PixelCount"))
                    mat.SetFloat("PixelCount", _pixelCount);
                else if (_usePixelation && mat.HasProperty("_PixelCount"))
                    mat.SetFloat("_PixelCount", _pixelCount);

                EditorUtility.SetDirty(mat);
                AssetDatabase.SaveAssets();
                result.materialPath = matPath;

                // Render preview + VLM evaluate
                _statusMsg = "Rendering preview and running VLM evaluation…";
                Repaint();

                // Use existing pipeline for the VLM loop (1 iteration for simplicity;
                // full loop is inside RAGPipelineManager for the non-pixelation path)
                string projectRoot = Path.GetDirectoryName(Application.dataPath);
                string previewRel  = Path.Combine(PREVIEW_DIR, $"{llmResponse.file_name}_preview.png");
                string previewAbs  = Path.GetFullPath(Path.Combine(projectRoot, previewRel));
                Directory.CreateDirectory(Path.GetDirectoryName(previewAbs));

                bool rendered = await RenderMaterialToPreviewAsync(mat, previewAbs);
                result.previewImagePath = rendered ? previewAbs : null;

                if (rendered && !string.IsNullOrEmpty(result.previewImagePath))
                {
                    var evalResponse = await OpenAIApiService.CallOpenAIEvalAsync(
                        userRequest, llmResponse.hlsl_code, llmResponse.properties,
                        result.previewImagePath, _config.openAIKey);

                    if (!string.IsNullOrEmpty(evalResponse))
                    {
                        var eval = Newtonsoft.Json.JsonConvert.DeserializeObject<LLMMatchScoreResponse>(evalResponse);
                        result.vmlScore    = eval.score;
                        result.vmlFeedback = eval.explanation;
                        result.success     = eval.score > 7;
                    }
                }
                else
                {
                    result.vmlScore = 5;
                    result.vmlFeedback = "Preview render failed — VLM skipped.";
                }

                return result;
            }
            catch (Exception ex)
            {
                result.errorMessage = ex.Message;
                Debug.LogError($"[UnifiedGen] RAG pipeline error: {ex.Message}\n{ex.StackTrace}");
                return result;
            }
        }

        // ── Retry ─────────────────────────────────────────────────────────────

        private async Task RetryAsync()
        {
            _humanIteration++;
            string feedback = _humanComment;
            _humanComment = "";
            await RunPipelineAsync(feedback);
        }

        // ── Accept ────────────────────────────────────────────────────────────

        private void HandleAccept()
        {
            int    vlmScore  = _ragResult?.vmlScore  ?? _imgResult?.vlmScore  ?? 0;
            string hlslCode  = _ragResult?.hlslCode  ?? _imgResult?.hlslCode  ?? "";
            string fileName  = _ragResult?.fileName  ?? _imgResult?.fileName  ?? "unknown";
            string matPath   = _ragResult?.materialPath ?? _imgResult?.materialPath ?? "";
            string desc      = _imgResult?.visualDescription ?? _prompt;

            bool addToKB = vlmScore >= KB_THRESHOLD && _humanScore >= KB_THRESHOLD
                           && !string.IsNullOrEmpty(hlslCode);

            if (addToKB)
            {
                var entry = new ShapeMetadata
                {
                    fileName          = fileName,
                    filePath          = Path.Combine(_outputDir, fileName + ".hlsl"),
                    originalPrompt    = (_mode == InputMode.TextPrompt ? _prompt : desc)
                                         .Substring(0, Math.Min(200, desc.Length)),
                    visualDescription = desc,
                    dateAdded         = DateTime.Now.ToString("yyyy-MM-dd")
                };

                if (_kb == null) _kb = new ShapeKnowledgeBase();
                _kb.shapes.Add(entry);
                _kb.totalShapes = _kb.shapes.Count;
                File.WriteAllText(KB_PATH,
                    Newtonsoft.Json.JsonConvert.SerializeObject(_kb, Newtonsoft.Json.Formatting.Indented));
                AssetDatabase.Refresh();

                _outcomeMsg = $"✓ '{fileName}' accepted and added to the library!\n" +
                              $"   VLM: {vlmScore}/10   Human: {_humanScore}/10\n" +
                              $"   Library now has {_kb.totalShapes} shapes.";
            }
            else
            {
                _outcomeMsg = $"✓ '{fileName}' accepted (not added to library).\n";
                if (vlmScore  < KB_THRESHOLD) _outcomeMsg += $"   VLM score {vlmScore}/10 is below threshold {KB_THRESHOLD}.\n";
                if (_humanScore < KB_THRESHOLD) _outcomeMsg += $"   Your score {_humanScore}/10 is below threshold {KB_THRESHOLD}.\n";
            }

            _state = State.Done;
            Repaint();
        }

        // ═══════════════════════════════════════════════════════════════════════
        //  HELPERS
        // ═══════════════════════════════════════════════════════════════════════

        private bool IsInputReady() =>
            _mode == InputMode.TextPrompt
                ? !string.IsNullOrWhiteSpace(_prompt)
                : _refImage != null;

        private void ResetToIdle()
        {
            _state         = State.Idle;
            _ragResult     = null;
            _imgResult     = null;
            _previewTex    = null;
            _humanScore    = 8;
            _humanComment  = "";
            _humanIteration = 1;
            _statusMsg     = "";
            _outcomeMsg    = "";
            _showVlmDetail = false;
            Repaint();
        }

        private void LoadPreview(string absPath)
        {
            if (string.IsNullOrEmpty(absPath) || !File.Exists(absPath)) return;
            _previewTex = new Texture2D(2, 2);
            _previewTex.LoadImage(File.ReadAllBytes(absPath));
        }

        private void SpawnPreviewQuad(string matPath, string name)
        {
            var mat = AssetDatabase.LoadAssetAtPath<Material>(matPath);
            if (mat == null) return;
            var quad = GameObject.CreatePrimitive(PrimitiveType.Quad);
            quad.name = $"RAG Preview — {name}";
            quad.GetComponent<Renderer>().material = mat;
            Selection.activeGameObject = quad;
            if (SceneView.lastActiveSceneView != null)
                SceneView.lastActiveSceneView.FrameSelected();
        }

        private static async Task<bool> RenderMaterialToPreviewAsync(Material mat, string absPath)
        {
            var allR = UnityEngine.Object.FindObjectsByType<Renderer>(FindObjectsSortMode.None);
            var wasEnabled = new bool[allR.Length];
            for (int i = 0; i < allR.Length; i++) { wasEnabled[i] = allR[i].enabled; allR[i].enabled = false; }

            GameObject quad = null; GameObject camGO = null; Camera cam = null;
            RenderTexture rt = null; Texture2D tex = null;
            try
            {
                quad = GameObject.CreatePrimitive(PrimitiveType.Quad);
                quad.GetComponent<Renderer>().material = mat;
                quad.transform.SetPositionAndRotation(Vector3.zero, Quaternion.identity);
                camGO = new GameObject("_UnifiedGenCam");
                cam   = camGO.AddComponent<Camera>();
                cam.transform.position = new Vector3(0, 0, -2);
                cam.transform.LookAt(quad.transform);
                cam.clearFlags = CameraClearFlags.SolidColor;
                cam.backgroundColor = Color.white;
                cam.orthographic = true; cam.orthographicSize = 0.55f;
                cam.cullingMask = 1 << quad.layer;
                rt = new RenderTexture(512, 512, 24); cam.targetTexture = rt;
                await Task.Delay(100); cam.Render();
                RenderTexture.active = rt;
                tex = new Texture2D(512, 512, TextureFormat.RGBA32, false);
                tex.ReadPixels(new Rect(0,0,512,512), 0, 0); tex.Apply();
                var px = tex.GetPixels32();
                for (int i = 0; i < px.Length; i++)
                {
                    float a = px[i].a / 255f;
                    px[i].r = (byte)(px[i].r * a + 255*(1-a));
                    px[i].g = (byte)(px[i].g * a + 255*(1-a));
                    px[i].b = (byte)(px[i].b * a + 255*(1-a));
                    px[i].a = 255;
                }
                tex.SetPixels32(px); tex.Apply();
                File.WriteAllBytes(absPath, tex.EncodeToPNG());
                return true;
            }
            catch (Exception ex) { Debug.LogError($"[UnifiedGen] Render failed: {ex.Message}"); return false; }
            finally
            {
                RenderTexture.active = null;
                if (cam != null) cam.targetTexture = null;
                if (rt  != null) { rt.Release(); UnityEngine.Object.DestroyImmediate(rt); }
                if (tex != null) UnityEngine.Object.DestroyImmediate(tex);
                if (camGO != null) UnityEngine.Object.DestroyImmediate(camGO);
                if (quad  != null) UnityEngine.Object.DestroyImmediate(quad);
                for (int i = 0; i < allR.Length; i++)
                    if (allR[i] != null) allR[i].enabled = wasEnabled[i];
                AssetDatabase.Refresh();
            }
        }

        // ─── UI helpers ───────────────────────────────────────────────────────

        private static void DrawSectionLabel(string text)
        {
            EditorGUILayout.Space(4);
            GUILayout.Label(text, EditorStyles.boldLabel);
        }

        private static void DrawDivider()
        {
            EditorGUILayout.Space(4);
            var rect = EditorGUILayout.GetControlRect(false, 1);
            EditorGUI.DrawRect(rect, new Color(0.5f, 0.5f, 0.5f, 0.3f));
            EditorGUILayout.Space(4);
        }

        private static void DrawWarning(string msg)
        {
            EditorGUILayout.HelpBox(msg, MessageType.Warning);
        }
    }
}