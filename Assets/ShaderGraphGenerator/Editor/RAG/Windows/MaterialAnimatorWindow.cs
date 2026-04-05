using System;
using System.Collections.Generic;
using System.IO;
using System.Threading.Tasks;
using UnityEditor;
using UnityEngine;
using ShaderGraphGenerator.Editor;
using ShaderGraphGenerator.KnowledgeBase;

namespace ShaderGraphGenerator.RAG
{
    /// <summary>
    /// Tool 2.10 — Material Animator
    ///
    /// Flow:
    ///   1. User picks a material + writes an animation description.
    ///   2. Pipeline reads material properties, retrieves similar animations from KB,
    ///      calls Gemini to generate a C# MonoBehaviour animation script.
    ///   3. Script is saved → Unity recompiles → script is attached to a new quad.
    ///   4. User presses Play, watches animation, then rates it.
    ///   5. Score ≥ 8 → save to animation library (with embedding for future retrieval).
    /// </summary>
    public class MaterialAnimatorWindow : EditorWindow
    {
        // ─── constants ────────────────────────────────────────────────────────
        private const int    MAX_HUMAN_ITER  = 3;
        private const int    KB_THRESHOLD    = 8;
        private const int    ACCEPT_MIN      = 6;

        // ─── state machine ────────────────────────────────────────────────────
        private enum State { Idle, Running, WaitingForCompile, AwaitingReview, Done }
        private State _state = State.Idle;

        // ─── config / KB ──────────────────────────────────────────────────────
        private ShaderGraphGeneratorConfig _config;
        private ShapeKnowledgeBase         _kb;

        // ─── idle inputs ──────────────────────────────────────────────────────
        private Material _sourceMaterial;
        private string   _animRequest = "pulse the size gently in and out, slowly cycle the main color through warm hues";
        private bool     _useKB       = true;

        // ─── detected properties display ─────────────────────────────────────
        private List<MaterialPropertyInfo> _detectedProps = new List<MaterialPropertyInfo>();
        private bool _showAllProps = false;

        // ─── pipeline result ──────────────────────────────────────────────────
        private AnimationPipelineResult _result;
        private string _statusMsg = "";
        private bool   _showCode  = false;

        // ─── review state ─────────────────────────────────────────────────────
        private int    _humanScore     = 8;
        private string _humanComment   = "";
        private int    _humanIteration = 1;
        private string _outcomeMsg     = "";

        // ─── tag editing ──────────────────────────────────────────────────────
        private string _newTag = "";

        private Vector2 _scroll;

        // ─── menu ─────────────────────────────────────────────────────────────
        [MenuItem("Tools/ShaderGraph Generator/2.10 Material Animator")]
        public static void ShowWindow()
        {
            var w = GetWindow<MaterialAnimatorWindow>("2.10 Material Animator");
            w.minSize = new Vector2(700, 600);
        }

        // ─── lifecycle ────────────────────────────────────────────────────────
        private void OnEnable()
        {
            LoadConfig();
            LoadKB();

            // If we survived a domain reload mid-pipeline, restore state
            if (MaterialAnimatorPipelineManager.IsPendingReload)
            {
                _state    = State.WaitingForCompile;
                _statusMsg = "Waiting for Unity to finish compiling…";
            }
        }

        private void LoadConfig()
        {
            var guids = AssetDatabase.FindAssets("t:ShaderGraphGeneratorConfig");
            if (guids.Length > 0)
                _config = AssetDatabase.LoadAssetAtPath<ShaderGraphGeneratorConfig>(
                    AssetDatabase.GUIDToAssetPath(guids[0]));
        }

        private const string KB_PATH = "Assets/ShaderGraphGenerator/KnowledgeBase/shape_metadata.json";

        private void LoadKB()
        {
            if (System.IO.File.Exists(KB_PATH))
                _kb = Newtonsoft.Json.JsonConvert.DeserializeObject<ShapeKnowledgeBase>(
                    System.IO.File.ReadAllText(KB_PATH));
            else
                _kb = new ShapeKnowledgeBase();
        }

