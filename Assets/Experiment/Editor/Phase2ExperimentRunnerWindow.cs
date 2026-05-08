// Phase2ExperimentRunnerWindow.cs
// Developer-only Unity EditorWindow for Master Thesis statistical evaluation.
// Access via:  Tools > Thesis Experiment (Dev) > Phase 2 Experiment Runner
//
// Three experiment tabs:
//   1. Generation  — RAG vs No-RAG pipeline comparison on batches of shapes
//   2. Edit        — Edit-pipeline quality evaluation (Phase 2 only)
//   3. Animation   — Animation-pipeline quality evaluation (Phase 2 only)
//
// All results are saved as JSON files in Assets/Experiment/Results/.
// A Python visualization script (Assets/Experiment/Visualization/visualize_results.py)
// reads those files and produces charts for the thesis.

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using Newtonsoft.Json;
using UnityEditor;
using UnityEngine;
using UnityEngine.Networking;

using ShaderGraphGenerator.Editor;
using ShaderGraphGenerator.KnowledgeBase;
using ShaderGraphGenerator.RAG;

namespace ShaderGraphExperiments.Editor
{
    public class Phase2ExperimentRunnerWindow : EditorWindow
    {
        // ── Menu registration ──────────────────────────────────────────────────
        [MenuItem("Tools/Thesis Experiment (Dev)/Phase 2 Experiment Runner")]
        public static void ShowWindow()
        {
            var win = GetWindow<Phase2ExperimentRunnerWindow>("Phase 2 Experiment");
            win.minSize = new Vector2(620, 600);
        }

        // ── Shared state ───────────────────────────────────────────────────────
        private int    _tab              = 0;
        private bool   _isRunning        = false;
        private Vector2 _scroll;
        private string _statusLog        = "";

        private ShaderGraphGeneratorConfig _config;
        private ShapeKnowledgeBase         _knowledgeBase;

        private const string RESULTS_FOLDER = "Assets/Experiment/Results";

        // ── Human-scoring panel (shared across tabs) ───────────────────────────
        private Texture2D _pendingPreview;
        private string    _pendingPrompt;
        private TaskCompletionSource<int> _humanScoreTcs;
        private int       _humanScoreSlider = 7;

        // ═══════════════════════════════════════════════
        //  TAB 1  –  GENERATION
        // ═══════════════════════════════════════════════
        private string  _gen_shapesFile    = "Assets/Experiment/ShapeSets/Shapes_Simple_InRAG.txt";
        private bool    _gen_runRAG        = true;
        private bool    _gen_runNoRAG      = true;
        private string  _gen_codeProvider  = "gemini-3-pro-preview";
        private string  _gen_evalProvider  = "gemini-3-pro-preview";
        private int     _gen_maxIter       = 3;
        private int     _gen_threshold     = 7;
        private bool    _gen_humanScore    = false;
        private bool    _gen_markInRAG     = false;   // manual flag: shapes in this file are in KB

        private GenerationExperimentRun _gen_currentRun;

        // ═══════════════════════════════════════════════
        //  TAB 2  –  EDIT
        // ═══════════════════════════════════════════════
        private string  _edit_configFile   = "Assets/Experiment/ShapeSets/EditRequests.json";
        private bool    _edit_humanScore   = false;
        private EditExperimentRun _edit_currentRun;

        // ═══════════════════════════════════════════════
        //  TAB 3  –  ANIMATION
        // ═══════════════════════════════════════════════
        private string  _anim_configFile   = "Assets/Experiment/ShapeSets/AnimationRequests.json";
        private bool    _anim_humanScore   = false;
        private AnimationExperimentRun _anim_currentRun;

        // ═══════════════════════════════════════════════
        //  TAB 4  –  IMAGE → SHADER
        // ═══════════════════════════════════════════════
        private string  _img_configFile   = "Assets/Experiment/ShapeSets/ImageRequests.json";
        private bool    _img_humanScore   = false;
        private int     _img_maxIter      = 2;
        private ImageExperimentRun _img_currentRun;

        // ═══════════════════════════════════════════════
        //  TAB 5  –  RESULTS OVERVIEW
        // ═══════════════════════════════════════════════
        private List<string>  _loaded_files        = new List<string>();
        private string        _loaded_summary       = "";
        private Vector2       _loaded_scroll;

        // ── Styles ─────────────────────────────────────────────────────────────
        private GUIStyle _headerStyle;
        private GUIStyle _sectionStyle;
        private GUIStyle _logStyle;
        private bool     _stylesInit = false;

        // ══════════════════════════════════════════════════════════════════════
        //  LIFECYCLE
        // ══════════════════════════════════════════════════════════════════════

        private void OnEnable()
        {
            _config = AssetDatabase.LoadAssetAtPath<ShaderGraphGeneratorConfig>(
                "Assets/ShaderGraphGeneratorConfig.asset");
            TryLoadKnowledgeBase();
        }

        private const string KB_PATH = "Assets/ShaderGraphGenerator/KnowledgeBase/shape_metadata.json";

        private void TryLoadKnowledgeBase()
        {
            if (!File.Exists(KB_PATH)) return;
            string json = File.ReadAllText(KB_PATH);
            _knowledgeBase = JsonConvert.DeserializeObject<ShapeKnowledgeBase>(json);
        }

        private void InitStyles()
        {
            if (_stylesInit) return;
            _headerStyle = new GUIStyle(EditorStyles.boldLabel) { fontSize = 14 };
            _sectionStyle = new GUIStyle(EditorStyles.boldLabel) { fontSize = 11 };
            _logStyle = new GUIStyle(EditorStyles.textArea)
            {
                wordWrap = true, fontSize = 10,
                normal = { textColor = new Color(0.2f, 0.9f, 0.3f) }
            };
            _stylesInit = true;
        }

        // ══════════════════════════════════════════════════════════════════════
        //  MAIN GUI
        // ══════════════════════════════════════════════════════════════════════

        private void OnGUI()
        {
            InitStyles();

            // ── header ──
            EditorGUILayout.Space(4);
            EditorGUILayout.LabelField("Phase 2 — Thesis Experiment Runner", _headerStyle);
            EditorGUILayout.LabelField(
                "Developer-only tool. Evaluates RAG pipeline for statistical data.",
                EditorStyles.miniLabel);
            EditorGUILayout.Space(6);

            // ── config check ──
            if (_config == null)
            {
                EditorGUILayout.HelpBox(
                    "Config not found at Assets/ShaderGraphGeneratorConfig.asset",
                    MessageType.Error);
            }
            if (_knowledgeBase == null)
            {
                EditorGUILayout.HelpBox(
                    "No ShapeKnowledgeBase asset found. RAG features require a loaded KB.",
                    MessageType.Warning);
                if (GUILayout.Button("Retry Load KB", GUILayout.Width(140)))
                    TryLoadKnowledgeBase();
            }

            EditorGUILayout.Space(4);

            // ── tabs ──
            _tab = GUILayout.Toolbar(_tab, new[] { "Generation", "Edit", "Animation", "Image→Shader", "Results" });
            EditorGUILayout.Space(6);

            _scroll = EditorGUILayout.BeginScrollView(_scroll);

            switch (_tab)
            {
                case 0: DrawGenerationTab();   break;
                case 1: DrawEditTab();         break;
                case 2: DrawAnimationTab();    break;
                case 3: DrawImageTab();        break;
                case 4: DrawResultsTab();      break;
            }

            EditorGUILayout.EndScrollView();

            // ── Human scoring overlay (visible on any tab) ──
            if (_humanScoreTcs != null)
                DrawHumanScoringPanel();
        }

        // ══════════════════════════════════════════════════════════════════════
        //  TAB 1  –  GENERATION
        // ══════════════════════════════════════════════════════════════════════

        private void DrawGenerationTab()
        {
            EditorGUILayout.LabelField("Generation Experiment", _sectionStyle);
            EditorGUILayout.HelpBox(
                "Runs shape generation on a text file of prompts.\n" +
                "Enable BOTH RAG and No-RAG to produce Phase 1 vs Phase 2 comparison data.\n" +
                "Results are saved in " + RESULTS_FOLDER,
                MessageType.Info);

            EditorGUILayout.Space(8);

            // ── Input ──
            EditorGUILayout.LabelField("Input", EditorStyles.boldLabel);
            _gen_shapesFile = EditorGUILayout.TextField("Shape Prompts File (.txt)", _gen_shapesFile);
            if (GUILayout.Button("Browse...", GUILayout.Width(90)))
            {
                string p = EditorUtility.OpenFilePanel("Select Shapes TXT", "Assets/Experiment/ShapeSets", "txt");
                if (!string.IsNullOrEmpty(p))
                    _gen_shapesFile = p.Replace(Application.dataPath, "Assets").Replace("\\", "/");
            }

            EditorGUILayout.Space(6);

            // ── Pipeline selection ──
            EditorGUILayout.LabelField("Pipelines to Run", EditorStyles.boldLabel);
            _gen_runRAG    = EditorGUILayout.ToggleLeft("RAG Pipeline  (Phase 2)", _gen_runRAG);
            _gen_runNoRAG  = EditorGUILayout.ToggleLeft("No-RAG Pipeline  (Phase 1 equivalent — direct LLM, no retrieval)", _gen_runNoRAG);
            _gen_markInRAG = EditorGUILayout.ToggleLeft(
                "Mark shapes in this file as 'in knowledge base'  (for In-KB vs Out-KB analysis)",
                _gen_markInRAG);

            EditorGUILayout.Space(6);

            // ── Providers ──
            EditorGUILayout.LabelField("Providers", EditorStyles.boldLabel);
            _gen_codeProvider  = DrawProviderField("Code LLM (generation)", _gen_codeProvider);
            _gen_evalProvider  = DrawProviderField("Eval VLM (scoring)",    _gen_evalProvider);

            EditorGUILayout.Space(6);

            // ── Settings ──
            EditorGUILayout.LabelField("Settings", EditorStyles.boldLabel);
            _gen_maxIter   = EditorGUILayout.IntSlider("Max Iterations per Shape", _gen_maxIter, 1, 6);
            _gen_threshold = EditorGUILayout.IntSlider("Success Threshold (VLM score ≥)", _gen_threshold, 5, 10);
            _gen_humanScore = EditorGUILayout.ToggleLeft("Collect Human Score after each shape", _gen_humanScore);

            EditorGUILayout.Space(10);

            // ── Run button ──
            EditorGUI.BeginDisabledGroup(_isRunning || _config == null);
            if (GUILayout.Button(_isRunning ? "Running..." : "Start Generation Experiment",
                GUILayout.Height(32)))
            {
                _ = RunGenerationExperimentAsync();
            }
            EditorGUI.EndDisabledGroup();

            if (_isRunning && GUILayout.Button("Abort (saves partial results)", GUILayout.Height(26)))
                _isRunning = false;

            // ── Live status log ──
            EditorGUILayout.Space(8);
            EditorGUILayout.LabelField("Status Log", EditorStyles.boldLabel);
            EditorGUILayout.TextArea(_statusLog, _logStyle, GUILayout.MinHeight(120));

            // ── Partial results table ──
            if (_gen_currentRun?.shapes?.Count > 0)
            {
                EditorGUILayout.Space(6);
                EditorGUILayout.LabelField(
                    $"Results so far: {_gen_currentRun.shapes.Count} shapes  " +
                    $"(success: {_gen_currentRun.shapes.Count(s => s.success)}/{_gen_currentRun.shapes.Count})",
                    EditorStyles.boldLabel);

                DrawGenerationResultTable(_gen_currentRun.shapes, showLast: 8);
            }
        }

