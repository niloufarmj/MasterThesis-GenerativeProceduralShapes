using System.IO;
using System.Threading.Tasks;
using UnityEditor;
using UnityEngine;
using ShaderGraphGenerator.KnowledgeBase;

namespace ShaderGraphGenerator.RAG
{
    /// <summary>
    /// Tool 2.6 — RAG Pipeline with Human-in-the-Loop Review.
    ///
    /// Flow:
    ///   1. Run the RAG pipeline (up to 4 VLM-guided iterations).
    ///   2. Display the final preview image + VLM score/feedback.
    ///   3. Ask the user to rate the shape 0–10.
    ///   4. Only add to the knowledge base if BOTH scores are >= 8.
    /// </summary>
    public class RAGHumanReviewWindow : EditorWindow
    {
        // ─── constants ────────────────────────────────────────────────────────
        private const int   MAX_ITERATIONS   = 4;
        private const int   KB_THRESHOLD     = 8;  // both VLM and human must meet this
        private const string KB_PATH         = "Assets/ShaderGraphGenerator/KnowledgeBase/shape_metadata.json";

        // ─── window state machine ─────────────────────────────────────────────
        private enum State { Idle, Running, AwaitingReview, Ingesting, Done }
        private State state = State.Idle;

        // ─── persisted across states ──────────────────────────────────────────
        private ShaderGraphGeneratorConfig config;
        private ShapeKnowledgeBase         knowledgeBase;

        private string userRequest   = "a cartoon sitting cat with rounded body, pointed ears, whiskers, collar, stripes, and a curved tail";
        private string statusMessage = "";

        // populated after pipeline finishes
        private RAGPipelineResult pipelineResult;
        private Texture2D         previewTex;

        // human review
        private int    humanScore   = 8;
        private string humanComment = "";

        // outcome
        private bool  addedToLibrary;
        private string outcomeMessage = "";

        private Vector2 scrollPos;

        // ─── menu ─────────────────────────────────────────────────────────────
        [MenuItem("Tools/ShaderGraph Generator/6 RAG Pipeline + Human Review")]
        public static void ShowWindow()
        {
            var w = GetWindow<RAGHumanReviewWindow>("6 RAG + Human Review");
            w.minSize = new Vector2(880, 680);
        }

        // ─── lifecycle ────────────────────────────────────────────────────────
        private void OnEnable()
        {
            LoadConfig();
            LoadKnowledgeBase();
        }

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

        // ─── GUI ──────────────────────────────────────────────────────────────
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
                case State.Idle:        DrawIdle();         break;
                case State.Running:     DrawRunning();      break;
                case State.AwaitingReview: DrawReview();    break;
                case State.Ingesting:   DrawIngesting();    break;
                case State.Done:        DrawDone();         break;
            }

