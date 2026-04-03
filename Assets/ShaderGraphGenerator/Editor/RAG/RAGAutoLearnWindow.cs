using System.IO;
using System.Threading.Tasks;
using UnityEditor;
using UnityEngine;
using ShaderGraphGenerator.KnowledgeBase;

namespace ShaderGraphGenerator.RAG
{
    /// <summary>
    /// Tool 2.4 — RAG Pipeline with Auto-Learning.
    /// Runs the same Decompose → Retrieve → Generate → Render → Evaluate pipeline as 2.3,
    /// but when the VLM score is above 8 the generated shape is automatically added back
    /// into the HLSL library and knowledge base JSON so future RAG runs can retrieve it.
    /// </summary>
    public class RAGAutoLearnWindow : EditorWindow
    {
        // ─────────────────────────────────────────────────────────────────────
        //  State
        // ─────────────────────────────────────────────────────────────────────
        private ShaderGraphGeneratorConfig config;
        private ShapeKnowledgeBase knowledgeBase;

        private string userRequest = "a cartoon sitting cat with rounded body, pointed ears, whiskers, collar, stripes, and a curved tail";
        private bool isProcessing;
        private string statusMessage = "";
        private RAGPipelineResult lastResult;
        private Vector2 scrollPos;

        private const string KB_PATH = "Assets/ShaderGraphGenerator/KnowledgeBase/shape_metadata.json";

        // ─────────────────────────────────────────────────────────────────────
        //  Menu
        // ─────────────────────────────────────────────────────────────────────
        [MenuItem("Tools/ShaderGraph Generator/2.4 RAG Pipeline with Auto-Learning")]
        public static void ShowWindow()
        {
            var window = GetWindow<RAGAutoLearnWindow>("2.4 RAG Auto-Learn");
            window.minSize = new Vector2(900, 700);
        }

        // ─────────────────────────────────────────────────────────────────────
        //  Lifecycle
        // ─────────────────────────────────────────────────────────────────────
        private void OnEnable()
        {
            LoadConfig();
            LoadKnowledgeBase();
        }

        private void LoadConfig()
        {
            string[] guids = AssetDatabase.FindAssets("t:ShaderGraphGeneratorConfig");
            if (guids.Length > 0)
            {
                string path = AssetDatabase.GUIDToAssetPath(guids[0]);
                config = AssetDatabase.LoadAssetAtPath<ShaderGraphGeneratorConfig>(path);
            }
        }

        private void LoadKnowledgeBase()
        {
            if (!File.Exists(KB_PATH)) return;
            string json = File.ReadAllText(KB_PATH);
            knowledgeBase = Newtonsoft.Json.JsonConvert.DeserializeObject<ShapeKnowledgeBase>(json);
        }

        // ─────────────────────────────────────────────────────────────────────
        //  GUI
        // ─────────────────────────────────────────────────────────────────────
        private void OnGUI()
        {
            GUILayout.Label("RAG Pipeline with Auto-Learning", EditorStyles.boldLabel);
            GUILayout.Label("Decompose → Retrieve → Generate → Render → Evaluate → Auto-Save if score > 8",
                EditorStyles.miniLabel);

            if (knowledgeBase != null)
                GUILayout.Label($"Library: {knowledgeBase.totalShapes} shapes", EditorStyles.miniLabel);

            EditorGUILayout.Space();

            if (config == null || knowledgeBase == null)
            {
                EditorGUILayout.HelpBox("Config or Knowledge Base not found!", MessageType.Error);
                return;
            }

            DrawInputSection();
            EditorGUILayout.Space(10);
            DrawResultSection();
        }

        private void DrawInputSection()
        {
            EditorGUILayout.LabelField("User Request:", EditorStyles.boldLabel);
            userRequest = EditorGUILayout.TextArea(userRequest, GUILayout.Height(70));

            EditorGUILayout.Space();

            EditorGUILayout.BeginHorizontal();
            GUI.enabled = !isProcessing;
            if (GUILayout.Button("Run Pipeline + Auto-Learn", GUILayout.Height(40)))
                _ = RunPipelineAsync();
            GUI.enabled = true;

            if (GUILayout.Button("Reload Knowledge Base", GUILayout.Height(40)))
            {
                LoadKnowledgeBase();
                statusMessage = $"Reloaded. Library now has {knowledgeBase?.totalShapes ?? 0} shapes.";
                Repaint();
            }
            EditorGUILayout.EndHorizontal();

            if (isProcessing)
            {
                EditorGUILayout.Space(4);
                EditorGUILayout.LabelField(statusMessage, EditorStyles.boldLabel);
                Repaint();
            }
        }