        private void DrawGenerationResultTable(List<GenerationShapeResult> shapes, int showLast)
        {
            var recent = shapes.Skip(Mathf.Max(0, shapes.Count - showLast)).ToList();
            EditorGUILayout.BeginHorizontal(EditorStyles.toolbar);
            GUILayout.Label("Prompt",      GUILayout.Width(180));
            GUILayout.Label("Category",    GUILayout.Width(60));
            GUILayout.Label("InKB",        GUILayout.Width(36));
            GUILayout.Label("OK?",         GUILayout.Width(32));
            GUILayout.Label("Iters",       GUILayout.Width(36));
            GUILayout.Label("VLM",         GUILayout.Width(36));
            GUILayout.Label("Human",       GUILayout.Width(46));
            GUILayout.Label("Time(s)",     GUILayout.Width(55));
            EditorGUILayout.EndHorizontal();

            foreach (var s in recent)
            {
                EditorGUILayout.BeginHorizontal(EditorStyles.helpBox);
                GUILayout.Label(Truncate(s.prompt, 28),  GUILayout.Width(180));
                GUILayout.Label(s.shape_complexity ?? "?", GUILayout.Width(60));
                GUILayout.Label(s.in_knowledge_base ? "Y" : "N", GUILayout.Width(36));
                GUILayout.Label(s.success ? "✓" : "✗",   GUILayout.Width(32));
                GUILayout.Label(s.iterations_used.ToString(), GUILayout.Width(36));
                GUILayout.Label(s.final_vlm_score.ToString(), GUILayout.Width(36));
                GUILayout.Label(s.human_score > 0 ? s.human_score.ToString() : "-", GUILayout.Width(46));
                GUILayout.Label($"{s.total_time_ms / 1000.0:F1}", GUILayout.Width(55));
                EditorGUILayout.EndHorizontal();
            }
        }

        // ══════════════════════════════════════════════════════════════════════
        //  TAB 2  –  EDIT
        // ══════════════════════════════════════════════════════════════════════

        private void DrawEditTab()
        {
            EditorGUILayout.LabelField("Edit Experiment  (Phase 2 only)", _sectionStyle);
            EditorGUILayout.HelpBox(
                "Generates a shape, then applies an edit request.\n" +
                "Measures: edit type classification, VLM score before/after, time.\n" +
                "Config file format: JSON array of {shape_prompt, edit_request} objects.",
                MessageType.Info);

            EditorGUILayout.Space(8);

            _edit_configFile = EditorGUILayout.TextField("Edit Config File (.json)", _edit_configFile);
            if (GUILayout.Button("Browse...", GUILayout.Width(90)))
            {
                string p = EditorUtility.OpenFilePanel("Select Edit Config JSON", "Assets/Experiment/ShapeSets", "json");
                if (!string.IsNullOrEmpty(p))
                    _edit_configFile = p.Replace(Application.dataPath, "Assets").Replace("\\", "/");
            }

            EditorGUILayout.Space(4);
            _edit_humanScore = EditorGUILayout.ToggleLeft("Collect Human Score after each edit", _edit_humanScore);
            EditorGUILayout.Space(10);

            EditorGUI.BeginDisabledGroup(_isRunning || _config == null || _knowledgeBase == null);
            if (GUILayout.Button(_isRunning ? "Running..." : "Start Edit Experiment",
                GUILayout.Height(32)))
            {
                _ = RunEditExperimentAsync();
            }
            EditorGUI.EndDisabledGroup();

            if (_isRunning && GUILayout.Button("Abort", GUILayout.Width(80)))
                _isRunning = false;

            EditorGUILayout.Space(8);
            EditorGUILayout.LabelField("Status Log", EditorStyles.boldLabel);
            EditorGUILayout.TextArea(_statusLog, _logStyle, GUILayout.MinHeight(100));

            if (_edit_currentRun?.items?.Count > 0)
            {
                EditorGUILayout.Space(6);
                EditorGUILayout.LabelField(
                    $"Edits so far: {_edit_currentRun.items.Count}  " +
                    $"(success: {_edit_currentRun.items.Count(e => e.success)}/{_edit_currentRun.items.Count})",
                    EditorStyles.boldLabel);

                DrawEditResultTable(_edit_currentRun.items, showLast: 6);
            }
        }

        private void DrawEditResultTable(List<EditExperimentItem> items, int showLast)
        {
            var recent = items.Skip(Mathf.Max(0, items.Count - showLast)).ToList();
            EditorGUILayout.BeginHorizontal(EditorStyles.toolbar);
            GUILayout.Label("Shape",        GUILayout.Width(130));
            GUILayout.Label("Edit Request", GUILayout.Width(160));
            GUILayout.Label("Type",         GUILayout.Width(80));
            GUILayout.Label("OK?",          GUILayout.Width(32));
            GUILayout.Label("Before",       GUILayout.Width(46));
            GUILayout.Label("After",        GUILayout.Width(40));
            GUILayout.Label("Δ",            GUILayout.Width(30));
            GUILayout.Label("Time(s)",      GUILayout.Width(52));
            EditorGUILayout.EndHorizontal();

            foreach (var e in recent)
            {
                EditorGUILayout.BeginHorizontal(EditorStyles.helpBox);
                GUILayout.Label(Truncate(e.base_shape_prompt, 18), GUILayout.Width(130));
                GUILayout.Label(Truncate(e.edit_request,      22), GUILayout.Width(160));
                GUILayout.Label(e.edit_type ?? "?",               GUILayout.Width(80));
                GUILayout.Label(e.success ? "✓" : "✗",            GUILayout.Width(32));
                GUILayout.Label(e.vlm_score_before.ToString(),    GUILayout.Width(46));
                GUILayout.Label(e.vlm_score_after.ToString(),     GUILayout.Width(40));
                GUILayout.Label(e.score_improvement >= 0 ? $"+{e.score_improvement}" : e.score_improvement.ToString(), GUILayout.Width(30));
                GUILayout.Label($"{e.total_time_ms / 1000.0:F1}", GUILayout.Width(52));
                EditorGUILayout.EndHorizontal();
            }
        }

        // ══════════════════════════════════════════════════════════════════════
        //  TAB 3  –  ANIMATION
        // ══════════════════════════════════════════════════════════════════════

        private void DrawAnimationTab()
        {
            EditorGUILayout.LabelField("Animation Experiment  (Phase 2 only)", _sectionStyle);
            EditorGUILayout.HelpBox(
                "Generates a shape, then requests an animation script for it.\n" +
                "Measures: success rate, generation time, human score.\n" +
                "Config file format: JSON array of {shape_prompt, animation_request} objects.",
                MessageType.Info);

            EditorGUILayout.Space(8);

            _anim_configFile = EditorGUILayout.TextField("Animation Config File (.json)", _anim_configFile);
            if (GUILayout.Button("Browse...", GUILayout.Width(90)))
            {
                string p = EditorUtility.OpenFilePanel("Select Anim Config JSON", "Assets/Experiment/ShapeSets", "json");
                if (!string.IsNullOrEmpty(p))
                    _anim_configFile = p.Replace(Application.dataPath, "Assets").Replace("\\", "/");
            }

            EditorGUILayout.Space(4);
            _anim_humanScore = EditorGUILayout.ToggleLeft("Collect Human Score after each animation", _anim_humanScore);
            EditorGUILayout.Space(10);

            EditorGUI.BeginDisabledGroup(_isRunning || _config == null || _knowledgeBase == null);
            if (GUILayout.Button(_isRunning ? "Running..." : "Start Animation Experiment",
                GUILayout.Height(32)))
            {
                _ = RunAnimationExperimentAsync();
            }
            EditorGUI.EndDisabledGroup();

            if (_isRunning && GUILayout.Button("Abort", GUILayout.Width(80)))
                _isRunning = false;

            EditorGUILayout.Space(8);
            EditorGUILayout.LabelField("Status Log", EditorStyles.boldLabel);
            EditorGUILayout.TextArea(_statusLog, _logStyle, GUILayout.MinHeight(100));

            if (_anim_currentRun?.items?.Count > 0)
            {
                EditorGUILayout.Space(6);
                EditorGUILayout.LabelField(
                    $"Animations so far: {_anim_currentRun.items.Count}  " +
                    $"(success: {_anim_currentRun.items.Count(a => a.success)}/{_anim_currentRun.items.Count})",
                    EditorStyles.boldLabel);

                DrawAnimationResultTable(_anim_currentRun.items, showLast: 6);
            }
        }

