using System.IO;
using System.Threading.Tasks;
using UnityEditor;
using UnityEngine;

namespace ShaderGraphGenerator.RAG
{
    /// <summary>
    /// Tool 2.5 — Manually add a single HLSL shape + screenshot to the knowledge base.
    ///
    /// Use this when the VLM evaluation was unavailable or unreliable during the
    /// auto-learn pipeline (2.4), or for any hand-crafted HLSL you want to ingest.
    ///
    /// The tool runs the same full ingestion steps as the auto-learn path:
    ///   1. Copy HLSL → SuccessfulResults/
    ///   2. OpenAI Vision → visual description comment appended to the HLSL file
    ///   3. Gemini → full metadata (category, complexity, symmetry, tags)
    ///   4. OpenAI embeddings → semantic search vector
    ///   5. shape_metadata.json updated
    ///   6. User prompt appended to final-shape-list.txt
    /// </summary>
    public class ManualLibraryAddWindow : EditorWindow
    {
        // ─── state ────────────────────────────────────────────────────────────
        private ShaderGraphGeneratorConfig config;

        private string hlslPath    = "";   // absolute or project-relative path
        private string imagePath   = "";
        private string userPrompt  = "";

        private Texture2D previewTex;
        private bool isProcessing;
        private string statusMessage = "";
        private bool lastSuccess;
        private bool hasResult;

        private Vector2 scrollPos;

        // ─── menu ─────────────────────────────────────────────────────────────
        [MenuItem("Tools/ShaderGraph Generator/2.5 Manual Add to Library")]
        public static void ShowWindow()
        {
            var w = GetWindow<ManualLibraryAddWindow>("2.5 Manual Add to Library");
            w.minSize = new Vector2(700, 560);
        }

        // ─── lifecycle ────────────────────────────────────────────────────────
        private void OnEnable() => LoadConfig();

        private void LoadConfig()
        {
            string[] guids = AssetDatabase.FindAssets("t:ShaderGraphGeneratorConfig");
            if (guids.Length > 0)
                config = AssetDatabase.LoadAssetAtPath<ShaderGraphGeneratorConfig>(
                    AssetDatabase.GUIDToAssetPath(guids[0]));
        }

        // ─── GUI ──────────────────────────────────────────────────────────────
        private void OnGUI()
        {
            GUILayout.Label("Manual Add Shape to Library", EditorStyles.boldLabel);
            GUILayout.Label(
                "Select an HLSL file and its preview screenshot to add it to the knowledge base with full AI annotation.",
                EditorStyles.wordWrappedMiniLabel);

            EditorGUILayout.Space(8);

            if (config == null)
            {
                EditorGUILayout.HelpBox("ShaderGraphGeneratorConfig not found!", MessageType.Error);
                return;
            }

            scrollPos = EditorGUILayout.BeginScrollView(scrollPos);

            DrawFilePickers();
            EditorGUILayout.Space(10);
            DrawPromptField();
            EditorGUILayout.Space(10);
            DrawPreview();
            EditorGUILayout.Space(10);
            DrawActionButtons();
            EditorGUILayout.Space(6);
            DrawStatus();

            EditorGUILayout.EndScrollView();
        }

        private void DrawFilePickers()
        {
            EditorGUILayout.LabelField("HLSL File", EditorStyles.boldLabel);
            EditorGUILayout.BeginHorizontal();
            hlslPath = EditorGUILayout.TextField(hlslPath);
            if (GUILayout.Button("Browse…", GUILayout.Width(80)))
            {
                string picked = EditorUtility.OpenFilePanel("Select HLSL file", "Assets", "hlsl");
                if (!string.IsNullOrEmpty(picked))
                    hlslPath = picked;
            }
            EditorGUILayout.EndHorizontal();

            // Also accept drag-drop of a TextAsset / DefaultAsset from the Project window
            var dropRect = GUILayoutUtility.GetLastRect();
            HandleDrop(dropRect, ".hlsl", ref hlslPath);

            EditorGUILayout.Space(6);

            EditorGUILayout.LabelField("Preview Screenshot (PNG)", EditorStyles.boldLabel);
            EditorGUILayout.BeginHorizontal();
            imagePath = EditorGUILayout.TextField(imagePath);
            if (GUILayout.Button("Browse…", GUILayout.Width(80)))
            {
                string picked = EditorUtility.OpenFilePanel("Select preview image", "Assets", "png,jpg,jpeg");
                if (!string.IsNullOrEmpty(picked))
                {
                    imagePath = picked;
                    ReloadPreview();
                }
            }
            EditorGUILayout.EndHorizontal();

            HandleDrop(GUILayoutUtility.GetLastRect(), ".png", ref imagePath, ReloadPreview);

            if (string.IsNullOrEmpty(imagePath))
                EditorGUILayout.HelpBox(
                    "Screenshot is optional but strongly recommended — it is sent to OpenAI Vision to generate the visual description.",
                    MessageType.Info);
        }

        private void DrawPromptField()
        {
            EditorGUILayout.LabelField("User Prompt / Shape Description", EditorStyles.boldLabel);
            EditorGUILayout.LabelField(
                "Describe what the shape is (same style as final-shape-list.txt).",
                EditorStyles.wordWrappedMiniLabel);
            userPrompt = EditorGUILayout.TextArea(userPrompt, GUILayout.Height(80));
        }

