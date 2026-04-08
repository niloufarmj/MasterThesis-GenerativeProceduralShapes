using System.Collections.Generic;
using System.Threading.Tasks;
using UnityEditor;
using UnityEngine;
using ShaderGraphGenerator.KnowledgeBase;

namespace ShaderGraphGenerator.RAG
{
    /// <summary>
    /// Test window for shape decomposition and component retrieval
    /// </summary>
    public class DecompositionTestWindow : EditorWindow
    {
        private ShaderGraphGeneratorConfig config;
        private ShapeKnowledgeBase knowledgeBase;
        
        private string userRequest = "a house with a triangular roof and a door";
        private ShapeDecomposition decomposition;
        private Dictionary<string, List<ShapeSearchResult>> componentResults;
        
        private bool isProcessing = false;
        private Vector2 scrollPos;

        [MenuItem("Tools/ShaderGraph Generator/2.2 Test Shape Decomposition")]
        public static void ShowWindow()
        {
            var window = GetWindow<DecompositionTestWindow>("Decomposition Test");
            window.minSize = new Vector2(800, 600);
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
            if (!System.IO.File.Exists(KB_PATH))
                return;

            string json = System.IO.File.ReadAllText(KB_PATH);
            knowledgeBase = Newtonsoft.Json.JsonConvert.DeserializeObject<ShapeKnowledgeBase>(json);
        }