        private void DrawAnimationResultTable(List<AnimationExperimentItem> items, int showLast)
        {
            var recent = items.Skip(Mathf.Max(0, items.Count - showLast)).ToList();
            EditorGUILayout.BeginHorizontal(EditorStyles.toolbar);
            GUILayout.Label("Shape",            GUILayout.Width(160));
            GUILayout.Label("Animation Request", GUILayout.Width(200));
            GUILayout.Label("OK?",              GUILayout.Width(32));
            GUILayout.Label("Human",            GUILayout.Width(46));
            GUILayout.Label("Time(s)",          GUILayout.Width(55));
            EditorGUILayout.EndHorizontal();

            foreach (var a in recent)
            {
                EditorGUILayout.BeginHorizontal(EditorStyles.helpBox);
                GUILayout.Label(Truncate(a.base_shape_prompt, 24), GUILayout.Width(160));
                GUILayout.Label(Truncate(a.animation_request, 28), GUILayout.Width(200));
                GUILayout.Label(a.success ? "✓" : "✗",            GUILayout.Width(32));
                GUILayout.Label(a.human_score > 0 ? a.human_score.ToString() : "-", GUILayout.Width(46));
                GUILayout.Label($"{a.total_time_ms / 1000.0:F1}", GUILayout.Width(55));
                EditorGUILayout.EndHorizontal();
            }
        }

        // ══════════════════════════════════════════════════════════════════════
        //  TAB 4  –  IMAGE → SHADER
        // ══════════════════════════════════════════════════════════════════════

        private void DrawImageTab()
        {
            EditorGUILayout.LabelField("Image → Shader Experiment", _sectionStyle);
            EditorGUILayout.HelpBox(
                "Generates a shader from a reference image using GPT-4o Vision + RAG.\n" +
                "Config file: JSON array of {image_path, editable_hints} objects.\n" +
                "Place reference images in Assets/Experiment/ReferenceImages/.\n" +
                "Results are saved in " + RESULTS_FOLDER,
                MessageType.Info);

            EditorGUILayout.Space(8);

            _img_configFile = EditorGUILayout.TextField("Image Config File (.json)", _img_configFile);
            if (GUILayout.Button("Browse...", GUILayout.Width(90)))
            {
                string p = EditorUtility.OpenFilePanel("Select Image Config JSON", "Assets/Experiment/ShapeSets", "json");
                if (!string.IsNullOrEmpty(p))
                    _img_configFile = p.Replace(Application.dataPath, "Assets").Replace("\\", "/");
            }

            EditorGUILayout.Space(4);
            _img_maxIter   = EditorGUILayout.IntSlider("Max VLM Iterations", _img_maxIter, 1, 4);
            _img_humanScore = EditorGUILayout.ToggleLeft("Collect Human Score after each image", _img_humanScore);
            EditorGUILayout.Space(10);

            EditorGUI.BeginDisabledGroup(_isRunning || _config == null || _knowledgeBase == null);
            if (GUILayout.Button(_isRunning ? "Running..." : "Start Image→Shader Experiment",
                GUILayout.Height(32)))
            {
                _ = RunImageExperimentAsync();
            }
            EditorGUI.EndDisabledGroup();

            if (_isRunning && GUILayout.Button("Abort", GUILayout.Width(80)))
                _isRunning = false;

            EditorGUILayout.Space(8);
            EditorGUILayout.LabelField("Status Log", EditorStyles.boldLabel);
            EditorGUILayout.TextArea(_statusLog, _logStyle, GUILayout.MinHeight(100));

            if (_img_currentRun?.items?.Count > 0)
            {
                EditorGUILayout.Space(6);
                EditorGUILayout.LabelField(
                    $"Images so far: {_img_currentRun.items.Count}  " +
                    $"(success: {_img_currentRun.items.Count(i => i.success)}/{_img_currentRun.items.Count})",
                    EditorStyles.boldLabel);

                DrawImageResultTable(_img_currentRun.items, showLast: 6);
            }
        }

        private void DrawImageResultTable(List<ImageExperimentItem> items, int showLast)
        {
            var recent = items.Skip(Mathf.Max(0, items.Count - showLast)).ToList();
            EditorGUILayout.BeginHorizontal(EditorStyles.toolbar);
            GUILayout.Label("Image",      GUILayout.Width(160));
            GUILayout.Label("Hints",      GUILayout.Width(160));
            GUILayout.Label("OK?",        GUILayout.Width(32));
            GUILayout.Label("VLM",        GUILayout.Width(36));
            GUILayout.Label("Human",      GUILayout.Width(46));
            GUILayout.Label("Time(s)",    GUILayout.Width(55));
            EditorGUILayout.EndHorizontal();

            foreach (var item in recent)
            {
                EditorGUILayout.BeginHorizontal(EditorStyles.helpBox);
                GUILayout.Label(Truncate(Path.GetFileName(item.image_path), 22),  GUILayout.Width(160));
                GUILayout.Label(Truncate(item.editable_hints, 22),                GUILayout.Width(160));
                GUILayout.Label(item.success ? "✓" : "✗",                        GUILayout.Width(32));
                GUILayout.Label(item.vlm_score.ToString(),                        GUILayout.Width(36));
                GUILayout.Label(item.human_score > 0 ? item.human_score.ToString() : "-", GUILayout.Width(46));
                GUILayout.Label($"{item.total_time_ms / 1000.0:F1}",             GUILayout.Width(55));
                EditorGUILayout.EndHorizontal();
            }
        }

        // ══════════════════════════════════════════════════════════════════════
        //  TAB 5  –  RESULTS OVERVIEW
        // ══════════════════════════════════════════════════════════════════════

        private void DrawResultsTab()
        {
            EditorGUILayout.LabelField("Results Overview & Visualization", _sectionStyle);
            EditorGUILayout.Space(6);

            if (GUILayout.Button("Reload Results from Disk", GUILayout.Height(28)))
                LoadResultsSummary();

            EditorGUILayout.Space(6);

            if (_loaded_files.Count == 0)
            {
                EditorGUILayout.HelpBox("No result JSON files found in " + RESULTS_FOLDER +
                    ". Run experiments first.", MessageType.Info);
            }
            else
            {
                EditorGUILayout.LabelField($"{_loaded_files.Count} result file(s) found:", EditorStyles.boldLabel);
                _loaded_scroll = EditorGUILayout.BeginScrollView(_loaded_scroll, GUILayout.MaxHeight(120));
                foreach (var f in _loaded_files)
                    EditorGUILayout.LabelField("  • " + Path.GetFileName(f), EditorStyles.miniLabel);
                EditorGUILayout.EndScrollView();

                if (!string.IsNullOrEmpty(_loaded_summary))
                {
                    EditorGUILayout.Space(4);
                    EditorGUILayout.LabelField("Quick Summary", EditorStyles.boldLabel);
                    EditorGUILayout.TextArea(_loaded_summary, EditorStyles.textArea, GUILayout.MinHeight(100));
                }
            }

            EditorGUILayout.Space(10);
            EditorGUILayout.LabelField("Visualization", EditorStyles.boldLabel);
            EditorGUILayout.HelpBox(
                "Run the Python script to generate all charts:\n" +
                "  python Assets/Experiment/Visualization/visualize_results.py\n\n" +
                "Charts are saved to Assets/Experiment/Visualization/Charts/\n" +
                "Requires: matplotlib, seaborn, pandas, scipy  (see requirements.txt)",
                MessageType.Info);

            if (GUILayout.Button("Open Visualization Folder", GUILayout.Height(28)))
                EditorUtility.RevealInFinder("Assets/Experiment/Visualization");

            if (GUILayout.Button("Open Results Folder", GUILayout.Height(28)))
                EditorUtility.RevealInFinder(RESULTS_FOLDER);

            EditorGUILayout.Space(6);
            if (GUILayout.Button("Run Python Visualizer (auto-detect Python)", GUILayout.Height(32)))
                LaunchPythonVisualizer();

            EditorGUILayout.Space(10);
            EditorGUILayout.LabelField("Data Management", EditorStyles.boldLabel);
            if (GUILayout.Button("Open Results Folder in Explorer", GUILayout.Width(240)))
                System.Diagnostics.Process.Start("explorer.exe",
                    Path.GetFullPath(RESULTS_FOLDER).Replace("/", "\\"));

            EditorGUI.BeginDisabledGroup(true);
            EditorGUILayout.HelpBox(
                "Warning: The button below deletes ALL experiment result files.",
                MessageType.Warning);
            EditorGUI.EndDisabledGroup();

            EditorGUI.BeginDisabledGroup(_isRunning);
            using (new GUILayout.HorizontalScope())
            {
                GUILayout.FlexibleSpace();
                var oldColor = GUI.backgroundColor;
                GUI.backgroundColor = new Color(0.9f, 0.3f, 0.3f);
                if (GUILayout.Button("Clear All Results", GUILayout.Width(140)))
                {
                    if (EditorUtility.DisplayDialog("Clear Results",
                        "Delete all JSON files in Assets/Experiment/Results/?",
                        "Delete", "Cancel"))
                    {
                        foreach (var f in Directory.GetFiles(RESULTS_FOLDER, "*.json"))
                            File.Delete(f);
                        AssetDatabase.Refresh();
                        _loaded_files.Clear();
                        _loaded_summary = "";
                    }
                }
                GUI.backgroundColor = oldColor;
            }
            EditorGUI.EndDisabledGroup();
        }

        // ══════════════════════════════════════════════════════════════════════
        //  HUMAN SCORING PANEL  (overlay shown on top of any tab)
        // ══════════════════════════════════════════════════════════════════════

        private void DrawHumanScoringPanel()
        {
            EditorGUILayout.Space(12);

            var boxStyle = new GUIStyle(EditorStyles.helpBox);
            EditorGUILayout.BeginVertical(boxStyle);

            EditorGUILayout.LabelField("Human Score Required", new GUIStyle(EditorStyles.boldLabel)
                { normal = { textColor = new Color(1f, 0.85f, 0.1f) }, fontSize = 12 });
            EditorGUILayout.HelpBox(
                "Adjust material values in the Inspector if needed, then submit your score.\n" +
                "If score ≥ threshold: a fresh screenshot is taken and sent to VLM.\n" +
                "Score 0 = skip (VLM runs on original).",
                MessageType.Info);

            if (_pendingPreview != null)
            {
                float w = Mathf.Min(position.width - 40, 480);
                Rect r = GUILayoutUtility.GetRect(w, w * 0.6f, GUILayout.ExpandWidth(false));
                EditorGUI.DrawPreviewTexture(r, _pendingPreview, null, ScaleMode.ScaleToFit);
            }

            EditorGUILayout.LabelField("Prompt:");
            EditorGUILayout.TextArea(_pendingPrompt ?? "", GUILayout.MinHeight(30));

            _humanScoreSlider = EditorGUILayout.IntSlider("Score (1–10)", _humanScoreSlider, 1, 10);

            using (new EditorGUILayout.HorizontalScope())
            {
                if (GUILayout.Button("Submit Score", GUILayout.Height(28)))
                {
                    _humanScoreTcs.TrySetResult(_humanScoreSlider);
                    ClearHumanPanel();
                }
                if (GUILayout.Button("Skip (0 = not scored)", GUILayout.Height(28)))
                {
                    _humanScoreTcs.TrySetResult(0);
                    ClearHumanPanel();
                }
            }

            EditorGUILayout.EndVertical();
        }