        private void DrawPreview()
        {
            if (previewTex == null) return;
            EditorGUILayout.LabelField("Preview:", EditorStyles.boldLabel);
            float size = Mathf.Min(position.width - 30, 240);
            GUILayout.Label(previewTex, GUILayout.Width(size), GUILayout.Height(size));
        }

        private void DrawActionButtons()
        {
            bool ready = !isProcessing
                         && !string.IsNullOrEmpty(hlslPath)  && File.Exists(hlslPath)
                         && !string.IsNullOrEmpty(userPrompt);

            GUI.enabled = ready;
            if (GUILayout.Button("Add to Library", GUILayout.Height(44)))
                _ = RunIngestionAsync();
            GUI.enabled = true;

            if (!ready && !isProcessing)
            {
                string missing = string.IsNullOrEmpty(hlslPath) || !File.Exists(hlslPath)
                    ? "• HLSL file is required and must exist on disk.\n"
                    : "";
                missing += string.IsNullOrEmpty(userPrompt)
                    ? "• User prompt / shape description is required.\n"
                    : "";
                if (!string.IsNullOrEmpty(missing))
                    EditorGUILayout.HelpBox(missing.TrimEnd(), MessageType.Warning);
            }
        }

        private void DrawStatus()
        {
            if (isProcessing)
            {
                EditorGUILayout.HelpBox(statusMessage, MessageType.Info);
                Repaint();
                return;
            }

            if (!hasResult) return;

            EditorGUILayout.HelpBox(
                lastSuccess
                    ? $"✓ Shape successfully added to the library.\n{statusMessage}"
                    : $"✗ Ingestion failed.\n{statusMessage}",
                lastSuccess ? MessageType.None : MessageType.Error);
        }

        // ─── ingestion ────────────────────────────────────────────────────────
        private async Task RunIngestionAsync()
        {
            isProcessing  = true;
            hasResult     = false;
            statusMessage = "Starting ingestion…";
            Repaint();

            bool ok = false;
            try
            {
                SetStatus("Copying HLSL and generating visual description…");
                ok = await KnowledgeBaseUpdater.AddToLibraryAsync(
                    hlslPath:    hlslPath,
                    imagePath:   imagePath,
                    userPrompt:  userPrompt,
                    geminiKey:   config.geminiKey,
                    openAIKey:   config.openAIKey);
            }
            catch (System.Exception ex)
            {
                Debug.LogError($"[Manual Add] Exception: {ex.Message}\n{ex.StackTrace}");
                statusMessage = ex.Message;
            }

            lastSuccess   = ok;
            hasResult     = true;
            isProcessing  = false;
            statusMessage = ok
                ? $"'{Path.GetFileNameWithoutExtension(hlslPath)}' added. Prompt saved to final-shape-list.txt."
                : "See Console for details.";

            Repaint();

            EditorUtility.DisplayDialog(
                ok ? "Library Updated" : "Ingestion Failed",
                ok  ? $"✓ Shape '{Path.GetFileNameWithoutExtension(hlslPath)}' has been added to:\n" +
                       "  • Assets/ShaderGraphs/SuccessfulResults/\n" +
                       "  • shape_metadata.json\n" +
                       "  • final-shape-list.txt\n\n" +
                       "The HLSL file now contains a visual description comment block."
                    : $"Ingestion failed. Check the Console for error details.",
                "OK");
        }

        // ─── helpers ──────────────────────────────────────────────────────────
        private void SetStatus(string msg)
        {
            statusMessage = msg;
            Repaint();
        }

        private void ReloadPreview()
        {
            previewTex = null;
            if (string.IsNullOrEmpty(imagePath) || !File.Exists(imagePath)) return;

            // Try loading via AssetDatabase first (works for assets inside the project)
            string relative = AbsoluteToAssetPath(imagePath);
            if (!string.IsNullOrEmpty(relative))
            {
                previewTex = AssetDatabase.LoadAssetAtPath<Texture2D>(relative);
            }

            // Fallback: load raw bytes
            if (previewTex == null)
            {
                byte[] bytes = File.ReadAllBytes(imagePath);
                previewTex = new Texture2D(2, 2);
                previewTex.LoadImage(bytes);
            }

            Repaint();
        }

        private static string AbsoluteToAssetPath(string abs)
        {
            string full    = Path.GetFullPath(abs).Replace('\\', '/');
            string project = Path.GetFullPath(Application.dataPath + "/..").Replace('\\', '/') + "/";
            return full.StartsWith(project) ? full.Substring(project.Length) : null;
        }

        private static void HandleDrop(Rect rect, string extension, ref string target,
                                       System.Action onChange = null)
        {
            Event e = Event.current;
            if ((e.type != EventType.DragUpdated && e.type != EventType.DragPerform)
                || !rect.Contains(e.mousePosition))
                return;

            foreach (var path in DragAndDrop.paths)
            {
                if (path.EndsWith(extension, System.StringComparison.OrdinalIgnoreCase))
                {
                    DragAndDrop.visualMode = DragAndDropVisualMode.Copy;
                    if (e.type == EventType.DragPerform)
                    {
                        DragAndDrop.AcceptDrag();
                        target = path;
                        onChange?.Invoke();
                    }
                    e.Use();
                    return;
                }
            }
        }
    }
}
