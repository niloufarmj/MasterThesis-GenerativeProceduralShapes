using System.IO;
using System.Threading.Tasks;
using UnityEditor;
using UnityEngine;
using ShaderGraphGenerator.KnowledgeBase;

namespace ShaderGraphGenerator.RAG
{
    /// <summary>
    /// Tool 2.7 — RAG-powered HLSL Updater with Human Review.
    ///
    /// Flow:
    ///   1. User picks a Material whose ShaderGraph uses an HLSL Custom Function node.
    ///   2. Pipeline renders a BEFORE screenshot using the material's live property values,
    ///      then extracts the HLSL and current property values from the material.
    ///   3. LLM generates an updated HLSL, instructed to preserve all property values
    ///      except those changed by the update request.
    ///   4. Updated material is rendered as the AFTER screenshot.
    ///   5. VLM validates (up to 4 iterations). Shows BEFORE + AFTER side by side.
    ///   6. User rates 0-10:
    ///      - score < 7  → retry pipeline with feedback (up to 4 human attempts)
    ///      - score 7    → accept, skip KB
    ///      - both VLM ≥ 8 AND human ≥ 8 → add to library
    /// </summary>
    public class RAGUpdateWindow : EditorWindow
    {
        // ─── constants ────────────────────────────────────────────────────────
        private const int    MAX_VLM_ITERATIONS   = 4;
        private const int    MAX_HUMAN_ITERATIONS = 4;
        private const int    KB_THRESHOLD         = 8;
        private const int    HUMAN_REJECT_BELOW   = 7;
        private const string KB_PATH = "Assets/ShaderGraphGenerator/KnowledgeBase/shape_metadata.json";

        // ─── state machine ────────────────────────────────────────────────────
        private enum State { Idle, Running, AwaitingReview, Ingesting, Done }
        private State state = State.Idle;

        // ─── persistent fields ────────────────────────────────────────────────
        private ShaderGraphGeneratorConfig config;
        private ShapeKnowledgeBase         knowledgeBase;

        // Idle inputs
        private Material originalMaterial;
        private string   updateRequest = "add horizontal stripes on the scarf";

        // Pipeline outputs
        private HLSLUpdateResult pipelineResult;
        private Texture2D        beforeTex;
        private Texture2D        afterTex;

        // Review state
        private int    humanScore       = 8;
        private string humanComment     = "";
        private int    humanIteration   = 1;
        private string prevUserFeedback = "";

        // Done state
        private bool   addedToLibrary;
        private string outcomeMessage = "";
        private string statusMessage  = "";

        private Vector2 scrollPos;

        // ─── menu ─────────────────────────────────────────────────────────────
        [MenuItem("Tools/ShaderGraph Generator/7 RAG HLSL Updater + Human Review")]
        public static void ShowWindow()
        {
            var w = GetWindow<RAGUpdateWindow>("7 RAG HLSL Updater");
            w.minSize = new Vector2(1000, 700);
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
                case State.Idle:           DrawIdle();      break;
                case State.Running:        DrawRunning();   break;
                case State.AwaitingReview: DrawReview();    break;
                case State.Ingesting:      DrawIngesting(); break;
                case State.Done:           DrawDone();      break;
            }
            EditorGUILayout.EndScrollView();
        }

        // ─── header ───────────────────────────────────────────────────────────
        private void DrawHeader()
        {
            GUILayout.Label("RAG HLSL Updater + Human Review", EditorStyles.boldLabel);
            GUILayout.Label(
                "Pick a Material → describe what to change → VLM validates → you review → optionally saved to library.",
                EditorStyles.wordWrappedMiniLabel);
            if (knowledgeBase != null)
                GUILayout.Label($"Library: {knowledgeBase.totalShapes} shapes", EditorStyles.miniLabel);
        }