        private void ClearHumanPanel()
        {
            _pendingPreview   = null;
            _pendingPrompt    = null;
            _humanScoreTcs    = null;
            _humanScoreSlider = 7;
            Repaint();
        }

        private async Task<int> RequestHumanScoreAsync(string prompt, string previewPath)
        {
            _pendingPrompt  = prompt;
            _pendingPreview = string.IsNullOrEmpty(previewPath) || !File.Exists(previewPath)
                ? null
                : AssetDatabase.LoadAssetAtPath<Texture2D>(previewPath);
            if (_pendingPreview == null && File.Exists(previewPath))
            {
                // Load outside Asset DB (absolute path)
                byte[] bytes = File.ReadAllBytes(previewPath);
                _pendingPreview = new Texture2D(2, 2);
                _pendingPreview.LoadImage(bytes);
            }
            _humanScoreTcs = new TaskCompletionSource<int>();
            Repaint();
            return await _humanScoreTcs.Task;
        }

        // ══════════════════════════════════════════════════════════════════════
        //  GENERATION EXPERIMENT ASYNC LOGIC
        // ══════════════════════════════════════════════════════════════════════

        private async Task RunGenerationExperimentAsync()
        {
            if (_isRunning) return;
            _isRunning = true;
            _statusLog = "";
            _gen_currentRun = null;

            try
            {
                if (!File.Exists(_gen_shapesFile))
                {
                    AppendStatus($"ERROR: shape file not found: {_gen_shapesFile}");
                    return;
                }

                string[] prompts = File.ReadAllLines(_gen_shapesFile)
                    .Select(l => l.Trim())
                    .Where(l => !string.IsNullOrWhiteSpace(l) && !l.StartsWith("#"))
                    .ToArray();

                AppendStatus($"Loaded {prompts.Length} prompts from {_gen_shapesFile}");
                EnsureResultsFolder();

                string setName = Path.GetFileNameWithoutExtension(_gen_shapesFile);

                if (_gen_runNoRAG)
                    await RunGenerationPipelineAsync(prompts, "NoRAG", setName);

                if (!_isRunning) { AppendStatus("Aborted."); return; }

                if (_gen_runRAG)
                    await RunGenerationPipelineAsync(prompts, "RAG", setName);

                AppendStatus("\n✓ Generation experiment complete.");
            }
            catch (Exception ex)
            {
                AppendStatus($"EXCEPTION: {ex.Message}\n{ex.StackTrace}");
                UnityEngine.Debug.LogException(ex);
            }
            finally
            {
                _isRunning = false;
                Repaint();
            }
        }

        private async Task RunGenerationPipelineAsync(string[] prompts, string pipeline, string setName)
        {
            AppendStatus($"\n══ Pipeline: {pipeline} | Set: {setName} ══");

            var run = new GenerationExperimentRun
            {
                run_id             = Guid.NewGuid().ToString("N").Substring(0, 8),
                timestamp_utc      = DateTime.UtcNow.ToString("o"),
                pipeline           = pipeline,
                shape_set_name     = setName,
                llm_provider       = _gen_codeProvider,
                llm_model_id       = _gen_codeProvider,
                eval_provider      = _gen_evalProvider,
                max_iterations     = _gen_maxIter,
                success_threshold  = _gen_threshold,
                require_human_score = _gen_humanScore
            };
            _gen_currentRun = run;

            string jsonPath = Path.Combine(RESULTS_FOLDER,
                $"gen_{pipeline}_{setName}_{DateTime.UtcNow:yyyyMMdd_HHmmss}_{run.run_id}.json");

            for (int i = 0; i < prompts.Length; i++)
            {
                if (!_isRunning) break;
                AppendStatus($"[{pipeline}] Shape {i+1}/{prompts.Length}: {Truncate(prompts[i], 60)}");

                var shapeResult = pipeline == "RAG"
                    ? await RunSingleShape_RAG(prompts[i])
                    : await RunSingleShape_NoRAG(prompts[i]);

                shapeResult.shape_complexity = DetermineComplexity(setName);
                shapeResult.in_knowledge_base = _gen_markInRAG;

                // Aggregate human score from iterations (highest non-zero score)
                if (_gen_humanScore && shapeResult.iterations.Any(it => it.human_score > 0))
                {
                    shapeResult.human_score       = shapeResult.iterations.Max(it => it.human_score);
                    shapeResult.accepted_by_human = shapeResult.human_score >= _gen_threshold;
                }

                run.shapes.Add(shapeResult);
                AppendStatus($"  → success={shapeResult.success}  vlm={shapeResult.final_vlm_score}  " +
                             $"iters={shapeResult.iterations_used}  " +
                             $"time={shapeResult.total_time_ms/1000.0:F1}s");

                // Save after each shape (incremental)
                ComputeGenerationSummary(run);
                File.WriteAllText(jsonPath, JsonConvert.SerializeObject(run, Formatting.Indented));
                AssetDatabase.Refresh();
            }

            ComputeGenerationSummary(run);
            File.WriteAllText(jsonPath, JsonConvert.SerializeObject(run, Formatting.Indented));
            AssetDatabase.Refresh();
            AppendStatus($"Saved: {jsonPath}");
        }

        // ─── RAG single shape ─────────────────────────────────────────────────

        private async Task<GenerationShapeResult> RunSingleShape_RAG(string prompt)
        {
            var result = new GenerationShapeResult { prompt = prompt };
            var totalSw = Stopwatch.StartNew();

            for (int iter = 1; iter <= _gen_maxIter; iter++)
            {
                if (!_isRunning) break;

                var iterSw = Stopwatch.StartNew();
                var iterResult = new GenerationIterationResult { iteration_index = iter };

                try
                {
                    // Step 1: Decompose (to capture RAG stats)
                    var decompSw = Stopwatch.StartNew();
                    var decomp = await ShapeDecompositionService.DecomposeShapeAsync(
                        prompt, _knowledgeBase, _config.geminiKey);
                    decompSw.Stop();

                    if (decomp != null)
                    {
                        iterResult.rag_components_decomposed = decomp.total_components;

                        // Step 2: Retrieve examples (count & similarity)
                        float simSum = 0f;
                        int   retrieved = 0;
                        foreach (var comp in decomp.components)
                        {
                            var results = await SemanticShapeSearch.SearchAsync(
                                comp.description, _knowledgeBase, _config.openAIKey, topK: 1);
                            if (results?.Count > 0)
                            {
                                simSum += results[0].similarity;
                                retrieved++;
                            }
                        }
                        iterResult.rag_retrieved_examples  = retrieved;
                        iterResult.rag_avg_similarity_score = retrieved > 0 ? simSum / retrieved : 0f;
                    }

                    // Step 3: Run full RAG pipeline
                    ShaderGenerationPipeline.DisableAllPreviewQuads();
                    var pipelineResult = await RAGPipelineManager.RunCompletePipelineAsync(
                        prompt, _knowledgeBase, _config, maxIterations: 1,
                        outputDir:  "Assets/Experiment/Generated_RAG",
                        previewDir: "Assets/Experiment/Generated_RAG/Previews",
                        codeProvider: _gen_codeProvider);

                    // compile_ok = HLSL compiled and a preview was rendered (NOT dependent on internal VLM score)
                    iterResult.compile_ok         = pipelineResult != null &&
                                                    !string.IsNullOrEmpty(pipelineResult.previewImagePath) &&
                                                    !string.IsNullOrEmpty(pipelineResult.hlslCode);
                    iterResult.screenshot_path    = pipelineResult?.previewImagePath;
                    iterResult.shadergraph_asset_path = pipelineResult?.shaderGraphPath;
                    iterResult.material_asset_path    = pipelineResult?.materialPath;
                    iterResult.hlsl_length        = pipelineResult?.hlslCode?.Length ?? 0;
                    iterResult.llm_usage.input_tokens  = pipelineResult?.llm_input_tokens  ?? 0;
                    iterResult.llm_usage.output_tokens = pipelineResult?.llm_output_tokens ?? 0;
                    LlmPricing.Fill(iterResult.llm_usage, _gen_codeProvider);
                    ShaderGenerationPipeline.DisableAllPreviewQuads();

                    // Step 4: Evaluate — human first, then VLM on fresh screenshot
                    if (!iterResult.compile_ok || string.IsNullOrEmpty(iterResult.screenshot_path))
                    {
                        iterResult.vlm_score       = 1;
                        iterResult.vlm_explanation = pipelineResult?.errorMessage ?? "Pipeline failed";
                    }
                    else if (_gen_humanScore)
                    {
                        int humanScore = await RequestHumanScoreAsync(prompt, iterResult.screenshot_path);
                        iterResult.human_score = humanScore;

                        if (humanScore == 0 || humanScore >= _gen_threshold)
                        {
                            string freshPath = await CaptureCurrentPreviewAsync(iterResult.screenshot_path);
                            iterResult.vlm_screenshot_path = freshPath;
                            var evalResult = await EvaluateShapeVLMAsync(prompt, pipelineResult.hlslCode ?? "", freshPath);
                            iterResult.vlm_score       = evalResult.score;
                            iterResult.vlm_explanation = evalResult.explanation;
                        }
                        else
                        {
                            iterResult.vlm_score       = humanScore;
                            iterResult.vlm_explanation = "Rejected by human evaluator.";
                        }
                    }
                    else
                    {
                        var evalResult = await EvaluateShapeVLMAsync(
                            prompt, pipelineResult.hlslCode ?? "", iterResult.screenshot_path);
                        iterResult.vlm_score       = evalResult.score;
                        iterResult.vlm_explanation = evalResult.explanation;
                    }
                }
                catch (Exception ex)
                {
                    iterResult.compile_ok      = false;
                    iterResult.vlm_score       = 1;
                    iterResult.vlm_explanation = ex.Message;
                    UnityEngine.Debug.LogWarning($"[Experiment RAG iter {iter}] {ex.Message}");
                }

                iterSw.Stop();
                iterResult.iteration_time_ms = iterSw.Elapsed.TotalMilliseconds;
                result.iterations.Add(iterResult);

                AppendStatus($"  Iter {iter}: compile={iterResult.compile_ok}  " +
                             $"score={iterResult.vlm_score}  " +
                             $"rag_components={iterResult.rag_components_decomposed}  " +
                             $"retrieved={iterResult.rag_retrieved_examples}  " +
                             $"avgSim={iterResult.rag_avg_similarity_score:F2}  " +
                             $"time={iterResult.iteration_time_ms/1000:F1}s");

                if (iterResult.compile_ok && iterResult.vlm_score >= _gen_threshold)
                {
                    result.success               = true;
                    result.iterations_used        = iter;
                    result.final_vlm_score        = iterResult.vlm_score;
                    result.final_vlm_explanation  = iterResult.vlm_explanation;
                    result.first_pass_compiled    = result.iterations[0].compile_ok;
                    result.rag_components_decomposed  = iterResult.rag_components_decomposed;
                    result.rag_retrieved_examples     = iterResult.rag_retrieved_examples;
                    result.rag_avg_similarity_score   = iterResult.rag_avg_similarity_score;
                    break;
                }
            }

            totalSw.Stop();
            result.total_time_ms = totalSw.Elapsed.TotalMilliseconds;

            if (!result.success)
            {
                result.iterations_used = result.iterations.Count;
                var last = result.iterations.LastOrDefault();
                if (last != null)
                {
                    result.final_vlm_score       = last.vlm_score;
                    result.final_vlm_explanation = last.vlm_explanation;
                    result.rag_components_decomposed = last.rag_components_decomposed;
                    result.rag_retrieved_examples    = last.rag_retrieved_examples;
                    result.rag_avg_similarity_score  = last.rag_avg_similarity_score;
                }
            }
            if (result.iterations.Count > 0)
                result.first_pass_compiled = result.iterations[0].compile_ok;

            result.llm_usage_total = LlmPricing.Aggregate(result.iterations.Select(i => i.llm_usage));

            return result;
        }