        // ─── OnGUI ────────────────────────────────────────────────────────────
        private void OnGUI()
        {
            // Poll for domain-reload resume every frame
            if (MaterialAnimatorPipelineManager.PollResumeNotification(
                    out bool resumeSuccess, out string resumeMsg))
            {
                if (resumeSuccess)
                {
                    _statusMsg = resumeMsg;
                    _state     = State.AwaitingReview;
                }
                else
                {
                    EditorUtility.DisplayDialog("Script Error", resumeMsg, "OK");
                    _state = State.Idle;
                }
                Repaint();
            }

            DrawHeader();
            EditorGUILayout.Space(4);

            if (_config == null)
            {
                EditorGUILayout.HelpBox("ShaderGraphGeneratorConfig not found in project.", MessageType.Error);
                return;
            }

            _scroll = EditorGUILayout.BeginScrollView(_scroll);
            switch (_state)
            {
                case State.Idle:            DrawIdle();           break;
                case State.Running:         DrawRunning();        break;
                case State.WaitingForCompile: DrawWaitingCompile(); break;
                case State.AwaitingReview:  DrawReview();         break;
                case State.Done:            DrawDone();           break;
            }
            EditorGUILayout.EndScrollView();
        }

        // ═══════════════════════════════════════════════════════════════════════
        //  HEADER
        // ═══════════════════════════════════════════════════════════════════════

        private void DrawHeader()
        {
            var bold14 = new GUIStyle(EditorStyles.boldLabel) { fontSize = 14, alignment = TextAnchor.MiddleCenter };
            EditorGUILayout.Space(6);
            GUILayout.Label("🎬  Material Animator", bold14);
            GUILayout.Label(
                "Pick a material  →  describe the animation  →  AI writes a C# script  →  attached to a quad in scene",
                new GUIStyle(EditorStyles.centeredGreyMiniLabel) { wordWrap = true });
            EditorGUILayout.Space(2);
            int totalAnims = 0;
            if (_kb != null) foreach (var s in _kb.shapes) totalAnims += s.animators.Count;
            GUILayout.Label($"Knowledge Base: {_kb?.totalShapes ?? 0} shapes · {totalAnims} saved animations",
                EditorStyles.centeredGreyMiniLabel);
            DrawDivider();
        }

        // ═══════════════════════════════════════════════════════════════════════
        //  IDLE
        // ═══════════════════════════════════════════════════════════════════════

