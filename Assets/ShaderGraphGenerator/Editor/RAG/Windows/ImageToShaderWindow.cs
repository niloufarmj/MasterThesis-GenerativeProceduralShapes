using System.IO;
using System.Threading.Tasks;
using UnityEditor;
using UnityEngine;
using ShaderGraphGenerator.KnowledgeBase;

namespace ShaderGraphGenerator.RAG
{
    /// <summary>
    /// Tool 2.8 — Image-to-Shader Generator
    ///
    /// Flow:
    ///   1. User drops a reference image + optionally writes which parts should be editable.
    ///   2. GPT-4o Vision describes the image (shapes, colors, layout).
    ///   3. Description is decomposed into components and matched against the KB.
    ///   4. Gemini Vision receives BOTH the text prompt AND the original image → generates HLSL.
    ///   5. ShaderGraph + Material built, preview rendered.
    ///   6. VLM compares reference image vs rendered preview (up to 2 iterations).
    ///   7. Human reviews result, optional KB ingest.
    /// </summary>
    public class ImageToShaderWindow : EditorWindow
    {
        // ─── constants ────────────────────────────────────────────────────────
        private const int    MAX_VLM_ITERATIONS   = 2;
        private const int    MAX_HUMAN_ITERATIONS = 3;
        private const int    KB_THRESHOLD         = 8;
        private const int    HUMAN_REJECT_BELOW   = 7;
        private const string KB_PATH = "Assets/ShaderGraphGenerator/KnowledgeBase/shape_metadata.json";

        // ─── state machine ────────────────────────────────────────────────────
        private enum State { Idle, Running, AwaitingReview, Done }
        private State state = State.Idle;

        // ─── persistent fields ────────────────────────────────────────────────
        private ShaderGraphGeneratorConfig config;
        private ShapeKnowledgeBase         knowledgeBase;

        // Idle inputs
        private Texture2D referenceImage;         // drag-and-drop in inspector
        private string    editableHints = "Describe which parts you want as editable properties (optional).\nE.g. \"body color, hat color, scarf stripe count\"";

        // Pipeline outputs
        private ImageToShaderResult pipelineResult;
        private Texture2D           refTex;       // loaded reference (display)
        private Texture2D           previewTex;   // loaded rendered preview (display)

        // Review state
        private int    humanScore     = 8;
        private string humanComment   = "";
        private int    humanIteration = 1;
        private bool   addedToLibrary;
        private string statusMessage  = "";
        private string outcomeMessage = "";

        private Vector2 scrollPos;

        // ─── menu ─────────────────────────────────────────────────────────────
        [MenuItem("Tools/ShaderGraph Generator/8. Image to Shader")]
        public static void ShowWindow()
        {
            var w = GetWindow<ImageToShaderWindow>("8. Image to Shader");
            w.minSize = new Vector2(1000, 720);
        }

        // ─── lifecycle ────────────────────────────────────────────────────────
        private void OnEnable() { LoadConfig(); LoadKnowledgeBase(); }

        private void LoadConfig()
        {
            string[] guids = AssetDatabase.FindAssets("t:ShaderGraphGeneratorConfig");
            if (guids.Length > 0)
                config = AssetDatabase.LoadAssetAtPath<ShaderGraphGeneratorConfig>(
                    AssetDatabase.GUIDToAssetPath(guids[0]));
        }

        private void LoadKnowledgeBase()
        {
            if (!File.Exists(KB_PATH)) return;
            knowledgeBase = Newtonsoft.Json.JsonConvert.DeserializeObject<ShapeKnowledgeBase>(
                File.ReadAllText(KB_PATH));
        }

        // ─── OnGUI ────────────────────────────────────────────────────────────
        private void OnGUI()
        {
            DrawHeader();
            EditorGUILayout.Space(6);

            if (config == null || knowledgeBase == null)
            {
                EditorGUILayout.HelpBox("Config or Knowledge Base not found!", MessageType.Error);
                return;
            }

            scrollPos = EditorGUILayout.BeginScrollView(scrollPos);
            switch (state)
            {
                case State.Idle:           DrawIdle();    break;
                case State.Running:        DrawRunning(); break;
                case State.AwaitingReview: DrawReview();  break;
                case State.Done:           DrawDone();    break;
            }
            EditorGUILayout.EndScrollView();
        }