        // ─── No-RAG single shape ──────────────────────────────────────────────

        private async Task<GenerationShapeResult> RunSingleShape_NoRAG(string prompt)
        {
            var result = new GenerationShapeResult { prompt = prompt };
            var totalSw = Stopwatch.StartNew();

            var settings = new GenerationSettings
            {
                UseTransparency  = true,
                HlslFolder       = "Assets/Experiment/Generated_NoRAG/HLSL",
                GraphFolder      = "Assets/Experiment/Generated_NoRAG/Graphs",
                PreviewFolder    = "Assets/Experiment/Generated_NoRAG/Previews",
                SuccessFolder    = "Assets/Experiment/Generated_NoRAG/Success"
            };

            string currentPrompt = ShaderPromptBuilder.BuildLLMPrompt(prompt, settings.UseTransparency);
            LLMShaderResponse llmResponse = null;

            for (int iter = 1; iter <= _gen_maxIter; iter++)
            {
                if (!_isRunning) break;

                var iterSw = Stopwatch.StartNew();
                var iterResult = new GenerationIterationResult { iteration_index = iter };

                try
                {
                    var (jsonResp, inTok, outTok) = await CallCodeLLMAsync(currentPrompt);
                    iterResult.llm_usage.input_tokens  = inTok;
                    iterResult.llm_usage.output_tokens = outTok;
                    LlmPricing.Fill(iterResult.llm_usage, _gen_codeProvider);

                    if (string.IsNullOrEmpty(jsonResp))
                    {
                        iterResult.compile_ok      = false;
                        iterResult.vlm_score       = 1;
                        iterResult.vlm_explanation = "LLM returned empty response.";
                        goto IterEnd;
                    }

                    jsonResp = StripMarkdown(jsonResp);
                    try { llmResponse = JsonConvert.DeserializeObject<LLMShaderResponse>(jsonResp); }
                    catch
                    {
                        iterResult.compile_ok      = false;
                        iterResult.vlm_score       = 1;
                        iterResult.vlm_explanation = "Invalid JSON from LLM.";
                        goto IterEnd;
                    }

                    iterResult.hlsl_length = llmResponse.hlsl_code?.Length ?? 0;

                    ShaderGenerationPipeline.DisableAllPreviewQuads();

                    string previewPath;
                    try
                    {
                        previewPath = await ShaderGenerationPipeline.ExecutePipelineAsync(llmResponse, settings);
                        iterResult.compile_ok = true;
                    }
                    catch (Exception ex)
                    {
                        iterResult.compile_ok      = false;
                        iterResult.vlm_score       = 1;
                        iterResult.vlm_explanation = $"Pipeline error: {ex.Message}";
                        goto IterEnd;
                    }

                    iterResult.screenshot_path = previewPath;

                    // Evaluate — human first, then VLM on fresh screenshot
                    if (_gen_humanScore)
                    {
                        int humanScore = await RequestHumanScoreAsync(prompt, previewPath);
                        iterResult.human_score = humanScore;

                        if (humanScore == 0 || humanScore >= _gen_threshold)
                        {
                            // Human accepted (or skipped) — take fresh screenshot then VLM
                            string freshPath = await CaptureCurrentPreviewAsync(previewPath);
                            iterResult.vlm_screenshot_path = freshPath;
                            var evalResult = await EvaluateShapeVLMAsync(prompt, llmResponse.hlsl_code, freshPath);
                            iterResult.vlm_score       = evalResult.score;
                            iterResult.vlm_explanation = evalResult.explanation;
                        }
                        else
                        {
                            // Human rejected — skip VLM, use human score as proxy
                            iterResult.vlm_score       = humanScore;
                            iterResult.vlm_explanation = "Rejected by human evaluator.";
                        }
                    }
                    else
                    {
                        var evalResult = await EvaluateShapeVLMAsync(prompt, llmResponse.hlsl_code, previewPath);
                        iterResult.vlm_score       = evalResult.score;
                        iterResult.vlm_explanation = evalResult.explanation;
                    }

                    if (iterResult.compile_ok && iterResult.vlm_score < _gen_threshold)
                        currentPrompt = ShaderPromptBuilder.BuildRefinementPrompt(
                            prompt, llmResponse, iterResult.vlm_explanation);
                }
                catch (Exception ex)
                {
                    iterResult.compile_ok      = false;
                    iterResult.vlm_score       = 1;
                    iterResult.vlm_explanation = ex.Message;
                }

                IterEnd:
                iterSw.Stop();
                iterResult.iteration_time_ms = iterSw.Elapsed.TotalMilliseconds;
                result.iterations.Add(iterResult);

                AppendStatus($"  Iter {iter}: compile={iterResult.compile_ok}  " +
                             $"score={iterResult.vlm_score}  time={iterResult.iteration_time_ms/1000:F1}s");

                if (iterResult.compile_ok && iterResult.vlm_score >= _gen_threshold)
                {
                    result.success              = true;
                    result.iterations_used      = iter;
                    result.final_vlm_score      = iterResult.vlm_score;
                    result.final_vlm_explanation = iterResult.vlm_explanation;
                    break;
                }
            }

            totalSw.Stop();
            result.total_time_ms = totalSw.Elapsed.TotalMilliseconds;

            if (!result.success)
            {
                result.iterations_used = result.iterations.Count;
                var last = result.iterations.LastOrDefault();
                if (last != null)
                {
                    result.final_vlm_score       = last.vlm_score;
                    result.final_vlm_explanation = last.vlm_explanation;
                }
            }
            if (result.iterations.Count > 0)
                result.first_pass_compiled = result.iterations[0].compile_ok;

            result.llm_usage_total = LlmPricing.Aggregate(result.iterations.Select(i => i.llm_usage));

            return result;
        }

        private void ComputeGenerationSummary(GenerationExperimentRun run)
        {
            if (run.shapes.Count == 0) return;
            run.summary_success_rate           = (float)run.shapes.Count(s => s.success)          / run.shapes.Count;
            run.summary_avg_vlm_score          = (float)run.shapes.Average(s => s.final_vlm_score);
            run.summary_avg_iterations         = (float)run.shapes.Average(s => s.iterations_used);
            run.summary_avg_time_ms            = (float)run.shapes.Average(s => s.total_time_ms);
            run.summary_compile_rate           = (float)run.shapes.Count(s => s.first_pass_compiled) / run.shapes.Count;
            run.summary_avg_human_score        = run.shapes.Any(s => s.human_score > 0)
                ? (float)run.shapes.Where(s => s.human_score > 0).Average(s => s.human_score) : 0f;
            run.summary_first_pass_compile_rate = run.summary_compile_rate;

            var agg = LlmPricing.Aggregate(run.shapes.Select(s => s.llm_usage_total));
            run.summary_total_input_tokens  = agg.input_tokens;
            run.summary_total_output_tokens = agg.output_tokens;
            run.summary_total_tokens        = agg.total_tokens;
            run.summary_total_cost_usd      = agg.cost_usd;
        }

        // ══════════════════════════════════════════════════════════════════════
        //  EDIT EXPERIMENT ASYNC LOGIC
        // ══════════════════════════════════════════════════════════════════════