        private void DrawIdle()
        {
            // ── Material Picker ───────────────────────────────────────────────
            DrawSectionLabel("🎨  Source Material");
            EditorGUILayout.BeginVertical(EditorStyles.helpBox);
            EditorGUILayout.LabelField(
                "The animation script will read and animate THIS material's properties.",
                EditorStyles.wordWrappedMiniLabel);
            EditorGUILayout.Space(4);

            var prevMat = _sourceMaterial;
            _sourceMaterial = (Material)EditorGUILayout.ObjectField(
                _sourceMaterial, typeof(Material), allowSceneObjects: false);

            if (_sourceMaterial != prevMat && _sourceMaterial != null)
                _detectedProps = AnimationScriptGenerator.ExtractMaterialProperties(_sourceMaterial);

            // Show detected properties
            if (_sourceMaterial != null && _detectedProps.Count > 0)
            {
                EditorGUILayout.Space(4);
                int show = _showAllProps ? _detectedProps.Count : Math.Min(6, _detectedProps.Count);
                GUILayout.Label($"Detected animatable properties ({_detectedProps.Count} total):",
                    EditorStyles.miniLabel);

                for (int i = 0; i < show; i++)
                {
                    var p = _detectedProps[i];
                    var typeColor = p.type == "color"  ? new Color(1f, 0.6f, 0.2f)
                                  : p.type == "float"  ? new Color(0.5f, 0.9f, 0.5f)
                                  :                      new Color(0.7f, 0.7f, 1.0f);

                    EditorGUILayout.BeginHorizontal();
                    var badge = new GUIStyle(EditorStyles.miniLabel);
                    badge.normal.textColor = typeColor;
                    GUILayout.Label($"[{p.type}]", badge, GUILayout.Width(52));
                    GUILayout.Label($"{p.name}", EditorStyles.miniLabel, GUILayout.Width(160));
                    GUILayout.Label($"= {p.currentValue}", EditorStyles.centeredGreyMiniLabel);
                    EditorGUILayout.EndHorizontal();
                }

                if (_detectedProps.Count > 6)
                {
                    if (GUILayout.Button(_showAllProps ? "▲ Show less" : $"▼ Show all {_detectedProps.Count}",
                        EditorStyles.miniButton, GUILayout.Width(120)))
                        _showAllProps = !_showAllProps;
                }
            }
            else if (_sourceMaterial != null)
            {
                EditorGUILayout.HelpBox("No animatable properties found on this material.", MessageType.Warning);
            }

            EditorGUILayout.EndVertical();

            EditorGUILayout.Space(8);

            // ── Animation Description ─────────────────────────────────────────
            DrawSectionLabel("✍️  Animation Description");
            EditorGUILayout.BeginVertical(EditorStyles.helpBox);
            EditorGUILayout.LabelField(
                "Describe the animation in natural language. Be specific about which properties to animate and how.",
                EditorStyles.wordWrappedMiniLabel);
            EditorGUILayout.Space(4);
            _animRequest = EditorGUILayout.TextArea(_animRequest, GUILayout.Height(80));

            // Hint examples
            EditorGUILayout.Space(4);
            GUILayout.Label("Examples:", EditorStyles.miniLabel);
            DrawExampleHint("\"pulse the size in and out rhythmically with a bounce ease\"");
            DrawExampleHint("\"slowly cycle the main color through a warm sunset palette\"");
            DrawExampleHint("\"flicker the outline width rapidly like a neon sign\"");
            DrawExampleHint("\"make the rotation spin continuously, size grows then snaps back\"");
            EditorGUILayout.EndVertical();

            EditorGUILayout.Space(8);

            // ── Options ───────────────────────────────────────────────────────
            DrawSectionLabel("⚙️  Options");
            EditorGUILayout.BeginVertical(EditorStyles.helpBox);
            _useKB = EditorGUILayout.Toggle(
                new GUIContent("Use Animation Library",
                    "Retrieve similar saved animations from the shape library as examples for the LLM."),
                _useKB);
            EditorGUILayout.EndVertical();

            EditorGUILayout.Space(12);

            // ── Generate Button ───────────────────────────────────────────────
            bool ready = _sourceMaterial != null
                      && _detectedProps.Count > 0
                      && !string.IsNullOrWhiteSpace(_animRequest);

            GUI.enabled = ready;
            var btnStyle = new GUIStyle(GUI.skin.button) { fontSize = 13, fontStyle = FontStyle.Bold };
            GUI.backgroundColor = ready ? new Color(0.4f, 0.8f, 0.4f) : Color.white;
            if (GUILayout.Button("🎬  Generate Animation Script", btnStyle, GUILayout.Height(48)))
            {
                _humanIteration = 1;
                _ = RunPipelineAsync();
            }
            GUI.backgroundColor = Color.white;
            GUI.enabled = true;

            if (!ready)
            {
                if (_sourceMaterial == null)
                    DrawWarning("Select a source material.");
                else if (_detectedProps.Count == 0)
                    DrawWarning("Material has no float/color/vector properties to animate.");
                else
                    DrawWarning("Enter an animation description.");
            }
        }

        private void DrawExampleHint(string text)
        {
            EditorGUILayout.BeginHorizontal();
            GUILayout.Label("  •", EditorStyles.miniLabel, GUILayout.Width(14));
            var linkStyle = new GUIStyle(EditorStyles.miniLabel);
            linkStyle.normal.textColor = new Color(0.4f, 0.7f, 1f);
            if (GUILayout.Button(text, linkStyle))
                _animRequest = text.Trim('"');
            EditorGUILayout.EndHorizontal();
        }

        // ═══════════════════════════════════════════════════════════════════════
        //  RUNNING / WAITING FOR COMPILE
        // ═══════════════════════════════════════════════════════════════════════

        private void DrawRunning()
        {
            EditorGUILayout.Space(20);
            GUILayout.Label("⏳  Generating Script…",
                new GUIStyle(EditorStyles.boldLabel) { fontSize = 13, alignment = TextAnchor.MiddleCenter });
            EditorGUILayout.Space(8);
            if (!string.IsNullOrEmpty(_statusMsg))
                EditorGUILayout.HelpBox(_statusMsg, MessageType.Info);
            GUILayout.Label("This may take 10–30 seconds.", EditorStyles.centeredGreyMiniLabel);
        }

