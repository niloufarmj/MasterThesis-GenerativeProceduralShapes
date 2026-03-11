using System.IO;
using System.Collections.Generic;
using System.Threading.Tasks;
using UnityEditor;
using UnityEngine;
using Newtonsoft.Json;

namespace ShaderGraphGenerator.KnowledgeBase
{
    /// <summary>
    /// Editor tool to generate embeddings for knowledge base and test semantic search
    /// </summary>
    public class EmbeddingGeneratorWindow : EditorWindow
    {
        private const string KB_PATH = "Assets/ShaderGraphGenerator/KnowledgeBase/shape_metadata.json";

        private ShaderGraphGeneratorConfig config;
        private ShapeKnowledgeBase knowledgeBase;
        private bool isProcessing = false;
        private string statusMessage = "";
        private Vector2 scrollPos;

        // Search testing
        private string searchQuery = "";
        private List<ShapeSearchResult> searchResults = new List<ShapeSearchResult>();
        private bool showSearchResults = false;

        [MenuItem("Tools/ShaderGraph Generator/2. Generate Embeddings & Search")]
        public static void ShowWindow()
        {
            var window = GetWindow<EmbeddingGeneratorWindow>("Embedding Generator");
            window.minSize = new Vector2(700, 600);
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
            if (!File.Exists(KB_PATH))
            {
                Debug.LogWarning($"Knowledge base not found at {KB_PATH}");
                return;
            }

            string json = File.ReadAllText(KB_PATH);
            knowledgeBase = JsonConvert.DeserializeObject<ShapeKnowledgeBase>(json);
            Debug.Log($"Loaded knowledge base with {knowledgeBase.totalShapes} shapes");
        }

        private void OnGUI()
        {
            GUILayout.Label("Shape Embedding Generator & Semantic Search", EditorStyles.boldLabel);
            GUILayout.Label("Step 2.1: Generate embeddings and test retrieval", EditorStyles.miniLabel);

            EditorGUILayout.Space();

            if (config == null)
            {
                EditorGUILayout.HelpBox("Config not found! Create ShaderGraphGeneratorConfig asset.", MessageType.Error);
                return;
            }

            if (knowledgeBase == null)
            {
                EditorGUILayout.HelpBox($"Knowledge base not found at {KB_PATH}\nRun Step 1 first!", MessageType.Error);
                if (GUILayout.Button("Reload Knowledge Base"))
                {
                    LoadKnowledgeBase();
                }
                return;
            }

            DrawEmbeddingSection();
            EditorGUILayout.Space(10);
            DrawSearchSection();
        }

        private void DrawEmbeddingSection()
        {
            EditorGUILayout.LabelField("Embedding Generation", EditorStyles.boldLabel);

            int shapesWithEmbeddings = knowledgeBase.shapes.FindAll(s => s.embedding != null && s.embedding.Length > 0).Count;
            
            EditorGUILayout.HelpBox(
                $"Knowledge Base Status:\n" +
                $"• Total shapes: {knowledgeBase.totalShapes}\n" +
                $"• Shapes with embeddings: {shapesWithEmbeddings}\n" +
                $"• Missing embeddings: {knowledgeBase.totalShapes - shapesWithEmbeddings}\n\n" +
                $"This will use OpenAI's text-embedding-3-small model (~$0.00002 per shape).",
                MessageType.Info);

            GUI.enabled = !isProcessing;
            if (GUILayout.Button("Generate All Embeddings", GUILayout.Height(40)))
            {
                _ = GenerateAllEmbeddingsAsync();
            }
            GUI.enabled = true;

            if (isProcessing)
            {
                EditorGUILayout.LabelField("Status:", statusMessage);
                Repaint();
            }
        }