        private async Task RunEditExperimentAsync()
        {
            if (_isRunning) return;
            _isRunning = true;
            _statusLog = "";
            _edit_currentRun = null;

            try
            {
                if (!File.Exists(_edit_configFile))
                {
                    AppendStatus($"ERROR: config file not found: {_edit_configFile}");
                    return;
                }

                var pairs = JsonConvert.DeserializeObject<List<EditRequestConfig>>(
                    File.ReadAllText(_edit_configFile));

                AppendStatus($"Loaded {pairs.Count} edit request pairs.");
                EnsureResultsFolder();

                var run = new EditExperimentRun
                {
                    run_id        = Guid.NewGuid().ToString("N").Substring(0, 8),
                    timestamp_utc = DateTime.UtcNow.ToString("o")
                };
                _edit_currentRun = run;

                string jsonPath = Path.Combine(RESULTS_FOLDER,
                    $"edit_{DateTime.UtcNow:yyyyMMdd_HHmmss}_{run.run_id}.json");

                foreach (var pair in pairs)
                {
                    if (!_isRunning) break;
                    AppendStatus($"\nEdit: [{Truncate(pair.shape_prompt, 40)}] → [{Truncate(pair.edit_request, 40)}]");

                    var item = await RunSingleEditAsync(pair.shape_prompt, pair.edit_request);

                    if (_edit_humanScore)
                    {
                        int human = await RequestHumanScoreAsync(pair.edit_request, item.screenshot_after_path);
                        item.human_score       = human;
                        item.accepted_by_human = human >= 7;
                    }

                    run.items.Add(item);
                    ComputeEditSummary(run);
                    File.WriteAllText(jsonPath, JsonConvert.SerializeObject(run, Formatting.Indented));
                    AssetDatabase.Refresh();
                }

                AppendStatus("\n✓ Edit experiment complete. Saved: " + jsonPath);
            }
            catch (Exception ex)
            {
                AppendStatus($"EXCEPTION: {ex.Message}");
                UnityEngine.Debug.LogException(ex);
            }
            finally
            {
                _isRunning = false;
                Repaint();
            }
        }

        private async Task<EditExperimentItem> RunSingleEditAsync(string shapePrompt, string editRequest)
        {
            var item = new EditExperimentItem
            {
                base_shape_prompt = shapePrompt,
                edit_request      = editRequest
            };
            var totalSw = Stopwatch.StartNew();

            try
            {
                // Step 1: Generate the base shape
                AppendStatus("  Generating base shape...");
                var pipeResult = await RAGPipelineManager.RunCompletePipelineAsync(
                    shapePrompt, _knowledgeBase, _config, maxIterations: 3);

                if (pipeResult == null || !pipeResult.success)
                {
                    item.edit_type = "Unknown";
                    item.success   = false;
                    totalSw.Stop();
                    item.total_time_ms = totalSw.Elapsed.TotalMilliseconds;
                    AppendStatus("  Base shape generation failed.");
                    return item;
                }

                item.material_name   = pipeResult.fileName;
                item.material_path   = pipeResult.materialPath;
                item.screenshot_before_path = pipeResult.previewImagePath;

                // Evaluate BEFORE score
                var beforeEval = await EvaluateShapeVLMAsync(
                    shapePrompt, pipeResult.hlslCode ?? "", pipeResult.previewImagePath ?? "");
                item.vlm_score_before = beforeEval.score;

                AppendStatus($"  Base shape ready (VLM={beforeEval.score}). Classifying edit...");

                // Step 2: Load material and get its properties
                var mat = AssetDatabase.LoadAssetAtPath<Material>(pipeResult.materialPath);
                var props = GetMaterialProperties(mat);

                // Step 3: Classify the edit request
                var classification = await EditClassifier.ClassifyEditRequestAsync(
                    editRequest, pipeResult.fileName, props, _config.geminiKey);

                item.edit_type             = classification.needs_hlsl_change ? "HLSLUpdate" : "PropertyChange";
                item.classification_reason = classification.reason;
                AppendStatus($"  Edit type: {item.edit_type}  ({classification.reason})");

                // Step 4: Apply the edit
                var iterSw = Stopwatch.StartNew();

                if (!classification.needs_hlsl_change)
                {
                    // Property-only edit
                    foreach (var change in classification.material_changes)
                        ApplyMaterialChange(mat, change);
                    AssetDatabase.SaveAssets();

                    // Render after screenshot
                    string afterPath = Path.Combine(RESULTS_FOLDER,
                        $"edit_after_{pipeResult.fileName}_{Guid.NewGuid():N}.png");
                    bool rendered = await RenderMaterialPreviewAsync(mat, afterPath);
                    iterSw.Stop();

                    item.screenshot_after_path = rendered ? afterPath : "";
                    item.iterations_used       = 1;
                    var afterEval = await EvaluateShapeVLMAsync(editRequest, "", afterPath);
                    item.vlm_score_after   = afterEval.score;
                    item.score_improvement = item.vlm_score_after - item.vlm_score_before;
                    item.success           = item.vlm_score_after >= 7;

                    item.iterations.Add(new EditIterationResult
                    {
                        iteration_index    = 1,
                        iteration_time_ms  = iterSw.Elapsed.TotalMilliseconds,
                        vlm_score          = afterEval.score,
                        vlm_explanation    = afterEval.explanation,
                        screenshot_path    = afterPath,
                        compile_ok         = true
                    });
                }
                else
                {
                    // HLSL update edit
                    var updateResult = await HLSLUpdatePipelineManager.RunUpdatePipelineAsync(
                        mat,
                        classification.hlsl_update_request,
                        _knowledgeBase,
                        _config);
                    iterSw.Stop();

                    item.success               = updateResult?.success ?? false;
                    item.screenshot_after_path = updateResult?.afterImagePath ?? "";
                    item.iterations_used       = 1;

                    var afterEval = updateResult?.success == true
                        ? new LLMMatchScoreResponse { score = updateResult.vlmScore, explanation = updateResult.vlmFeedback }
                        : await EvaluateShapeVLMAsync(editRequest, "", item.screenshot_after_path);

                    item.vlm_score_after   = afterEval?.score ?? 0;
                    item.score_improvement = item.vlm_score_after - item.vlm_score_before;

                    item.iterations.Add(new EditIterationResult
                    {
                        iteration_index   = 1,
                        iteration_time_ms = iterSw.Elapsed.TotalMilliseconds,
                        vlm_score         = item.vlm_score_after,
                        compile_ok        = updateResult?.success ?? false,
                        screenshot_path   = item.screenshot_after_path
                    });
                }

                AppendStatus($"  Edit done: success={item.success}  vlm_before={item.vlm_score_before}  " +
                             $"vlm_after={item.vlm_score_after}  Δ={item.score_improvement:+0;-0}");
            }
            catch (Exception ex)
            {
                item.success       = false;
                item.edit_type     = item.edit_type ?? "Unknown";
                UnityEngine.Debug.LogWarning($"[Experiment Edit] {ex.Message}");
                AppendStatus($"  Edit error: {ex.Message}");
            }

            totalSw.Stop();
            item.total_time_ms = totalSw.Elapsed.TotalMilliseconds;
            return item;
        }

        private void ComputeEditSummary(EditExperimentRun run)
        {
            if (run.items.Count == 0) return;
            run.summary_success_rate        = (float)run.items.Count(e => e.success)                            / run.items.Count;
            run.summary_avg_score_improvement = (float)run.items.Average(e => e.score_improvement);
            run.summary_property_change_rate = (float)run.items.Count(e => e.edit_type == "PropertyChange")    / run.items.Count;
            run.summary_hlsl_update_rate     = (float)run.items.Count(e => e.edit_type == "HLSLUpdate")        / run.items.Count;
            run.summary_avg_time_ms          = (float)run.items.Average(e => e.total_time_ms);
        }

        // ══════════════════════════════════════════════════════════════════════
        //  ANIMATION EXPERIMENT ASYNC LOGIC
        // ══════════════════════════════════════════════════════════════════════

        private async Task RunAnimationExperimentAsync()
        {
            if (_isRunning) return;
            _isRunning = true;
            _statusLog = "";
            _anim_currentRun = null;

            try
            {
                if (!File.Exists(_anim_configFile))
                {
                    AppendStatus($"ERROR: config file not found: {_anim_configFile}");
                    return;
                }

                var pairs = JsonConvert.DeserializeObject<List<AnimationRequestConfig>>(
                    File.ReadAllText(_anim_configFile));

                AppendStatus($"Loaded {pairs.Count} animation request pairs.");
                EnsureResultsFolder();

                var run = new AnimationExperimentRun
                {
                    run_id        = Guid.NewGuid().ToString("N").Substring(0, 8),
                    timestamp_utc = DateTime.UtcNow.ToString("o")
                };
                _anim_currentRun = run;

                string jsonPath = Path.Combine(RESULTS_FOLDER,
                    $"anim_{DateTime.UtcNow:yyyyMMdd_HHmmss}_{run.run_id}.json");

                foreach (var pair in pairs)
                {
                    if (!_isRunning) break;
                    AppendStatus($"\nAnim: [{Truncate(pair.shape_prompt, 40)}] → [{Truncate(pair.animation_request, 40)}]");

                    var item = await RunSingleAnimationAsync(pair.shape_prompt, pair.animation_request);

                    if (_anim_humanScore)
                    {
                        int human = await RequestHumanScoreAsync(pair.animation_request, null);
                        item.human_score       = human;
                        item.accepted_by_human = human >= 7;
                    }

                    run.items.Add(item);
                    ComputeAnimSummary(run);
                    File.WriteAllText(jsonPath, JsonConvert.SerializeObject(run, Formatting.Indented));
                    AssetDatabase.Refresh();
                }

                AppendStatus("\n✓ Animation experiment complete. Saved: " + jsonPath);
            }
            catch (Exception ex)
            {
                AppendStatus($"EXCEPTION: {ex.Message}");
                UnityEngine.Debug.LogException(ex);
            }
            finally
            {
                _isRunning = false;
                Repaint();
            }
        }

        private async Task<AnimationExperimentItem> RunSingleAnimationAsync(
            string shapePrompt, string animRequest)
        {
            var item = new AnimationExperimentItem
            {
                base_shape_prompt  = shapePrompt,
                animation_request  = animRequest
            };
            var sw = Stopwatch.StartNew();

            try
            {
                AppendStatus("  Generating base shape...");
                var pipeResult = await RAGPipelineManager.RunCompletePipelineAsync(
                    shapePrompt, _knowledgeBase, _config, maxIterations: 3);

                if (pipeResult == null || !pipeResult.success)
                {
                    item.success       = false;
                    item.error_message = "Base shape generation failed";
                    sw.Stop();
                    item.total_time_ms = sw.Elapsed.TotalMilliseconds;
                    return item;
                }

                item.material_name = pipeResult.fileName;
                item.material_path = pipeResult.materialPath;
                AppendStatus($"  Base shape ready. Generating animation script...");

                // Run animation pipeline
                var mat = AssetDatabase.LoadAssetAtPath<Material>(pipeResult.materialPath);
                var animResult = await MaterialAnimatorPipelineManager.RunPipelineAsync(
                    mat, animRequest, _config, _knowledgeBase, useKB: true);

                item.success              = animResult?.success ?? false;
                item.generated_script_path = animResult?.scriptAssetPath ?? "";
                item.error_message        = animResult?.errorMessage ?? "";

                AppendStatus($"  Animation done: success={item.success}");
            }
            catch (Exception ex)
            {
                item.success       = false;
                item.error_message = ex.Message;
                AppendStatus($"  Animation error: {ex.Message}");
            }

            sw.Stop();
            item.total_time_ms = sw.Elapsed.TotalMilliseconds;
            return item;
        }