        private void OnGUI()
        {
            GUILayout.Label("Shape Decomposition Test", EditorStyles.boldLabel);
            GUILayout.Label("Step 2.2: Test decomposing complex requests into primitives", EditorStyles.miniLabel);

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
            if (GUILayout.Button("Decompose & Retrieve", GUILayout.Height(35)))
            {
                _ = DecomposeAndRetrieveAsync();
            }
            GUI.enabled = true;

            if (GUILayout.Button("Clear", GUILayout.Height(35)))
            {
                decomposition = null;
                componentResults = null;
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
            if (decomposition == null)
                return;

            scrollPos = EditorGUILayout.BeginScrollView(scrollPos);

            // Show decomposition
            EditorGUILayout.LabelField("Decomposition Result", EditorStyles.boldLabel);
            EditorGUILayout.BeginVertical(EditorStyles.helpBox);
            
            EditorGUILayout.LabelField($"Simple Shape: {decomposition.is_simple}");
            EditorGUILayout.LabelField($"Total Components: {decomposition.total_components}");
            EditorGUILayout.LabelField($"Uses Existing Shapes: {decomposition.uses_existing_shapes}");
            
            EditorGUILayout.Space();
            EditorGUILayout.LabelField("Agent Reasoning:", EditorStyles.miniBoldLabel);
            EditorGUILayout.LabelField(decomposition.reasoning, EditorStyles.wordWrappedMiniLabel);
            
            EditorGUILayout.Space();
            EditorGUILayout.LabelField("Composition Strategy:", EditorStyles.miniBoldLabel);
            EditorGUILayout.LabelField(decomposition.composition_strategy, EditorStyles.wordWrappedMiniLabel);
            
            if (decomposition.missing_shapes_needed != null && decomposition.missing_shapes_needed.Count > 0)
            {
                EditorGUILayout.Space();
                EditorGUILayout.LabelField("⚠️ Missing Shapes Identified:", EditorStyles.miniBoldLabel);
                foreach (var missing in decomposition.missing_shapes_needed)
                {
                    EditorGUILayout.LabelField($"  • {missing}", EditorStyles.wordWrappedMiniLabel);
                }
            }
            
            EditorGUILayout.EndVertical();

            EditorGUILayout.Space(10);

            // Show components and their retrieval results
            EditorGUILayout.LabelField("Components & Retrieved Primitives", EditorStyles.boldLabel);

            for (int i = 0; i < decomposition.components.Count; i++)
            {
                var component = decomposition.components[i];
                
                EditorGUILayout.BeginVertical(EditorStyles.helpBox);
                
                EditorGUILayout.LabelField($"Component {i + 1}: {component.role}", EditorStyles.boldLabel);
                EditorGUILayout.LabelField($"Description: {component.description}");
                EditorGUILayout.LabelField($"Type: {component.primitive_type} | Size: {component.relative_size} | Position: {component.position_hint}");
                
                // NEW: Show agent's predictions
                EditorGUILayout.LabelField($"Might exist as: {component.might_exist_as}", EditorStyles.miniLabel);
                string libraryStatus = component.is_likely_in_library ? "✓ Likely in library" : "⚠️ Might need generation";
                EditorGUILayout.LabelField(libraryStatus, EditorStyles.miniLabel);

                // Show retrieved shapes for this component
                if (componentResults != null && componentResults.ContainsKey(component.description))
                {
                    EditorGUILayout.Space(5);
                    EditorGUILayout.LabelField("Top 3 Retrieved Shapes:", EditorStyles.miniBoldLabel);
                    
                    var results = componentResults[component.description];
                    
                    if (results.Count == 0)
                    {
                        EditorGUILayout.LabelField("  ⚠️ No matches found - will need to generate", EditorStyles.miniLabel);
                    }
                    else
                    {
                        foreach (var result in results)
                        {
                            EditorGUILayout.BeginHorizontal();
                            EditorGUILayout.LabelField($"• {result.shape.fileName}", GUILayout.Width(200));
                            EditorGUILayout.LabelField($"(similarity: {result.similarity:F3})", GUILayout.Width(120));
                            EditorGUILayout.LabelField($"{result.shape.category}", GUILayout.Width(150));
                            EditorGUILayout.EndHorizontal();
                        }
                    }
                }

                EditorGUILayout.EndVertical();
                EditorGUILayout.Space(5);
            }

            EditorGUILayout.EndScrollView();
        }
        
        private async Task DecomposeAndRetrieveAsync()
        {
            isProcessing = true;
            decomposition = null;
            componentResults = null;

            // Step 1: Decompose the request (NOW PASSING KNOWLEDGE BASE)
            Debug.Log($"Decomposing request: {userRequest}");
            Debug.Log($"Knowledge base has {knowledgeBase.totalShapes} shapes");
            
            decomposition = await ShapeDecompositionService.DecomposeShapeAsync(
                userRequest, 
                knowledgeBase,  // ← NEW: Pass knowledge base
                config.geminiKey
            );

            if (decomposition == null)
            {
                EditorUtility.DisplayDialog("Error", "Failed to decompose shape request", "OK");
                isProcessing = false;
                return;
            }

            Debug.Log($"Decomposed into {decomposition.total_components} components");
            Debug.Log($"Reasoning: {decomposition.reasoning}");
            Debug.Log($"Uses existing shapes: {decomposition.uses_existing_shapes}");
            
            if (decomposition.missing_shapes_needed != null && decomposition.missing_shapes_needed.Count > 0)
            {
                Debug.LogWarning($"Missing shapes identified: {string.Join(", ", decomposition.missing_shapes_needed)}");
            }

            // Step 2: Retrieve primitives for each component
            componentResults = new Dictionary<string, List<ShapeSearchResult>>();

            foreach (var component in decomposition.components)
            {
                Debug.Log($"Searching for: {component.description}");
                Debug.Log($"  Agent thinks it might exist as: {component.might_exist_as}");
                Debug.Log($"  Likely in library: {component.is_likely_in_library}");
                
                var results = await SemanticShapeSearch.SearchAsync(
                    component.description,
                    knowledgeBase,
                    config.openAIKey,
                    topK: 3
                );

                componentResults[component.description] = results;

                if (results.Count > 0)
                {
                    Debug.Log($"  → Best match: {results[0].shape.fileName} (similarity: {results[0].similarity:F3})");
                }
                else
                {
                    Debug.LogWarning($"  → No matches found - will need to generate this component");
                }
            }

            isProcessing = false;
            
            string resultMessage = $"Decomposed into {decomposition.total_components} components!\n\n" +
                                $"Uses existing shapes: {decomposition.uses_existing_shapes}\n\n";
            
            if (decomposition.missing_shapes_needed.Count > 0)
            {
                resultMessage += $"⚠️ Missing shapes identified:\n{string.Join("\n", decomposition.missing_shapes_needed)}";
            }
            
            EditorUtility.DisplayDialog("Decomposition Complete", resultMessage, "OK");
        }
    }


}