            EditorGUILayout.EndScrollView();
        }

        // ── header ─────────────────────────────────────────────────────────────
        private void DrawHeader()
        {
            GUILayout.Label("RAG Pipeline + Human Review", EditorStyles.boldLabel);
            GUILayout.Label(
                "Decompose → Retrieve → Generate → Evaluate (up to 4 iterations) → Human Review → Library",
                EditorStyles.wordWrappedMiniLabel);
            if (knowledgeBase != null)
                GUILayout.Label($"Library: {knowledgeBase.totalShapes} shapes", EditorStyles.miniLabel);
        }

        // ── idle ───────────────────────────────────────────────────────────────
        private void DrawIdle()
        {
            EditorGUILayout.LabelField("User Request:", EditorStyles.boldLabel);
            userRequest = EditorGUILayout.TextArea(userRequest, GUILayout.Height(70));
            EditorGUILayout.Space(8);

            if (GUILayout.Button("Run Pipeline", GUILayout.Height(42)))
                _ = RunPipelineAsync();
        }

        // ── running ────────────────────────────────────────────────────────────
        private void DrawRunning()
        {
            EditorGUILayout.HelpBox(statusMessage, MessageType.Info);
            GUILayout.Label("Processing — please wait…", EditorStyles.boldLabel);
            Repaint();
        }

        // ── awaiting human review ──────────────────────────────────────────────
        private void DrawReview()
        {
            // ── VLM result ──────────────────────────────────────────────────
            EditorGUILayout.LabelField("Pipeline Result", EditorStyles.boldLabel);
            EditorGUILayout.BeginVertical(EditorStyles.helpBox);

            EditorGUILayout.LabelField($"Shape:      {pipelineResult.fileName}");
            EditorGUILayout.LabelField($"VLM Score:  {pipelineResult.vmlScore}/10");
            EditorGUILayout.Space(3);
            EditorGUILayout.LabelField("VLM Feedback:", EditorStyles.miniBoldLabel);
            EditorGUILayout.LabelField(pipelineResult.vmlFeedback ?? "—",
                EditorStyles.wordWrappedLabel);

            EditorGUILayout.EndVertical();

            // ── preview image ───────────────────────────────────────────────
            EditorGUILayout.Space(8);
            if (previewTex != null)
            {
                EditorGUILayout.LabelField("Preview:", EditorStyles.boldLabel);
                float size = Mathf.Min(position.width - 30f, 380f);
                var rect = GUILayoutUtility.GetRect(size, size,
                    GUILayout.Width(size), GUILayout.Height(size));
                GUI.DrawTexture(rect, previewTex, ScaleMode.ScaleToFit);
            }
            else
            {
                EditorGUILayout.HelpBox("Preview image not available.", MessageType.Warning);
            }

            // ── human rating ────────────────────────────────────────────────
            EditorGUILayout.Space(10);
            EditorGUILayout.LabelField("Your Rating", EditorStyles.boldLabel);

            EditorGUILayout.BeginVertical(EditorStyles.helpBox);

            EditorGUILayout.LabelField(
                "Rate the rendered result from 0 (unusable) to 10 (perfect).",
                EditorStyles.wordWrappedMiniLabel);

            EditorGUILayout.Space(4);

            // Slider + integer field side by side
            EditorGUILayout.BeginHorizontal();
            GUILayout.Label("Score:", GUILayout.Width(48));
            humanScore = EditorGUILayout.IntSlider(humanScore, 0, 10);
            EditorGUILayout.EndHorizontal();

            EditorGUILayout.Space(4);
            EditorGUILayout.LabelField("Optional comment:", EditorStyles.miniBoldLabel);
            humanComment = EditorGUILayout.TextArea(humanComment, GUILayout.Height(50));

            EditorGUILayout.EndVertical();

            // ── threshold hint ───────────────────────────────────────────────
            EditorGUILayout.Space(6);
            bool vlmPass   = pipelineResult.vmlScore >= KB_THRESHOLD;
            bool humanPass = humanScore >= KB_THRESHOLD;

            string hint = vlmPass && humanPass
                ? $"✓ Both VLM ({pipelineResult.vmlScore}) and your score ({humanScore}) meet the threshold ({KB_THRESHOLD}). Shape will be added to the library."
                : $"One or both scores are below {KB_THRESHOLD}. Shape will NOT be added to the library.\n" +
                  $"  VLM score: {pipelineResult.vmlScore}/10  {(vlmPass ? "✓" : "✗")}\n" +
                  $"  Your score: {humanScore}/10  {(humanPass ? "✓" : "✗")}";

            EditorGUILayout.HelpBox(hint, vlmPass && humanPass ? MessageType.None : MessageType.Warning);

            // ── action buttons ───────────────────────────────────────────────
            EditorGUILayout.Space(8);
            EditorGUILayout.BeginHorizontal();

            if (GUILayout.Button("Submit Review", GUILayout.Height(40)))
                _ = SubmitReviewAsync();

            GUI.backgroundColor = new Color(1f, 0.45f, 0.45f);
            if (GUILayout.Button("Discard", GUILayout.Width(120), GUILayout.Height(40)))
            {
                outcomeMessage = "Shape discarded — not added to library.";
                state = State.Done;
                Repaint();
            }
            GUI.backgroundColor = Color.white;

            EditorGUILayout.EndHorizontal();
        }

        // ── ingesting ──────────────────────────────────────────────────────────
        private void DrawIngesting()
        {
            EditorGUILayout.HelpBox(statusMessage, MessageType.Info);
            GUILayout.Label("Adding to knowledge base — please wait…", EditorStyles.boldLabel);
            Repaint();
        }

        // ── done ───────────────────────────────────────────────────────────────
        private void DrawDone()
        {
            EditorGUILayout.HelpBox(outcomeMessage,
                addedToLibrary ? MessageType.None : MessageType.Info);

            if (addedToLibrary && knowledgeBase != null)
                EditorGUILayout.LabelField(
                    $"Library now has {knowledgeBase.totalShapes} shapes.",
                    EditorStyles.miniLabel);

            if (previewTex != null)
            {
                EditorGUILayout.Space(6);
                float size = Mathf.Min(position.width - 30f, 300f);
                var rect = GUILayoutUtility.GetRect(size, size,
                    GUILayout.Width(size), GUILayout.Height(size));
                GUI.DrawTexture(rect, previewTex, ScaleMode.ScaleToFit);
            }

            EditorGUILayout.Space(10);
            if (GUILayout.Button("Run Again", GUILayout.Height(36)))
            {
                pipelineResult = null;
                previewTex     = null;
                humanScore     = 8;
                humanComment   = "";
                outcomeMessage = "";
                addedToLibrary = false;
                state          = State.Idle;
                Repaint();
            }
        }

        // ─── pipeline async ───────────────────────────────────────────────────
        private async Task RunPipelineAsync()
        {
            state         = State.Running;
            statusMessage = "Starting RAG pipeline…";
            Repaint();

            pipelineResult = await RAGPipelineManager.RunCompletePipelineAsync(
                userRequest,
                knowledgeBase,
                config,
                maxIterations: MAX_ITERATIONS);

            if (pipelineResult == null || !string.IsNullOrEmpty(pipelineResult.errorMessage))
            {
                outcomeMessage = $"Pipeline failed: {pipelineResult?.errorMessage ?? "unknown error"}";
                state = State.Done;
                Repaint();
                return;
            }

            // Load preview texture
            previewTex = null;
            if (!string.IsNullOrEmpty(pipelineResult.previewImagePath)
                && File.Exists(pipelineResult.previewImagePath))
            {
                // Force-reimport so AssetDatabase knows about it
                AssetDatabase.ImportAsset(pipelineResult.previewImagePath);
                previewTex = AssetDatabase.LoadAssetAtPath<Texture2D>(pipelineResult.previewImagePath);

                // Fallback: raw bytes
                if (previewTex == null)
                {
                    byte[] bytes = File.ReadAllBytes(pipelineResult.previewImagePath);
                    previewTex = new Texture2D(2, 2);
                    previewTex.LoadImage(bytes);
                }
            }

            // Default human score to match the VLM score as a starting point
            humanScore = pipelineResult.vmlScore;

            state         = State.AwaitingReview;
            statusMessage = "";
            Repaint();
        }

        // ─── submit review async ──────────────────────────────────────────────
        private async Task SubmitReviewAsync()
        {
            bool vlmPass   = pipelineResult.vmlScore >= KB_THRESHOLD;
            bool humanPass = humanScore >= KB_THRESHOLD;

            if (!vlmPass || !humanPass)
            {
                // Scores don't meet threshold — skip ingestion
                outcomeMessage =
                    $"Not added to library.\n" +
                    $"VLM score: {pipelineResult.vmlScore}/10  {(vlmPass ? "✓" : "✗")}\n" +
                    $"Your score: {humanScore}/10  {(humanPass ? "✓" : "✗")}\n" +
                    $"Both scores must be ≥ {KB_THRESHOLD} to add to the library.";
                addedToLibrary = false;
                state          = State.Done;
                Repaint();
                return;
            }

            state         = State.Ingesting;
            statusMessage = "Generating visual description and updating knowledge base…";
            Repaint();

            // Use the higher of the two scores as the stored verificationScore
            int storedScore = Mathf.Max(pipelineResult.vmlScore, humanScore);

            // Enrich the fallback description with the human comment
            string feedback = pipelineResult.vmlFeedback ?? "";
            if (!string.IsNullOrEmpty(humanComment))
                feedback += $" Human reviewer: {humanComment}";

            // Use AddToLibraryAsync directly — threshold was already checked above.
            bool ok = await KnowledgeBaseUpdater.AddToLibraryAsync(
                hlslPath:     System.IO.Path.Combine("Assets/ShaderGraphs/RAG_Generated", $"{pipelineResult.fileName}.hlsl"),
                imagePath:    pipelineResult.previewImagePath,
                userPrompt:   pipelineResult.userRequest,
                geminiKey:    config.geminiKey,
                openAIKey:    config.openAIKey,
                verifyScore:  storedScore,
                fallbackDesc: feedback);

            addedToLibrary = ok;
            LoadKnowledgeBase(); // refresh count

            outcomeMessage = ok
                ? $"✓ '{pipelineResult.fileName}' added to the knowledge base.\n" +
                  $"VLM score: {pipelineResult.vmlScore}/10 · Your score: {humanScore}/10 · Stored: {storedScore}/10"
                : "Knowledge base update failed — see Console for details.";

            state = State.Done;
            Repaint();
        }
    }
}