        private void ComputeAnimSummary(AnimationExperimentRun run)
        {
            if (run.items.Count == 0) return;
            run.summary_success_rate      = (float)run.items.Count(a => a.success) / run.items.Count;
            run.summary_avg_time_ms       = (float)run.items.Average(a => a.total_time_ms);
            run.summary_avg_human_score   = run.items.Any(a => a.human_score > 0)
                ? (float)run.items.Where(a => a.human_score > 0).Average(a => a.human_score) : 0f;
        }

        // ══════════════════════════════════════════════════════════════════════
        //  IMAGE → SHADER EXPERIMENT ASYNC LOGIC
        // ══════════════════════════════════════════════════════════════════════

        private async Task RunImageExperimentAsync()
        {
            if (_isRunning) return;
            _isRunning = true;
            _statusLog = "";
            _img_currentRun = null;

            try
            {
                if (!File.Exists(_img_configFile))
                {
                    AppendStatus($"ERROR: config file not found: {_img_configFile}");
                    return;
                }

                var requests = JsonConvert.DeserializeObject<List<ImageRequestConfig>>(
                    File.ReadAllText(_img_configFile));

                AppendStatus($"Loaded {requests.Count} image request(s).");
                EnsureResultsFolder();

                var run = new ImageExperimentRun
                {
                    run_id        = Guid.NewGuid().ToString("N").Substring(0, 8),
                    timestamp_utc = DateTime.UtcNow.ToString("o")
                };
                _img_currentRun = run;

                string jsonPath = Path.Combine(RESULTS_FOLDER,
                    $"img2shader_{DateTime.UtcNow:yyyyMMdd_HHmmss}_{run.run_id}.json");

                foreach (var req in requests)
                {
                    if (!_isRunning) break;

                    string absPath = Path.GetFullPath(req.image_path);
                    AppendStatus($"\nImage: {Path.GetFileName(req.image_path)}");

                    var item = await RunSingleImageAsync(absPath, req.editable_hints);

                    if (_img_humanScore)
                    {
                        int human = await RequestHumanScoreAsync(
                            $"Image: {req.image_path}\nHints: {req.editable_hints}",
                            item.preview_image_path);
                        item.human_score       = human;
                        item.accepted_by_human = human >= 7;
                    }

                    run.items.Add(item);
                    ComputeImageSummary(run);
                    File.WriteAllText(jsonPath, JsonConvert.SerializeObject(run, Formatting.Indented));
                    AssetDatabase.Refresh();

                    AppendStatus($"  → success={item.success}  vlm={item.vlm_score}  " +
                                 $"time={item.total_time_ms / 1000.0:F1}s");
                }

                AppendStatus("\n✓ Image→Shader experiment complete. Saved: " + jsonPath);
            }
            catch (Exception ex)
            {
                AppendStatus($"EXCEPTION: {ex.Message}");
                UnityEngine.Debug.LogException(ex);
            }
            finally
            {
                _isRunning = false;
                Repaint();
            }
        }

        private async Task<ImageExperimentItem> RunSingleImageAsync(string absImagePath, string editableHints)
        {
            var item = new ImageExperimentItem
            {
                image_path     = absImagePath,
                editable_hints = editableHints
            };
            var sw = Stopwatch.StartNew();

            try
            {
                var result = await ImageToShaderPipelineManager.RunPipelineAsync(
                    absImagePath, editableHints, _knowledgeBase, _config,
                    maxVlmIterations: _img_maxIter);

                item.success             = result.success;
                item.vlm_score           = result.vlmScore;
                item.vlm_feedback        = result.vlmFeedback;
                item.visual_description  = result.visualDescription;
                item.shader_graph_path   = result.shaderGraphPath;
                item.material_path       = result.materialPath;
                item.preview_image_path  = result.previewImagePath;
                item.error_message       = result.errorMessage;
            }
            catch (Exception ex)
            {
                item.success       = false;
                item.error_message = ex.Message;
                AppendStatus($"  Image error: {ex.Message}");
            }

            sw.Stop();
            item.total_time_ms = sw.Elapsed.TotalMilliseconds;
            return item;
        }

        private void ComputeImageSummary(ImageExperimentRun run)
        {
            if (run.items.Count == 0) return;
            run.summary_success_rate    = (float)run.items.Count(i => i.success) / run.items.Count;
            run.summary_avg_vlm_score   = (float)run.items.Average(i => i.vlm_score);
            run.summary_avg_time_ms     = (float)run.items.Average(i => i.total_time_ms);
            run.summary_avg_human_score = run.items.Any(i => i.human_score > 0)
                ? (float)run.items.Where(i => i.human_score > 0).Average(i => i.human_score) : 0f;
        }

        // ══════════════════════════════════════════════════════════════════════
        //  RESULTS OVERVIEW HELPERS
        // ══════════════════════════════════════════════════════════════════════

        private void LoadResultsSummary()
        {
            _loaded_files.Clear();
            _loaded_summary = "";

            if (!Directory.Exists(RESULTS_FOLDER))
            {
                _loaded_summary = "Results folder does not exist yet.";
                return;
            }

            _loaded_files = Directory.GetFiles(RESULTS_FOLDER, "*.json")
                .OrderByDescending(f => File.GetLastWriteTime(f))
                .ToList();

            // Quick aggregate stats
            int genRag = 0, genNoRag = 0, editRuns = 0, animRuns = 0, imgRuns = 0;
            int genRagSuccess = 0, genNoRagSuccess = 0, editSuccess = 0, animSuccess = 0, imgSuccess = 0;
            int genRagTotal = 0, genNoRagTotal = 0, editTotal = 0, animTotal = 0, imgTotal = 0;

            foreach (var f in _loaded_files)
            {
                try
                {
                    string json = File.ReadAllText(f);
                    if (json.Contains("\"experiment_type\": \"generation\"") ||
                        json.Contains("\"experiment_type\":\"generation\""))
                    {
                        var run = JsonConvert.DeserializeObject<GenerationExperimentRun>(json);
                        if (run.pipeline == "RAG")
                        {
                            genRag++;
                            genRagSuccess += run.shapes.Count(s => s.success);
                            genRagTotal   += run.shapes.Count;
                        }
                        else
                        {
                            genNoRag++;
                            genNoRagSuccess += run.shapes.Count(s => s.success);
                            genNoRagTotal   += run.shapes.Count;
                        }
                    }
                    else if (json.Contains("\"experiment_type\": \"edit\"") ||
                             json.Contains("\"experiment_type\":\"edit\""))
                    {
                        var run = JsonConvert.DeserializeObject<EditExperimentRun>(json);
                        editRuns++;
                        editSuccess += run.items.Count(e => e.success);
                        editTotal   += run.items.Count;
                    }
                    else if (json.Contains("\"experiment_type\": \"animation\"") ||
                             json.Contains("\"experiment_type\":\"animation\""))
                    {
                        var run = JsonConvert.DeserializeObject<AnimationExperimentRun>(json);
                        animRuns++;
                        animSuccess += run.items.Count(a => a.success);
                        animTotal   += run.items.Count;
                    }
                    else if (json.Contains("\"experiment_type\": \"image_to_shader\"") ||
                             json.Contains("\"experiment_type\":\"image_to_shader\""))
                    {
                        var run = JsonConvert.DeserializeObject<ImageExperimentRun>(json);
                        imgRuns++;
                        imgSuccess += run.items.Count(i => i.success);
                        imgTotal   += run.items.Count;
                    }
                }
                catch { /* skip malformed files */ }
            }

            _loaded_summary =
                $"GENERATION (RAG — Phase 2):   {genRag} run(s)   {genRagTotal} shapes   " +
                $"success={SafeRate(genRagSuccess, genRagTotal):P0}\n" +
                $"GENERATION (No-RAG — Phase 1): {genNoRag} run(s)  {genNoRagTotal} shapes   " +
                $"success={SafeRate(genNoRagSuccess, genNoRagTotal):P0}\n" +
                $"EDIT (Phase 2 only):          {editRuns} run(s)  {editTotal} edits   " +
                $"success={SafeRate(editSuccess, editTotal):P0}\n" +
                $"ANIMATION (Phase 2 only):     {animRuns} run(s)  {animTotal} anims   " +
                $"success={SafeRate(animSuccess, animTotal):P0}\n" +
                $"IMAGE→SHADER:                 {imgRuns} run(s)  {imgTotal} images  " +
                $"success={SafeRate(imgSuccess, imgTotal):P0}";
        }

        private static float SafeRate(int num, int denom) =>
            denom == 0 ? 0f : (float)num / denom;

        private void LaunchPythonVisualizer()
        {
            string scriptPath = Path.GetFullPath("Assets/Experiment/Visualization/visualize_results.py");
            string resultsDir = Path.GetFullPath(RESULTS_FOLDER);
            string outDir     = Path.GetFullPath("Assets/Experiment/Visualization/Charts");

            try
            {
                // Try to find Python executable — prefer project venv, then PATH entries.
                // Deliberately exclude "py" (Windows Launcher) as it may be configured to use
                // a Python version that is no longer installed, causing a misleading error.
                string venvPython = Path.GetFullPath(@"kb_env\Scripts\python.exe");
                string[] candidates = { venvPython, "python", "python3" };
                string   python     = null;
                foreach (var c in candidates)
                {
                    try
                    {
                        var test = new System.Diagnostics.ProcessStartInfo(c, "--version")
                        {
                            RedirectStandardOutput = true,
                            RedirectStandardError  = true,
                            UseShellExecute = false,
                            CreateNoWindow = true
                        };
                        var proc = Process.Start(test);
                        proc?.WaitForExit(2000);
                        if (proc?.ExitCode == 0) { python = c; break; }
                    }
                    catch { /* try next */ }
                }

                if (python == null)
                {
                    EditorUtility.DisplayDialog("Python Not Found",
                        "Could not find Python. Open a terminal and run:\n\n" +
                        $"python \"{scriptPath}\" --results_dir \"{resultsDir}\" --out_dir \"{outDir}\"",
                        "OK");
                    return;
                }

                // Write a temp batch file to avoid cmd.exe quoting issues with spaces in paths.
                string batPath = Path.Combine(Path.GetTempPath(), "run_visualizer.bat");
                File.WriteAllText(batPath,
                    $"@echo off\r\n" +
                    $"\"{python}\" \"{scriptPath}\" --results_dir \"{resultsDir}\" --out_dir \"{outDir}\"\r\n" +
                    $"pause\r\n");
                var psi = new ProcessStartInfo
                {
                    FileName        = batPath,
                    UseShellExecute = true
                };
                Process.Start(psi);
                AppendStatus("Launched Python visualizer.");
            }
            catch (Exception ex)
            {
                EditorUtility.DisplayDialog("Launch Failed", ex.Message, "OK");
            }
        }