        // ─── idle ─────────────────────────────────────────────────────────────
        private void DrawIdle()
        {
            // Material picker
            EditorGUILayout.LabelField("Source Material:", EditorStyles.boldLabel);
            EditorGUILayout.LabelField(
                "Pick a material whose shader was generated by this tool (ShaderGraph + HLSL Custom Function).",
                EditorStyles.wordWrappedMiniLabel);

            originalMaterial = (Material)EditorGUILayout.ObjectField(
                originalMaterial, typeof(Material), allowSceneObjects: false);

            if (originalMaterial != null)
            {
                string shaderName = originalMaterial.shader != null
                    ? originalMaterial.shader.name : "—";
                EditorGUILayout.LabelField($"Shader: {shaderName}", EditorStyles.miniLabel);
            }

            EditorGUILayout.Space(8);

            // Update request
            EditorGUILayout.LabelField("Update Request:", EditorStyles.boldLabel);
            EditorGUILayout.LabelField(
                "Describe specifically what you want changed (e.g. \"add diagonal stripes on the hat\").",
                EditorStyles.wordWrappedMiniLabel);
            updateRequest = EditorGUILayout.TextArea(updateRequest, GUILayout.Height(70));

            EditorGUILayout.Space(8);

            bool ready = originalMaterial != null && !string.IsNullOrWhiteSpace(updateRequest);

            GUI.enabled = ready;
            if (GUILayout.Button("Run Update Pipeline", GUILayout.Height(42)))
            {
                humanIteration   = 1;
                prevUserFeedback = "";
                _ = RunPipelineAsync(prevUserFeedback);
            }
            GUI.enabled = true;

            if (!ready)
            {
                string warn = "";
                if (originalMaterial == null)
                    warn += "• A Material is required.\n";
                if (string.IsNullOrWhiteSpace(updateRequest))
                    warn += "• An update request is required.";
                if (!string.IsNullOrEmpty(warn))
                    EditorGUILayout.HelpBox(warn.TrimEnd(), MessageType.Warning);
            }
        }

        // ─── running ──────────────────────────────────────────────────────────
        private void DrawRunning()
        {
            EditorGUILayout.HelpBox(statusMessage, MessageType.Info);
            if (humanIteration > 1)
                EditorGUILayout.LabelField(
                    $"Human review attempt {humanIteration}/{MAX_HUMAN_ITERATIONS}",
                    EditorStyles.boldLabel);
            GUILayout.Label("Running pipeline — please wait…", EditorStyles.boldLabel);
            Repaint();
        }

        // ─── review ───────────────────────────────────────────────────────────
        private void DrawReview()
        {
            // VLM summary
            EditorGUILayout.LabelField("Pipeline Result", EditorStyles.boldLabel);
            EditorGUILayout.BeginVertical(EditorStyles.helpBox);
            EditorGUILayout.LabelField($"Updated shape:  {pipelineResult.updatedFileName}");
            EditorGUILayout.LabelField($"VLM score:      {pipelineResult.vlmScore}/10");
            EditorGUILayout.LabelField("VLM feedback:", EditorStyles.miniBoldLabel);
            EditorGUILayout.LabelField(pipelineResult.vlmFeedback ?? "—", EditorStyles.wordWrappedLabel);
            EditorGUILayout.EndVertical();

            // Before / after images side by side
            EditorGUILayout.Space(8);
            float imgSize = Mathf.Min((position.width - 50f) * 0.5f, 380f);

            EditorGUILayout.BeginHorizontal();

            EditorGUILayout.BeginVertical();
            EditorGUILayout.LabelField("BEFORE", EditorStyles.boldLabel);
            if (beforeTex != null)
                GUILayout.Label(beforeTex, GUILayout.Width(imgSize), GUILayout.Height(imgSize));
            else
                EditorGUILayout.HelpBox("Before image not available.", MessageType.Warning);
            EditorGUILayout.EndVertical();

            EditorGUILayout.Space(10);

            EditorGUILayout.BeginVertical();
            EditorGUILayout.LabelField("AFTER", EditorStyles.boldLabel);
            if (afterTex != null)
                GUILayout.Label(afterTex, GUILayout.Width(imgSize), GUILayout.Height(imgSize));
            else
                EditorGUILayout.HelpBox("After image not available.", MessageType.Warning);
            EditorGUILayout.EndVertical();

            EditorGUILayout.EndHorizontal();

            // Human rating
            EditorGUILayout.Space(10);
            EditorGUILayout.LabelField(
                $"Your Rating  (attempt {humanIteration}/{MAX_HUMAN_ITERATIONS})",
                EditorStyles.boldLabel);
            EditorGUILayout.BeginVertical(EditorStyles.helpBox);

            EditorGUILayout.LabelField(
                "Rate the update result 0–10. Score < 7 triggers a retry; both scores ≥ 8 adds to library.",
                EditorStyles.wordWrappedMiniLabel);
            EditorGUILayout.Space(4);

            EditorGUILayout.BeginHorizontal();
            GUILayout.Label("Score:", GUILayout.Width(48));
            humanScore = EditorGUILayout.IntSlider(humanScore, 0, 10);
            EditorGUILayout.EndHorizontal();

            EditorGUILayout.Space(4);
            EditorGUILayout.LabelField("Comment / feedback for retry (optional):", EditorStyles.miniBoldLabel);
            humanComment = EditorGUILayout.TextArea(humanComment, GUILayout.Height(50));
            EditorGUILayout.EndVertical();

            // Threshold hints
            EditorGUILayout.Space(6);
            bool vlmPass   = pipelineResult.vlmScore >= KB_THRESHOLD;
            bool humanPass = humanScore >= KB_THRESHOLD;
            bool willRetry = humanScore < HUMAN_REJECT_BELOW && humanIteration < MAX_HUMAN_ITERATIONS;

            string hint;
            MessageType hintType;
            if (humanScore < HUMAN_REJECT_BELOW)
            {
                hint     = willRetry
                    ? $"Score {humanScore} < {HUMAN_REJECT_BELOW} — will retry the pipeline with your feedback ({humanIteration}/{MAX_HUMAN_ITERATIONS} attempts)."
                    : $"Score {humanScore} < {HUMAN_REJECT_BELOW} — max retries reached. Pipeline will be marked as failed.";
                hintType = MessageType.Warning;
            }
            else if (vlmPass && humanPass)
            {
                hint     = $"✓ Both scores meet the threshold ({KB_THRESHOLD}). Shape will be added to the library.";
                hintType = MessageType.None;
            }
            else
            {
                hint     = $"Update accepted, but not added to library (both scores must be ≥ {KB_THRESHOLD}).\n" +
                           $"  VLM: {pipelineResult.vlmScore}/10 {(vlmPass ? "✓" : "✗")}    " +
                           $"Your score: {humanScore}/10 {(humanPass ? "✓" : "✗")}";
                hintType = MessageType.Info;
            }
            EditorGUILayout.HelpBox(hint, hintType);

            // Action buttons
            EditorGUILayout.Space(8);
            EditorGUILayout.BeginHorizontal();

            if (GUILayout.Button("Submit Review", GUILayout.Height(40)))
                _ = SubmitReviewAsync();

            GUI.backgroundColor = new Color(1f, 0.45f, 0.45f);
            if (GUILayout.Button("Discard", GUILayout.Width(110), GUILayout.Height(40)))
            {
                outcomeMessage = "Update discarded — not saved to library.";
                addedToLibrary = false;
                state          = State.Done;
                Repaint();
            }
            GUI.backgroundColor = Color.white;

            EditorGUILayout.EndHorizontal();
        }