        private void DrawWaitingCompile()
        {
            EditorGUILayout.Space(20);
            GUILayout.Label("⚙️  Unity is Compiling…",
                new GUIStyle(EditorStyles.boldLabel) { fontSize = 13, alignment = TextAnchor.MiddleCenter });
            EditorGUILayout.Space(8);
            EditorGUILayout.HelpBox(
                "The animation script has been saved. Unity is recompiling.\n" +
                "Once complete, a preview quad will appear in the Scene view.\n" +
                "Press Play to see the animation.",
                MessageType.Info);
            GUILayout.Label("Do not close this window.", EditorStyles.centeredGreyMiniLabel);
        }

        // ═══════════════════════════════════════════════════════════════════════
        //  REVIEW
        // ═══════════════════════════════════════════════════════════════════════

        private void DrawReview()
        {
            if (_result == null) return;

            // ── Result Summary ────────────────────────────────────────────────
            DrawSectionLabel("📋  Result");
            EditorGUILayout.BeginVertical(EditorStyles.helpBox);
            EditorGUILayout.LabelField($"Script:      {_result.fileName}.cs");
            EditorGUILayout.LabelField($"Material:    {_result.sourceMaterialName}");

            if (_result.matchedShape != null)
            {
                var matchStyle = new GUIStyle(EditorStyles.miniLabel);
                matchStyle.normal.textColor = new Color(0.3f, 0.9f, 0.3f);
                GUILayout.Label($"✓ Linked to KB shape: '{_result.matchedShape.fileName}' " +
                                $"({_result.matchedShape.animators.Count} existing animator(s))",
                                matchStyle);
            }
            else
            {
                var noMatchStyle = new GUIStyle(EditorStyles.miniLabel);
                noMatchStyle.normal.textColor = new Color(1f, 0.7f, 0.3f);
                GUILayout.Label("⚠  Material not found in KB — animation will be saved but not linked to a shape.",
                                noMatchStyle);
            }
            if (_result.propertiesUsed != null && _result.propertiesUsed.Count > 0)
                EditorGUILayout.LabelField($"Animates:    {string.Join(", ", _result.propertiesUsed)}");
            if (!string.IsNullOrEmpty(_result.animationSummary))
            {
                EditorGUILayout.Space(2);
                EditorGUILayout.LabelField("Summary:", EditorStyles.boldLabel);
                EditorGUILayout.LabelField(_result.animationSummary, EditorStyles.wordWrappedLabel);
            }
            EditorGUILayout.EndVertical();

            EditorGUILayout.Space(6);

            // ── Play hint ─────────────────────────────────────────────────────
            EditorGUILayout.HelpBox(
                "▶  Press Play in Unity to preview the animation on the quad in the Scene.\n" +
                "   Adjust the script's public fields in the Inspector to tweak timing/speed.",
                MessageType.Info);

            // ── Script Preview (collapsible) ──────────────────────────────────
            EditorGUILayout.Space(4);
            _showCode = EditorGUILayout.Foldout(_showCode, "📄 View Generated Script", true);
            if (_showCode && !string.IsNullOrEmpty(_result.csCode))
            {
                var codeStyle = new GUIStyle(EditorStyles.textArea) { font = EditorStyles.miniFont };
                GUILayout.TextArea(_result.csCode, codeStyle, GUILayout.Height(200));

                if (GUILayout.Button("📂 Open in Editor", GUILayout.Height(24)))
                {
                    var asset = AssetDatabase.LoadAssetAtPath<UnityEngine.Object>(_result.scriptAssetPath);
                    if (asset) AssetDatabase.OpenAsset(asset);
                }
            }

            // ── Tags ──────────────────────────────────────────────────────────
            if (_result.tags != null && _result.tags.Count > 0)
            {
                EditorGUILayout.Space(4);
                DrawSectionLabel("🏷️  Tags");
                EditorGUILayout.BeginHorizontal();
                foreach (var tag in _result.tags)
                {
                    var ts = new GUIStyle(EditorStyles.miniButton);
                    ts.normal.textColor = new Color(0.3f, 0.7f, 1f);
                    GUILayout.Label(tag, ts, GUILayout.ExpandWidth(false));
                }
                // Add tag
                _newTag = GUILayout.TextField(_newTag, GUILayout.Width(80));
                if (GUILayout.Button("+", GUILayout.Width(24)) && !string.IsNullOrWhiteSpace(_newTag))
                {
                    if (!_result.tags.Contains(_newTag.Trim()))
                        _result.tags.Add(_newTag.Trim());
                    _newTag = "";
                }
                EditorGUILayout.EndHorizontal();
            }

            EditorGUILayout.Space(10);

            // ── Human Rating ──────────────────────────────────────────────────
            DrawSectionLabel($"⭐  Your Rating   (attempt {_humanIteration}/{MAX_HUMAN_ITER})");
            EditorGUILayout.BeginVertical(EditorStyles.helpBox);
            EditorGUILayout.LabelField(
                $"Score < {ACCEPT_MIN} → retry.   Score ≥ {KB_THRESHOLD} → save to animation library.",
                EditorStyles.wordWrappedMiniLabel);
            EditorGUILayout.Space(4);

            EditorGUILayout.BeginHorizontal();
            GUILayout.Label("Score:", GUILayout.Width(48));
            _humanScore = Mathf.RoundToInt(GUILayout.HorizontalSlider(_humanScore, 0, 10, GUILayout.Width(320)));
            var badgeStyle = new GUIStyle(EditorStyles.boldLabel) { fontSize = 16 };
            badgeStyle.normal.textColor = _humanScore >= 8 ? new Color(0.2f, 0.8f, 0.2f)
                                        : _humanScore >= 6 ? new Color(1f, 0.7f, 0.1f)
                                        : new Color(0.9f, 0.2f, 0.2f);
            GUILayout.Label(_humanScore.ToString(), badgeStyle, GUILayout.Width(28));
            EditorGUILayout.EndHorizontal();

            EditorGUILayout.Space(4);
            GUILayout.Label("Feedback for retry (optional):");
            _humanComment = EditorGUILayout.TextField(_humanComment);
            EditorGUILayout.EndVertical();

            EditorGUILayout.Space(8);

            // ── Action Buttons ────────────────────────────────────────────────
            EditorGUILayout.BeginHorizontal();

            bool canAccept = _humanScore >= ACCEPT_MIN;
            GUI.enabled = canAccept;
            GUI.backgroundColor = canAccept ? new Color(0.3f, 0.9f, 0.3f) : Color.white;
            if (GUILayout.Button($"✅  Accept  ({_humanScore}/10)", GUILayout.Height(36)))
                _ = HandleAcceptAsync();
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
                HandleDiscard();
            GUI.backgroundColor = Color.white;

            EditorGUILayout.EndHorizontal();

            if (!canAccept)
                DrawWarning($"Raise score to at least {ACCEPT_MIN} to accept.");
            if (!canRetry)
                DrawWarning("Maximum retries reached — accept or discard.");
        }