        // ══════════════════════════════════════════════════════════════════════
        //  API HELPERS
        // ══════════════════════════════════════════════════════════════════════

        private async Task<LLMMatchScoreResponse> EvaluateShapeVLMAsync(
            string prompt, string hlslCode, string previewPath)
        {
            try
            {
                string evalJson;
                if (_gen_evalProvider.StartsWith("gemini-"))
                    evalJson = await GeminiApiService.CallGeminiEvalAsync(
                        prompt, hlslCode, previewPath, _config.geminiKey, _gen_evalProvider);
                else
                    evalJson = await OpenAIApiService.CallOpenAIEvalAsync(
                        prompt, hlslCode, null, previewPath, _config.openAIKey);

                if (!string.IsNullOrEmpty(evalJson))
                {
                    evalJson = StripMarkdown(evalJson);
                    return JsonConvert.DeserializeObject<LLMMatchScoreResponse>(evalJson)
                           ?? new LLMMatchScoreResponse { score = 1, explanation = "Parse failed." };
                }
            }
            catch (Exception ex)
            {
                UnityEngine.Debug.LogWarning($"[Experiment VLM] {ex.Message}");
            }
            return new LLMMatchScoreResponse { score = 1, explanation = "Eval unavailable." };
        }

        private async Task<string> CaptureCurrentPreviewAsync(string originalPath)
        {
            // Find the active preview quad — either NoRAG ("... Preview Quad") or RAG ("RAG Preview — ...")
            // Take the last match so we get the most recently created one
            var renderers = UnityEngine.Object.FindObjectsByType<MeshRenderer>(FindObjectsSortMode.None);
            MeshRenderer target = null;
            foreach (var r in renderers)
            {
                if (r.sharedMaterial != null &&
                    (r.name.Contains("Preview Quad") || r.name.StartsWith("RAG Preview")))
                    target = r;
            }

            if (target == null)
            {
                AppendStatus("  [CapturePreview] No active preview quad found — using original screenshot.");
                return originalPath;
            }

            string freshPath = originalPath.Replace(".png", "_vlm.png");
            bool ok = await RenderMaterialPreviewAsync(target.sharedMaterial, freshPath);
            if (ok) AppendStatus($"  [CapturePreview] Fresh screenshot captured from '{target.name}'.");
            return ok ? freshPath : originalPath;
        }

//
        private Task<(string content, int inputTokens, int outputTokens)> CallCodeLLMAsync(string prompt)
        {
            if (_gen_codeProvider.StartsWith("gemini-"))
                return GeminiApiService.CallGeminiWithUsageAsync(prompt, _config.geminiKey, _gen_codeProvider);
            if (_gen_codeProvider.StartsWith("gpt-"))
                return OpenAIApiService.CallOpenAIGenerateWithUsageAsync(prompt, _config.openAIKey, _gen_codeProvider);
            if (_gen_codeProvider.StartsWith("claude-"))
                return ClaudeApiService.CallClaudeWithUsageAsync(prompt, _config.claudeKey);
            if (_gen_codeProvider.StartsWith("kimi-"))
                return KimiApiService.CallKimiWithUsageAsync(prompt, _config.kimiKey, _gen_codeProvider);

            UnityEngine.Debug.LogWarning($"[Experiment] Unknown provider '{_gen_codeProvider}', falling back to Gemini.");
            return GeminiApiService.CallGeminiWithUsageAsync(prompt, _config.geminiKey);
        }

        private async Task<bool> RenderMaterialPreviewAsync(Material mat, string outputPath)
        {
            try
            {
                Directory.CreateDirectory(Path.GetDirectoryName(outputPath));

                var quad = GameObject.CreatePrimitive(PrimitiveType.Quad);
                quad.name = "_ExperimentPreview";
                quad.GetComponent<Renderer>().material = mat;

                var cameraGO = new GameObject("_ExperimentCamera");
                var cam      = cameraGO.AddComponent<Camera>();
                cam.transform.position = new Vector3(0, 0, -2);
                cam.clearFlags         = CameraClearFlags.SolidColor;
                cam.backgroundColor    = Color.white;
                cam.orthographic       = true;
                cam.orthographicSize   = 0.55f;

                var rt = new RenderTexture(512, 512, 24);
                cam.targetTexture = rt;

                await Task.Delay(100);
                cam.Render();

                RenderTexture.active = rt;
                var tex = new Texture2D(512, 512, TextureFormat.RGBA32, false);
                tex.ReadPixels(new Rect(0, 0, 512, 512), 0, 0);
                tex.Apply();
                File.WriteAllBytes(outputPath, tex.EncodeToPNG());

                UnityEngine.Object.DestroyImmediate(quad);
                UnityEngine.Object.DestroyImmediate(cameraGO);
                RenderTexture.active = null;
                UnityEngine.Object.DestroyImmediate(rt);
                return true;
            }
            catch { return false; }
        }

        private List<MaterialPropertyInfo> GetMaterialProperties(Material mat)
        {
            var list = new List<MaterialPropertyInfo>();
            if (mat == null) return list;
            var shader = mat.shader;
            int count = ShaderUtil.GetPropertyCount(shader);
            for (int i = 0; i < count; i++)
            {
                var propType = ShaderUtil.GetPropertyType(shader, i);
                string name  = ShaderUtil.GetPropertyName(shader, i);
                string type  = propType.ToString().ToLower();
                string val   = "";
                switch (propType)
                {
                    case ShaderUtil.ShaderPropertyType.Float:
                    case ShaderUtil.ShaderPropertyType.Range:
                        val = mat.GetFloat(name).ToString("F3"); break;
                    case ShaderUtil.ShaderPropertyType.Color:
                        val = mat.GetColor(name).ToString(); break;
                    case ShaderUtil.ShaderPropertyType.Vector:
                        val = mat.GetVector(name).ToString(); break;
                    default: continue;
                }
                list.Add(new MaterialPropertyInfo { name = name, type = type, currentValue = val });
            }
            return list;
        }

        private void ApplyMaterialChange(Material mat, MaterialPropertyChange change)
        {
            if (mat == null || change == null) return;
            switch (change.property_type?.ToLower())
            {
                case "float": case "range":
                    if (mat.HasProperty(change.property_name))
                        mat.SetFloat(change.property_name, change.float_value);
                    break;
                case "color":
                    if (mat.HasProperty(change.property_name))
                        mat.SetColor(change.property_name, new Color(change.r, change.g, change.b, change.a));
                    break;
                case "vector":
                    if (mat.HasProperty(change.property_name))
                        mat.SetVector(change.property_name, new Vector4(change.x, change.y, change.z, change.w));
                    break;
            }
        }

        // ══════════════════════════════════════════════════════════════════════
        //  UTILITIES
        // ══════════════════════════════════════════════════════════════════════

        private void AppendStatus(string msg)
        {
            _statusLog += msg + "\n";
            // Keep log from growing too large in the UI
            if (_statusLog.Length > 8000)
                _statusLog = "...(truncated)\n" + _statusLog.Substring(_statusLog.Length - 6000);
            Repaint();
        }

        private void EnsureResultsFolder()
        {
            Directory.CreateDirectory(RESULTS_FOLDER);
            AssetDatabase.Refresh();
        }

        private static string DetermineComplexity(string setName)
        {
            string lower = setName.ToLower();
            if (lower.Contains("simple")) return "Simple";
            if (lower.Contains("complex")) return "Complex";
            return "Unknown";
        }

        private static string Truncate(string s, int max) =>
            string.IsNullOrEmpty(s) ? ""
            : s.Length <= max ? s
            : s.Substring(0, max) + "…";

        private static readonly string[] k_Providers =
        {
            "gemini-3-pro-preview",
            "gemini-3.1-pro-preview",
            "gpt-5.4",
            "claude-sonnet-4-6",
            "kimi-k2.6",
        };

        private static string DrawProviderField(string label, string current)
        {
            int idx = System.Array.IndexOf(k_Providers, current);
            if (idx < 0) idx = 0;
            EditorGUILayout.BeginHorizontal();
            EditorGUILayout.LabelField(label, GUILayout.Width(200));
            idx = EditorGUILayout.Popup(idx, k_Providers, GUILayout.Width(180));
            EditorGUILayout.EndHorizontal();
            return k_Providers[idx];
        }

        private static string StripMarkdown(string text)
        {
            if (string.IsNullOrEmpty(text)) return text;
            var m = System.Text.RegularExpressions.Regex.Match(
                text, @"```(?:json)?\s*([\s\S]*?)```",
                System.Text.RegularExpressions.RegexOptions.Multiline);
            return m.Success ? m.Groups[1].Value.Trim() : text.Trim();
        }
    }

    // ══════════════════════════════════════════════════════════════════════════
    //  HELPER CONFIG CLASSES  (for deserialising the JSON config files)
    // ══════════════════════════════════════════════════════════════════════════

    [Serializable]
    internal class EditRequestConfig
    {
        public string shape_prompt;
        public string edit_request;
    }

    [Serializable]
    internal class AnimationRequestConfig
    {
        public string shape_prompt;
        public string animation_request;
    }

    [Serializable]
    internal class ImageRequestConfig
    {
        public string image_path;      // relative asset path, e.g. "Assets/Experiment/ReferenceImages/coin.png"
        public string editable_hints;  // free-text hint for adjustable parameters
    }
}