        // ─── ingesting ────────────────────────────────────────────────────────
        private void DrawIngesting()
        {
            EditorGUILayout.HelpBox(statusMessage, MessageType.Info);
            GUILayout.Label("Adding to knowledge base — please wait…", EditorStyles.boldLabel);
            Repaint();
        }

        // ─── done ─────────────────────────────────────────────────────────────
        private void DrawDone()
        {
            EditorGUILayout.HelpBox(outcomeMessage,
                addedToLibrary ? MessageType.None : MessageType.Info);

            if (addedToLibrary && knowledgeBase != null)
                EditorGUILayout.LabelField(
                    $"Library now has {knowledgeBase.totalShapes} shapes.", EditorStyles.miniLabel);

            if (afterTex != null)
            {
                EditorGUILayout.Space(6);
                float size = Mathf.Min(position.width - 30f, 320f);
                var rect = GUILayoutUtility.GetRect(size, size,
                    GUILayout.Width(size), GUILayout.Height(size));
                GUI.DrawTexture(rect, afterTex, ScaleMode.ScaleToFit);
            }

            EditorGUILayout.Space(10);
            if (GUILayout.Button("Start Over", GUILayout.Height(36)))
                ResetToIdle();
        }

        // ─── pipeline logic ───────────────────────────────────────────────────
        private async Task RunPipelineAsync(string userFeedback)
        {
            state         = State.Running;
            statusMessage = $"Running update pipeline (human attempt {humanIteration}/{MAX_HUMAN_ITERATIONS})…";
            pipelineResult = null;
            beforeTex      = null;
            afterTex       = null;
            Repaint();

            pipelineResult = await HLSLUpdatePipelineManager.RunUpdatePipelineAsync(
                originalMaterial:  originalMaterial,
                updateRequest:     updateRequest,
                knowledgeBase:     knowledgeBase,
                config:            config,
                maxVlmIterations:  MAX_VLM_ITERATIONS,
                userFeedback:      string.IsNullOrEmpty(userFeedback) ? null : userFeedback);

            if (pipelineResult == null)
            {
                outcomeMessage = "Pipeline returned null — see Console.";
                state          = State.Done;
                Repaint();
                return;
            }

            if (!pipelineResult.success && string.IsNullOrEmpty(pipelineResult.updatedFileName))
            {
                outcomeMessage = $"Update pipeline failed: {pipelineResult.errorMessage}";
                state          = State.Done;
                Repaint();
                return;
            }

            LoadTexture(pipelineResult.beforeImagePath, ref beforeTex);
            LoadTexture(pipelineResult.afterImagePath,  ref afterTex);

            humanScore   = pipelineResult.vlmScore;
            humanComment = "";
            state        = State.AwaitingReview;
            Repaint();
        }