        // ═══════════════════════════════════════════════════════════════════════
        //  DONE
        // ═══════════════════════════════════════════════════════════════════════

        private void DrawDone()
        {
            EditorGUILayout.Space(16);
            GUILayout.Label("✓  Done",
                new GUIStyle(EditorStyles.boldLabel) { fontSize = 13, alignment = TextAnchor.MiddleCenter });
            EditorGUILayout.Space(8);
            EditorGUILayout.TextArea(_outcomeMsg, EditorStyles.wordWrappedLabel, GUILayout.Height(80));

            if (_result?.scriptAssetPath != null)
            {
                EditorGUILayout.Space(4);
                if (GUILayout.Button("📂  Open Script", GUILayout.Height(28)))
                {
                    var asset = AssetDatabase.LoadAssetAtPath<UnityEngine.Object>(_result.scriptAssetPath);
                    if (asset) AssetDatabase.OpenAsset(asset);
                }
            }

            EditorGUILayout.Space(10);
            if (GUILayout.Button("🔁  Animate Another Material", GUILayout.Height(36)))
                ResetToIdle();
        }

        // ═══════════════════════════════════════════════════════════════════════
        //  PIPELINE EXECUTION
        // ═══════════════════════════════════════════════════════════════════════

        private async Task RunPipelineAsync(string feedback = null)
        {
            _state    = State.Running;
            _showCode = false;
            Repaint();

            _result = await MaterialAnimatorPipelineManager.RunPipelineAsync(
                _sourceMaterial,
                _animRequest,
                _config,
                _kb,
                _useKB,
                feedback,
                msg => { _statusMsg = msg; Repaint(); });

            if (_result == null || !_result.success)
            {
                EditorUtility.DisplayDialog("Error",
                    _result?.errorMessage ?? "Pipeline failed.", "OK");
                _state = State.Idle;
                Repaint();
                return;
            }

            // Script saved — now waiting for Unity to compile it
            _state     = State.WaitingForCompile;
            _statusMsg = $"Script saved: {_result.scriptAssetPath}\nWaiting for compilation…";
            Repaint();
            // ResumeAfterReload() will flip state to AwaitingReview via PollResumeNotification
        }