        // ─── header ───────────────────────────────────────────────────────────
        private void DrawHeader()
        {
            GUILayout.Label("Image → Shader Generator", EditorStyles.boldLabel);
            GUILayout.Label(
                "Drop a reference image → describe editable parts → AI recreates it as a procedural shader material.",
                EditorStyles.wordWrappedMiniLabel);
            if (knowledgeBase != null)
                GUILayout.Label($"Library: {knowledgeBase.totalShapes} shapes", EditorStyles.miniLabel);
        }

        // ─── idle ─────────────────────────────────────────────────────────────
        private void DrawIdle()
        {
            // ── Reference image drop ──────────────────────────────────────────
            EditorGUILayout.LabelField("Reference Image:", EditorStyles.boldLabel);
            EditorGUILayout.LabelField(
                "Drop a PNG/JPG image. The AI will recreate it as a procedural HLSL shader material.",
                EditorStyles.wordWrappedMiniLabel);

            var prevRef = referenceImage;
            referenceImage = (Texture2D)EditorGUILayout.ObjectField(
                referenceImage, typeof(Texture2D), allowSceneObjects: false,
                GUILayout.Height(100));

            if (referenceImage != prevRef)
            {
                refTex = referenceImage; // direct display ref
            }

            // Show the reference image as a large preview
            if (refTex != null)
            {
                float aspect = (float)refTex.width / refTex.height;
                float dispW  = Mathf.Min(300f, position.width * 0.4f);
                float dispH  = dispW / aspect;
                GUILayout.Label(refTex, GUILayout.Width(dispW), GUILayout.Height(dispH));
            }

            EditorGUILayout.Space(10);

            // ── Editable hints ────────────────────────────────────────────────
            EditorGUILayout.LabelField("Editable Properties Hint (optional):", EditorStyles.boldLabel);
            EditorGUILayout.LabelField(
                "Tell the AI which visual aspects should become editable material properties (colors, sizes, etc.).",
                EditorStyles.wordWrappedMiniLabel);
            editableHints = EditorGUILayout.TextArea(editableHints, GUILayout.Height(65));

            EditorGUILayout.Space(10);

            bool ready = referenceImage != null;
            GUI.enabled = ready;

            if (GUILayout.Button("Generate Shader from Image", GUILayout.Height(46)))
            {
                humanIteration = 1;
                _ = RunPipelineAsync();
            }

            GUI.enabled = true;

            if (!ready)
                EditorGUILayout.HelpBox("Please assign a reference image.", MessageType.Warning);
        }

        // ─── running ──────────────────────────────────────────────────────────
        private void DrawRunning()
        {
            EditorGUILayout.HelpBox(statusMessage.Length > 0 ? statusMessage : "Pipeline running…", MessageType.Info);
            GUILayout.Label("Please wait — this may take 30–90 seconds.", EditorStyles.centeredGreyMiniLabel);
        }

