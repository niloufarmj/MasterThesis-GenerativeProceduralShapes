using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using UnityEditor;
using UnityEngine;
using ShaderGraphGenerator.KnowledgeBase;

namespace ShaderGraphGenerator.RAG
{
    /// <summary>
    /// Test window for full RAG pipeline: Decompose → Retrieve → Compose
    /// </summary>
    public class CompositionTestWindow : EditorWindow
    {
        private ShaderGraphGeneratorConfig config;
        private ShapeKnowledgeBase knowledgeBase;
        
        private string userRequest = "a simple house with a triangular roof";
        private ShapeDecomposition decomposition;
        private Dictionary<string, List<ShapeSearchResult>> componentSearchResults;
        private Dictionary<string, ShapeSearchResult> selectedComponents;
        private ComposedHLSL composedResult;
        
        private bool isProcessing = false;
        private Vector2 scrollPos;

        [MenuItem("Tools/ShaderGraph Generator/3 Test Full RAG Pipeline")]
        public static void ShowWindow()
        {
            var window = GetWindow<CompositionTestWindow>("RAG Pipeline Test");
            window.minSize = new Vector2(900, 700);
        }

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
            const string KB_PATH = "Assets/ShaderGraphGenerator/KnowledgeBase/shape_metadata.json";
            if (!File.Exists(KB_PATH))
                return;

            string json = File.ReadAllText(KB_PATH);
            knowledgeBase = Newtonsoft.Json.JsonConvert.DeserializeObject<ShapeKnowledgeBase>(json);
        }

        private void OnGUI()
        {
            GUILayout.Label("RAG Composition Pipeline Test", EditorStyles.boldLabel);
            GUILayout.Label("Full pipeline: Decompose → Retrieve → Compose HLSL", EditorStyles.miniLabel);

            EditorGUILayout.Space();

            if (config == null || knowledgeBase == null)
            {
                EditorGUILayout.HelpBox("Config or Knowledge Base not found!", MessageType.Error);
                return;
            }

            DrawInputSection();
            EditorGUILayout.Space(10);
            DrawResultsSection();
        }

        private void DrawInputSection()
        {
            EditorGUILayout.LabelField("User Request:", EditorStyles.boldLabel);
            userRequest = EditorGUILayout.TextArea(userRequest, GUILayout.Height(60));

            EditorGUILayout.Space();

            EditorGUILayout.BeginHorizontal();
            GUI.enabled = !isProcessing;
            if (GUILayout.Button("Run Full Pipeline", GUILayout.Height(40)))
            {
                _ = RunFullPipelineAsync();
            }
            GUI.enabled = true;

            if (GUILayout.Button("Clear", GUILayout.Height(40)))
            {
                decomposition = null;
                componentSearchResults = null;
                selectedComponents = null;
                composedResult = null;
            }
            EditorGUILayout.EndHorizontal();

            if (isProcessing)
            {
                EditorGUILayout.LabelField("Processing...", EditorStyles.boldLabel);
                Repaint();
            }
        }

        private void DrawResultsSection()
        {
            if (composedResult == null)
                return;

            scrollPos = EditorGUILayout.BeginScrollView(scrollPos);

            // Show composition summary
            EditorGUILayout.LabelField("Composition Result", EditorStyles.boldLabel);
            EditorGUILayout.BeginVertical(EditorStyles.helpBox);
            
            EditorGUILayout.LabelField($"Function: {composedResult.functionName}");
            EditorGUILayout.LabelField($"Single Primitive: {composedResult.isSinglePrimitive}");
            EditorGUILayout.LabelField($"Components Used: {composedResult.components.Count}");
            
            EditorGUILayout.Space();
            
            foreach (var comp in composedResult.components)
            {
                EditorGUILayout.LabelField($"• {comp.shapeName} ({comp.role})", EditorStyles.miniLabel);
            }
            
            EditorGUILayout.EndVertical();

            EditorGUILayout.Space(10);

            // Show generated HLSL
            EditorGUILayout.LabelField("Generated HLSL Code", EditorStyles.boldLabel);
            EditorGUILayout.BeginVertical(EditorStyles.helpBox);
            EditorGUILayout.TextArea(composedResult.hlslCode, GUILayout.Height(300));
            EditorGUILayout.EndVertical();

            EditorGUILayout.Space();

            if (GUILayout.Button("Save HLSL File", GUILayout.Height(30)))
            {
                SaveHLSLFile();
            }

            EditorGUILayout.EndScrollView();
        }

        private async Task RunFullPipelineAsync()
        {
            isProcessing = true;

            Debug.Log("=== RAG COMPLETE PIPELINE START ===");

            // Run complete pipeline with visual feedback
            var result = await RAGPipelineManager.RunCompletePipelineAsync(
                userRequest,
                knowledgeBase,
                config,
                maxIterations: 3  // Allow up to 3 refinement iterations
            );

            isProcessing = false;

            if (!result.success)
            {
                EditorUtility.DisplayDialog("Pipeline Failed", 
                    $"Error: {result.errorMessage}", 
                    "OK");
                return;
            }

            // Show success dialog with results
            string message = $"✓ HLSL: {result.fileName}\n" +
                            $"✓ ShaderGraph: Generated\n" +
                            $"✓ Material: Created\n" +
                            $"✓ Preview: Rendered\n\n" +
                            $"VLM Score: {result.vmlScore}/10\n" +
                            $"Feedback: {result.vmlFeedback}\n\n" +
                            $"Preview saved at:\n{result.previewImagePath}";

            EditorUtility.DisplayDialog("RAG Pipeline Complete!", message, "OK");

            // Select the preview image in Project window
            var previewAsset = AssetDatabase.LoadAssetAtPath<Texture2D>(result.previewImagePath);
            if (previewAsset != null)
            {
                Selection.activeObject = previewAsset;
                EditorGUIUtility.PingObject(previewAsset);
            }
        }
        private void SaveHLSLFile()
        {
            if (composedResult == null)
                return;

            string directory = "Assets/ShaderGraphs/RAG_Generated";
            if (!Directory.Exists(directory))
                Directory.CreateDirectory(directory);

            string path = $"{directory}/{composedResult.functionName}.hlsl";
            File.WriteAllText(path, composedResult.hlslCode);
            AssetDatabase.Refresh();

            EditorUtility.DisplayDialog("Saved", $"HLSL code saved to:\n{path}", "OK");
            Debug.Log($"Saved composed HLSL to {path}");
        }

        private string SanitizeFunctionName(string userRequest)
        {
            // Create a valid function name from user request
            string name = userRequest.Trim();
            name = System.Text.RegularExpressions.Regex.Replace(name, @"[^a-zA-Z0-9\s]", "");
            name = System.Text.RegularExpressions.Regex.Replace(name, @"\s+", "_");
            
            if (name.Length > 40)
                name = name.Substring(0, 40);

            return "Composed_" + name;
        }
    }
}