        private void DrawResultSection()
        {
            if (lastResult == null) return;

            scrollPos = EditorGUILayout.BeginScrollView(scrollPos);

            EditorGUILayout.LabelField("Last Result", EditorStyles.boldLabel);
            EditorGUILayout.BeginVertical(EditorStyles.helpBox);

            EditorGUILayout.LabelField($"Shape:   {lastResult.fileName}");
            EditorGUILayout.LabelField($"Score:   {lastResult.vmlScore}/10");
            EditorGUILayout.LabelField($"Success: {lastResult.success}");

            EditorGUILayout.Space(4);
            EditorGUILayout.LabelField("VLM Feedback:", EditorStyles.boldLabel);
            EditorGUILayout.LabelField(lastResult.vmlFeedback ?? "-", EditorStyles.wordWrappedLabel);

            if (lastResult.vmlScore > KnowledgeBaseUpdater.AUTO_LEARN_THRESHOLD)
            {
                EditorGUILayout.Space(4);
                var savedStyle = new GUIStyle(EditorStyles.helpBox)
                {
                    normal = { textColor = new Color(0.2f, 0.7f, 0.2f) }
                };
                EditorGUILayout.LabelField(
                    $"✓ Added to library (score {lastResult.vmlScore} > {KnowledgeBaseUpdater.AUTO_LEARN_THRESHOLD})",
                    EditorStyles.boldLabel);
                EditorGUILayout.LabelField($"  Library now has {knowledgeBase?.totalShapes ?? 0} shapes.",
                    EditorStyles.miniLabel);
            }
            else
            {
                EditorGUILayout.Space(4);
                EditorGUILayout.LabelField(
                    $"Score {lastResult.vmlScore} ≤ {KnowledgeBaseUpdater.AUTO_LEARN_THRESHOLD} — not added to library.",
                    EditorStyles.miniLabel);
            }

            EditorGUILayout.EndVertical();

            if (!string.IsNullOrEmpty(lastResult.previewImagePath))
            {
                EditorGUILayout.Space(6);
                var preview = AssetDatabase.LoadAssetAtPath<Texture2D>(lastResult.previewImagePath);
                if (preview != null)
                {
                    EditorGUILayout.LabelField("Preview:", EditorStyles.boldLabel);
                    float size = Mathf.Min(position.width - 30, 300);
                    GUILayout.Label(preview, GUILayout.Width(size), GUILayout.Height(size));
                }
            }

            EditorGUILayout.EndScrollView();
        }

        // ─────────────────────────────────────────────────────────────────────
        //  Pipeline
        // ─────────────────────────────────────────────────────────────────────
        private async Task RunPipelineAsync()
        {
            isProcessing = true;
            lastResult = null;
            statusMessage = "Running RAG pipeline...";
            Repaint();

            // Run the same pipeline as 2.3
            var result = await RAGPipelineManager.RunCompletePipelineAsync(
                userRequest,
                knowledgeBase,
                config,
                maxIterations: 3
            );

            lastResult = result;

            // Auto-learn: add to library if score > threshold
            if (result.vmlScore > KnowledgeBaseUpdater.AUTO_LEARN_THRESHOLD)
            {
                statusMessage = $"Score {result.vmlScore}/10 — adding to library...";
                Repaint();

                bool added = await KnowledgeBaseUpdater.TryAddToLibraryAsync(result, config.geminiKey, config.openAIKey);

                if (added)
                {
                    // Reload KB so the shape count in UI is up to date
                    LoadKnowledgeBase();
                    statusMessage = $"✓ Done — '{result.fileName}' saved to library.";
                }
                else
                {
                    statusMessage = "Pipeline complete — library update skipped (see console).";
                }
            }
            else
            {
                statusMessage = $"Done — score {result.vmlScore}/10, not added to library.";
            }

            isProcessing = false;

            // Show summary dialog
            if (!result.success && string.IsNullOrEmpty(result.errorMessage) == false)
            {
                EditorUtility.DisplayDialog("Pipeline Failed",
                    $"Error: {result.errorMessage}", "OK");
            }
            else
            {
                string learnLine = result.vmlScore > KnowledgeBaseUpdater.AUTO_LEARN_THRESHOLD
                    ? $"\n✓ Shape added to library for future RAG retrieval."
                    : $"\nScore below threshold ({KnowledgeBaseUpdater.AUTO_LEARN_THRESHOLD}) — not added to library.";

                EditorUtility.DisplayDialog("RAG Auto-Learn Complete",
                    $"Shape: {result.fileName}\n" +
                    $"VLM Score: {result.vmlScore}/10\n" +
                    $"Feedback: {result.vmlFeedback}\n" +
                    learnLine,
                    "OK");
            }

            // Select preview in Project window
            if (!string.IsNullOrEmpty(result.previewImagePath))
            {
                var preview = AssetDatabase.LoadAssetAtPath<Texture2D>(result.previewImagePath);
                if (preview != null)
                {
                    Selection.activeObject = preview;
                    EditorGUIUtility.PingObject(preview);
                }
            }

            Repaint();
        }
    }
}