        // ─── review ───────────────────────────────────────────────────────────
        private void DrawReview()
        {
            if (pipelineResult == null) return;

            GUILayout.Label("Pipeline Result", EditorStyles.boldLabel);
            EditorGUILayout.LabelField($"Generated shape:  {pipelineResult.fileName}");
            EditorGUILayout.LabelField($"VLM score:  {pipelineResult.vlmScore}/10");

            EditorGUILayout.Space(4);
            GUILayout.Label("VLM feedback:", EditorStyles.boldLabel);
            EditorGUILayout.LabelField(pipelineResult.vlmFeedback ?? "—", EditorStyles.wordWrappedLabel);

            EditorGUILayout.Space(10);

            // ── Side-by-side: reference vs preview ───────────────────────────
            float halfW = (position.width - 40f) * 0.5f;
            float imgH  = halfW;

            EditorGUILayout.BeginHorizontal();

            EditorGUILayout.BeginVertical();
            GUILayout.Label("REFERENCE", EditorStyles.boldLabel);
            if (refTex != null)
                GUILayout.Label(refTex, GUILayout.Width(halfW), GUILayout.Height(imgH));
            else
                EditorGUILayout.LabelField("(not available)");
            EditorGUILayout.EndVertical();

            EditorGUILayout.BeginVertical();
            GUILayout.Label("RENDERED PREVIEW", EditorStyles.boldLabel);
            if (previewTex != null)
                GUILayout.Label(previewTex, GUILayout.Width(halfW), GUILayout.Height(imgH));
            else
                EditorGUILayout.LabelField("(not available)");
            EditorGUILayout.EndVertical();

            EditorGUILayout.EndHorizontal();

            // ── Visual description toggle ─────────────────────────────────────
            EditorGUILayout.Space(6);
            if (GUILayout.Button("Show / Hide Visual Description", GUILayout.Height(22)))
                _showDescription = !_showDescription;

            if (_showDescription && !string.IsNullOrEmpty(pipelineResult.visualDescription))
            {
                EditorGUILayout.TextArea(pipelineResult.visualDescription, GUILayout.Height(120));
            }

            EditorGUILayout.Space(10);

            // ── Human rating ──────────────────────────────────────────────────
            GUILayout.Label($"Your Rating  (attempt {humanIteration}/{MAX_HUMAN_ITERATIONS})", EditorStyles.boldLabel);
            GUILayout.Label("Rate 0–10. Score < 7 triggers a retry. Both VLM ≥ 8 AND human ≥ 8 adds to library.",
                EditorStyles.wordWrappedMiniLabel);

            EditorGUILayout.BeginHorizontal();
            GUILayout.Label("Score:", GUILayout.Width(50));
            humanScore = Mathf.RoundToInt(GUILayout.HorizontalSlider(humanScore, 0, 10, GUILayout.Width(300)));
            GUILayout.Label(humanScore.ToString(), GUILayout.Width(30));
            EditorGUILayout.EndHorizontal();

            EditorGUILayout.LabelField("Comment / feedback for retry (optional):");
            humanComment = EditorGUILayout.TextField(humanComment);

            EditorGUILayout.Space(8);

            EditorGUILayout.BeginHorizontal();

            // Accept
            bool canAccept = humanScore >= HUMAN_REJECT_BELOW;
            GUI.enabled = canAccept;
            if (GUILayout.Button($"Accept  (score {humanScore})", GUILayout.Height(34)))
                HandleHumanAccept();
            GUI.enabled = true;

            // Retry
            bool canRetry = humanIteration < MAX_HUMAN_ITERATIONS;
            GUI.enabled = canRetry;
            if (GUILayout.Button("Retry with Feedback", GUILayout.Height(34)))
                _ = RetryPipelineAsync();
            GUI.enabled = true;

            // Discard
            if (GUILayout.Button("Discard", GUILayout.Height(34)))
                ResetToIdle();

            EditorGUILayout.EndHorizontal();

            if (!canAccept)
                EditorGUILayout.HelpBox($"Score must be ≥ {HUMAN_REJECT_BELOW} to accept.", MessageType.Warning);
        }

        private bool _showDescription = false;

        // ─── done ─────────────────────────────────────────────────────────────
        private void DrawDone()
        {
            GUILayout.Label("✓ Done", EditorStyles.boldLabel);
            EditorGUILayout.LabelField(outcomeMessage, EditorStyles.wordWrappedLabel);

            if (pipelineResult?.materialPath != null)
            {
                EditorGUILayout.Space(4);
                if (GUILayout.Button("Select Material in Project", GUILayout.Height(28)))
                {
                    var mat = AssetDatabase.LoadAssetAtPath<Material>(pipelineResult.materialPath);
                    if (mat != null) Selection.activeObject = mat;
                }
            }

            EditorGUILayout.Space(10);
            if (GUILayout.Button("Start Over", GUILayout.Height(34)))
                ResetToIdle();
        }

        // ─── pipeline execution ───────────────────────────────────────────────