        private void DrawSearchSection()
        {
            EditorGUILayout.LabelField("Semantic Search Test", EditorStyles.boldLabel);

            int shapesWithEmbeddings = knowledgeBase.shapes.FindAll(s => s.embedding != null && s.embedding.Length > 0).Count;
            
            if (shapesWithEmbeddings == 0)
            {
                EditorGUILayout.HelpBox("Generate embeddings first to enable search!", MessageType.Warning);
                return;
            }

            EditorGUILayout.LabelField("Search Query:");
            searchQuery = EditorGUILayout.TextField(searchQuery);

            EditorGUILayout.BeginHorizontal();
            if (GUILayout.Button("Search", GUILayout.Height(30)))
            {
                _ = PerformSearchAsync();
            }
            if (GUILayout.Button("Clear", GUILayout.Height(30)))
            {
                searchResults.Clear();
                showSearchResults = false;
                searchQuery = "";
            }
            EditorGUILayout.EndHorizontal();

            if (showSearchResults && searchResults.Count > 0)
            {
                EditorGUILayout.Space();
                EditorGUILayout.LabelField($"Top {searchResults.Count} Results:", EditorStyles.boldLabel);

                scrollPos = EditorGUILayout.BeginScrollView(scrollPos, GUILayout.Height(300));

                foreach (var result in searchResults)
                {
                    EditorGUILayout.BeginVertical(EditorStyles.helpBox);
                    
                    EditorGUILayout.LabelField($"Similarity: {result.similarity:F3}", EditorStyles.boldLabel);
                    EditorGUILayout.LabelField("Shape:", result.shape.fileName);
                    EditorGUILayout.LabelField("Original Prompt:", EditorStyles.miniBoldLabel);
                    EditorGUILayout.LabelField(result.shape.originalPrompt, EditorStyles.wordWrappedMiniLabel);
                    EditorGUILayout.LabelField("Visual Description:", EditorStyles.miniBoldLabel);
                    EditorGUILayout.LabelField(result.shape.visualDescription, EditorStyles.wordWrappedMiniLabel);
                    EditorGUILayout.LabelField($"Category: {result.shape.category} | Complexity: {result.shape.complexity}");

                    EditorGUILayout.EndVertical();
                    EditorGUILayout.Space(5);
                }

                EditorGUILayout.EndScrollView();
            }
        }

        private async Task GenerateAllEmbeddingsAsync()
        {
            isProcessing = true;
            statusMessage = "Preparing embeddings...";

            var textsToEmbed = new List<string>();
            var shapesNeedingEmbeddings = new List<ShapeMetadata>();

            // Find shapes missing embeddings
            foreach (var shape in knowledgeBase.shapes)
            {
                if (shape.embedding == null || shape.embedding.Length == 0)
                {
                    string searchText = ShapeEmbeddingService.CreateSearchableText(shape);
                    textsToEmbed.Add(searchText);
                    shapesNeedingEmbeddings.Add(shape);
                }
            }

            if (textsToEmbed.Count == 0)
            {
                EditorUtility.DisplayDialog("Already Complete", "All shapes already have embeddings!", "OK");
                isProcessing = false;
                return;
            }

            Debug.Log($"Generating embeddings for {textsToEmbed.Count} shapes...");

            // Generate embeddings in batch
            var embeddings = await ShapeEmbeddingService.GenerateEmbeddingsBatchAsync(
                textsToEmbed,
                config.openAIKey,
                (current, total) => {
                    statusMessage = $"Generating embeddings: {current}/{total}";
                }
            );

            // Assign embeddings back to shapes
            for (int i = 0; i < shapesNeedingEmbeddings.Count; i++)
            {
                if (embeddings[i] != null)
                {
                    shapesNeedingEmbeddings[i].embedding = embeddings[i];
                }
            }

            // Save updated knowledge base
            SaveKnowledgeBase();

            statusMessage = $"✓ Generated {embeddings.Count} embeddings successfully!";
            isProcessing = false;

            EditorUtility.DisplayDialog("Success", 
                $"Generated embeddings for {embeddings.Count} shapes!\n\nKnowledge base updated.", 
                "OK");
        }

        private async Task PerformSearchAsync()
        {
            if (string.IsNullOrWhiteSpace(searchQuery))
                return;

            searchResults.Clear();
            showSearchResults = false;

            Debug.Log($"Searching for: {searchQuery}");

            searchResults = await SemanticShapeSearch.SearchAsync(
                searchQuery,
                knowledgeBase,
                config.openAIKey,
                topK: 5
            );

            showSearchResults = true;
            Debug.Log($"Found {searchResults.Count} results");
        }

        private void SaveKnowledgeBase()
        {
            string json = JsonConvert.SerializeObject(knowledgeBase, Formatting.Indented);
            File.WriteAllText(KB_PATH, json);
            AssetDatabase.Refresh();
            Debug.Log($"Knowledge base saved to {KB_PATH}");
        }
    }
}