        private async Task SubmitReviewAsync()
        {
            // Case A: human score too low → retry
            if (humanScore < HUMAN_REJECT_BELOW)
            {
                if (humanIteration >= MAX_HUMAN_ITERATIONS)
                {
                    outcomeMessage = $"Max human review attempts ({MAX_HUMAN_ITERATIONS}) reached with score {humanScore}. Update failed.";
                    addedToLibrary = false;
                    state          = State.Done;
                    Repaint();
                    return;
                }

                if (!string.IsNullOrWhiteSpace(humanComment))
                    prevUserFeedback += (string.IsNullOrEmpty(prevUserFeedback) ? "" : " | ") + humanComment;

                humanIteration++;
                _ = RunPipelineAsync(prevUserFeedback);
                return;
            }

            // Case B: accepted (score >= 7) — check KB threshold
            bool vlmPass   = pipelineResult.vlmScore >= KB_THRESHOLD;
            bool humanPass = humanScore >= KB_THRESHOLD;

            if (!vlmPass || !humanPass)
            {
                outcomeMessage =
                    $"Update accepted!\n" +
                    $"VLM: {pipelineResult.vlmScore}/10 {(vlmPass ? "✓" : "✗")}    " +
                    $"Your score: {humanScore}/10 {(humanPass ? "✓" : "✗")}\n" +
                    $"Both scores must be ≥ {KB_THRESHOLD} to save to library.";
                addedToLibrary = false;
                state          = State.Done;
                Repaint();
                return;
            }

            // Case C: both scores >= 8 → add to KB
            state         = State.Ingesting;
            statusMessage = "Adding updated shape to knowledge base…";
            Repaint();

            int storedScore = System.Math.Max(pipelineResult.vlmScore, humanScore);
            string feedback = pipelineResult.vlmFeedback ?? "";
            if (!string.IsNullOrEmpty(humanComment))
                feedback += $" Human: {humanComment}";

            bool ok = await KnowledgeBaseUpdater.AddToLibraryAsync(
                hlslPath:     Path.Combine("Assets/ShaderGraphs/RAG_Updates",
                                           $"{pipelineResult.updatedFileName}.hlsl"),
                imagePath:    pipelineResult.afterImagePath,
                userPrompt:   $"Updated from '{pipelineResult.originalFileName}': {updateRequest}",
                geminiKey:    config.geminiKey,
                openAIKey:    config.openAIKey,
                verifyScore:  storedScore,
                fallbackDesc: feedback);

            addedToLibrary = ok;
            LoadKnowledgeBase();

            outcomeMessage = ok
                ? $"✓ '{pipelineResult.updatedFileName}' added to the knowledge base.\n" +
                  $"VLM: {pipelineResult.vlmScore}/10 · Your score: {humanScore}/10 · Stored: {storedScore}/10"
                : "Knowledge base update failed — see Console.";

            state = State.Done;
            Repaint();
        }

        // ─── helpers ──────────────────────────────────────────────────────────
        private void ResetToIdle()
        {
            pipelineResult   = null;
            beforeTex        = null;
            afterTex         = null;
            humanScore       = 8;
            humanComment     = "";
            humanIteration   = 1;
            prevUserFeedback = "";
            outcomeMessage   = "";
            addedToLibrary   = false;
            statusMessage    = "";
            state            = State.Idle;
            Repaint();
        }

        private static void LoadTexture(string path, ref Texture2D tex)
        {
            tex = null;
            if (string.IsNullOrEmpty(path) || !File.Exists(path)) return;

            AssetDatabase.ImportAsset(path);
            tex = AssetDatabase.LoadAssetAtPath<Texture2D>(path);

            if (tex == null)
            {
                tex = new Texture2D(2, 2);
                tex.LoadImage(File.ReadAllBytes(path));
            }
        }
    }
}