        private async Task RunPipelineAsync(string extraFeedback = null)
        {
            state         = State.Running;
            statusMessage = "Step 1/4: GPT-4o Vision describing reference image…";
            Repaint();

            // Resolve absolute path from Unity asset
            string assetPath = AssetDatabase.GetAssetPath(referenceImage);
            string projectRoot = Path.GetDirectoryName(Application.dataPath);
            string absPath = string.IsNullOrEmpty(assetPath)
                ? null
                : Path.GetFullPath(Path.Combine(projectRoot, assetPath));

            if (string.IsNullOrEmpty(absPath) || !File.Exists(absPath))
            {
                statusMessage = "Could not resolve image path on disk.";
                EditorUtility.DisplayDialog("Error", statusMessage, "OK");
                state = State.Idle;
                Repaint();
                return;
            }

            string hints = editableHints;
            if (!string.IsNullOrWhiteSpace(extraFeedback))
                hints += "\n\n[Previous attempt feedback]: " + extraFeedback;

            pipelineResult = await ImageToShaderPipelineManager.RunPipelineAsync(
                absPath, hints, knowledgeBase, config,
                maxVlmIterations: MAX_VLM_ITERATIONS);

            // Load textures for display
            if (!string.IsNullOrEmpty(pipelineResult.previewImagePath) &&
                File.Exists(pipelineResult.previewImagePath))
            {
                previewTex = LoadTexFromDisk(pipelineResult.previewImagePath);
            }

            if (!string.IsNullOrEmpty(pipelineResult.errorMessage) && pipelineResult.materialPath == null)
            {
                EditorUtility.DisplayDialog("Pipeline Error", pipelineResult.errorMessage, "OK");
                state = State.Idle;
            }
            else
            {
                state = State.AwaitingReview;
            }

            Repaint();
        }

        private async Task RetryPipelineAsync()
        {
            humanIteration++;
            string feedback = humanComment;
            humanComment    = "";
            await RunPipelineAsync(feedback);
        }

        private void HandleHumanAccept()
        {
            bool addToKB = pipelineResult.vlmScore >= KB_THRESHOLD && humanScore >= KB_THRESHOLD;

            if (addToKB && !string.IsNullOrEmpty(pipelineResult.hlslCode))
            {
                // Use the visual description as the original prompt for KB storage
                var entry = new ShapeMetadata
                {
                    fileName         = pipelineResult.fileName,
                    filePath         = Path.Combine("Assets/ShaderGraphs/RAG_Generated", pipelineResult.fileName + ".hlsl"),
                    originalPrompt   = pipelineResult.visualDescription?.Substring(0, System.Math.Min(200, pipelineResult.visualDescription?.Length ?? 0)) ?? "image-to-shader",
                    visualDescription = pipelineResult.visualDescription ?? "Generated from image reference",
                    dateAdded        = System.DateTime.Now.ToString("yyyy-MM-dd")
                };

                if (knowledgeBase == null)
                    knowledgeBase = new ShapeKnowledgeBase();
                knowledgeBase.shapes.Add(entry);
                knowledgeBase.totalShapes = knowledgeBase.shapes.Count;

                File.WriteAllText(KB_PATH, Newtonsoft.Json.JsonConvert.SerializeObject(knowledgeBase, Newtonsoft.Json.Formatting.Indented));
                AssetDatabase.Refresh();

                addedToLibrary = true;
                outcomeMessage = $"✓ '{pipelineResult.fileName}' accepted and added to the shape library (VLM: {pipelineResult.vlmScore}/10, Human: {humanScore}/10).";
            }
            else
            {
                addedToLibrary = false;
                outcomeMessage = $"✓ '{pipelineResult.fileName}' accepted (not added to library — one or both scores below {KB_THRESHOLD}).";
                if (pipelineResult.vlmScore < KB_THRESHOLD)
                    outcomeMessage += $"\n  VLM score was {pipelineResult.vlmScore}/10.";
                if (humanScore < KB_THRESHOLD)
                    outcomeMessage += $"\n  Your score was {humanScore}/10.";
            }

            state = State.Done;
            Repaint();
        }

        private void ResetToIdle()
        {
            state          = State.Idle;
            pipelineResult = null;
            previewTex     = null;
            humanScore     = 8;
            humanComment   = "";
            humanIteration = 1;
            outcomeMessage = "";
            statusMessage  = "";
            _showDescription = false;
            Repaint();
        }

        // ─── helpers ──────────────────────────────────────────────────────────

        private static Texture2D LoadTexFromDisk(string absPath)
        {
            if (!File.Exists(absPath)) return null;
            var tex = new Texture2D(2, 2);
            tex.LoadImage(File.ReadAllBytes(absPath));
            return tex;
        }
    }
}