        private async Task RetryAsync()
        {
            _humanIteration++;
            string fb = _humanComment;
            _humanComment = "";
            await RunPipelineAsync(fb);
        }

        private async Task HandleAcceptAsync()
        {
            bool saveToKB = _humanScore >= KB_THRESHOLD;

            if (saveToKB)
            {
                _state     = State.Running;
                _statusMsg = "Saving animation to knowledge base…";
                Repaint();

                var entry = new AnimatorEntry
                {
                    id                   = Guid.NewGuid().ToString("N").Substring(0, 8),
                    fileName             = _result.fileName,
                    scriptPath           = _result.scriptAssetPath,
                    animationDescription = _result.animationRequest,
                    animationSummary     = _result.animationSummary ?? "",
                    propertiesUsed       = _result.propertiesUsed ?? new List<string>(),
                    tags                 = _result.tags ?? new List<string>(),
                    sourceMaterialName   = _result.sourceMaterialName,
                    dateAdded            = DateTime.Now.ToString("yyyy-MM-dd"),
                    humanScore           = _humanScore
                };

                if (_result.matchedShape != null)
                {
                    // Material IS in KB — link the animator directly to its shape
                    await AnimationKBHelper.SaveAnimatorToShapeAsync(
                        entry, _result.matchedShape, _kb, _config.openAIKey);

                    int totalAnims = 0;
                    foreach (var s in _kb.shapes) totalAnims += s.animators.Count;

                    _outcomeMsg = $"✓ '{_result.fileName}' accepted and saved to shape '{_result.matchedShape.fileName}'!\n" +
                                  $"   That shape now has {_result.matchedShape.animators.Count} animator(s).\n" +
                                  $"   Your score: {_humanScore}/10\n" +
                                  $"   Total animations across library: {totalAnims}\n\n" +
                                  $"   Script: {_result.scriptAssetPath}";
                }
                else
                {
                    // Material NOT in KB — still save animation but with no shape link
                    // Find or create an "unlinked" placeholder shape
                    var unlinked = _kb.shapes.Find(s => s.fileName == "__unlinked_animations__");
                    if (unlinked == null)
                    {
                        unlinked = new ShapeMetadata
                        {
                            id       = "__unlinked__",
                            fileName = "__unlinked_animations__",
                            originalPrompt   = "Animations not linked to a specific shape",
                            visualDescription = "Unlinked animations"
                        };
                        _kb.shapes.Add(unlinked);
                    }
                    await AnimationKBHelper.SaveAnimatorToShapeAsync(
                        entry, unlinked, _kb, _config.openAIKey);

                    _outcomeMsg = $"✓ '{_result.fileName}' accepted.\n" +
                                  $"   ⚠  Material not in KB — saved to unlinked pool.\n" +
                                  $"   Your score: {_humanScore}/10\n\n" +
                                  $"   Script: {_result.scriptAssetPath}";
                }
            }
            else
            {
                _outcomeMsg = $"✓ '{_result.fileName}' accepted (score {_humanScore}/10).\n" +
                              $"   Not saved to library (score below {KB_THRESHOLD}).\n\n" +
                              $"   Script: {_result.scriptAssetPath}";
            }

            _state = State.Done;
            Repaint();
        }

        private void HandleDiscard()
        {
            // Delete the generated script if user discards
            if (_result?.scriptAssetPath != null && File.Exists(_result.scriptAssetPath))
            {
                bool del = EditorUtility.DisplayDialog("Discard Animation",
                    $"Delete the generated script?\n{_result.scriptAssetPath}", "Delete", "Keep");
                if (del)
                {
                    AssetDatabase.DeleteAsset(_result.scriptAssetPath);
                    AssetDatabase.Refresh();
                }
            }
            ResetToIdle();
        }

        private void ResetToIdle()
        {
            _state         = State.Idle;
            _result        = null;
            _statusMsg     = "";
            _outcomeMsg    = "";
            _humanScore    = 8;
            _humanComment  = "";
            _humanIteration = 1;
            _showCode      = false;
            _newTag        = "";
            Repaint();
        }

        // ─── UI Helpers ───────────────────────────────────────────────────────

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