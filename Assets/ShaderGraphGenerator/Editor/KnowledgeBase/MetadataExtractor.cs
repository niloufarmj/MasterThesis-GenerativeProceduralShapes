// using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using UnityEditor;
using UnityEngine;
using Newtonsoft.Json;
using System.Collections.Generic;

namespace ShaderGraphGenerator.KnowledgeBase
{
    /// <summary>
    /// Editor tool to extract metadata from all HLSL files using LLM analysis
    /// </summary>
    public class MetadataExtractor : EditorWindow
    {
        private const string SUCCESSFUL_RESULTS_FOLDER = "Assets/ShaderGraphs/SuccessfulResults";
        private const string PROMPT_LIST_PATH = "Assets/final-shape-list.txt";
        private const string OUTPUT_JSON_PATH = "Assets/ShaderGraphGenerator/KnowledgeBase/shape_metadata.json";

        private Vector2 scrollPos;
        private List<ShapeMetadata> extractedShapes = new List<ShapeMetadata>();
        private bool hasExtracted = false;
        private bool isProcessing = false;
        private string statusMessage = "";
        private ShaderGraphGeneratorConfig config;

        [MenuItem("Tools/ShaderGraph Generator/1. Extract Metadata with LLM")]
        public static void ShowWindow()
        {
            var window = GetWindow<MetadataExtractor>("Metadata Extractor (LLM)");
            window.minSize = new Vector2(700, 500);
        }

        private void OnEnable()
        {
            LoadConfig();
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

        private void OnGUI()
        {
            GUILayout.Label("HLSL Metadata Extractor with LLM Analysis", EditorStyles.boldLabel);
            GUILayout.Label("Step 1: Extract detailed metadata from verified HLSL shapes", EditorStyles.miniLabel);
            
            EditorGUILayout.Space();

            if (config == null)
            {
                EditorGUILayout.HelpBox(
                    "Config not found! Create a ShaderGraphGeneratorConfig asset.\n" +
                    "Right-click in Project → Create → ShaderGraphGenerator → Config",
                    MessageType.Error);
                return;
            }

            EditorGUILayout.HelpBox(
                $"This tool will:\n" +
                $"1. Scan all .hlsl files in: {SUCCESSFUL_RESULTS_FOLDER}\n" +
                $"2. Match each file with its original prompt from: {PROMPT_LIST_PATH}\n" +
                $"3. Send HLSL + prompt to Gemini for detailed analysis\n" +
                $"4. Extract: visual description, category, complexity, symmetry, tags\n" +
                $"5. Parse function signatures and parameters locally\n\n" +
                $"This process will make API calls for each shape (may take several minutes).",
                MessageType.Info);

            EditorGUILayout.Space();

            GUI.enabled = !isProcessing;
            if (GUILayout.Button("Start LLM-Based Extraction", GUILayout.Height(40)))
            {
                _ = ExtractMetadataWithLLMAsync();
            }
            GUI.enabled = true;

            if (isProcessing)
            {
                EditorGUILayout.Space();
                EditorGUILayout.LabelField("Status:", statusMessage);
                Repaint();
            }

            if (hasExtracted && !isProcessing)
            {
                EditorGUILayout.Space();
                GUILayout.Label($"✓ Extracted {extractedShapes.Count} shapes", EditorStyles.boldLabel);

                EditorGUILayout.BeginHorizontal();
                if (GUILayout.Button("Save to JSON", GUILayout.Height(30)))
                {
                    SaveToJSON();
                }
                if (GUILayout.Button("Clear", GUILayout.Height(30)))
                {
                    extractedShapes.Clear();
                    hasExtracted = false;
                    statusMessage = "";
                }
                EditorGUILayout.EndHorizontal();

                EditorGUILayout.Space();
                DrawShapeList();
            }
        }

        private async Task ExtractMetadataWithLLMAsync()
        {
            isProcessing = true;
            extractedShapes.Clear();
            statusMessage = "Loading files...";

            // 1. Check folders exist
            if (!Directory.Exists(SUCCESSFUL_RESULTS_FOLDER))
            {
                EditorUtility.DisplayDialog("Error", $"Folder not found: {SUCCESSFUL_RESULTS_FOLDER}", "OK");
                isProcessing = false;
                return;
            }

            if (!File.Exists(PROMPT_LIST_PATH))
            {
                EditorUtility.DisplayDialog("Error", $"Prompt list not found: {PROMPT_LIST_PATH}", "OK");
                isProcessing = false;
                return;
            }

            // 2. Load prompt list
            string[] prompts = File.ReadAllLines(PROMPT_LIST_PATH);
            Dictionary<string, string> promptMap = new Dictionary<string, string>();

            foreach (string line in prompts)
            {
                string trimmed = line.Trim();
                if (!string.IsNullOrEmpty(trimmed))
                {
                    // Try to extract shape name from prompt or use full prompt as key
                    // This is a simple heuristic - you might need to adjust
                    string key = ExtractShapeNameFromPrompt(trimmed);
                    promptMap[key] = trimmed;
                }
            }

            // 3. Get all HLSL files
            string[] hlslFiles = Directory.GetFiles(SUCCESSFUL_RESULTS_FOLDER, "*.hlsl", SearchOption.AllDirectories);
            statusMessage = $"Found {hlslFiles.Length} HLSL files";

            // 4. Process each file
            for (int i = 0; i < hlslFiles.Length; i++)
            {
                string filePath = hlslFiles[i];
                string fileName = Path.GetFileNameWithoutExtension(filePath);
                
                statusMessage = $"Processing {i + 1}/{hlslFiles.Length}: {fileName}";
                await Task.Delay(100); // Allow UI to update

                try
                {
                    // Parse local data
                    var metadata = HLSLParser.ParseHLSLFileLocal(filePath);
                    if (metadata == null)
                        continue;

                    // Find matching prompt
                    string prompt = FindMatchingPrompt(fileName, promptMap);
                    metadata.originalPrompt = prompt ?? $"A {fileName} shape";

                    // Read HLSL content
                    string hlslCode = HLSLParser.ReadHLSLContent(filePath);

                    // Call LLM for analysis
                    var analysis = await KnowledgeBaseLLMService.AnalyzeShapeAsync(
                        hlslCode, 
                        metadata.originalPrompt, 
                        config.geminiKey);

                    if (analysis != null)
                    {
                        // Populate metadata from LLM analysis
                        metadata.visualDescription = analysis.visual_description;
                        metadata.category = ParseCategory(analysis.category);
                        metadata.complexity = ParseComplexity(analysis.complexity);
                        metadata.symmetry = ParseSymmetry(analysis.symmetry);
                        metadata.tags = analysis.tags ?? new List<string>();

                        extractedShapes.Add(metadata);
                        Debug.Log($"✓ Successfully analyzed: {fileName}");
                    }
                    else
                    {
                        Debug.LogWarning($"✗ Failed LLM analysis for: {fileName}");
                    }
                }
                catch (System.Exception ex)
                {
                    Debug.LogError($"Error processing {fileName}: {ex.Message}");
                }
            }

            statusMessage = $"✓ Completed! Extracted {extractedShapes.Count}/{hlslFiles.Length} shapes";
            isProcessing = false;
            hasExtracted = true;
        }

        private string ExtractShapeNameFromPrompt(string prompt)
        {
            // Simple heuristic: take first meaningful word
            // You can improve this based on your prompt patterns
            string lower = prompt.ToLower().Trim();
            
            // Remove common prefixes
            lower = lower.Replace("a ", "").Replace("an ", "").Replace("the ", "");
            
            // Take first word as key
            string[] words = lower.Split(' ');
            return words.Length > 0 ? words[0] : prompt;
        }

        private string FindMatchingPrompt(string fileName, Dictionary<string, string> promptMap)
        {
            string lowerFileName = fileName.ToLower();
            
            // Try exact match
            if (promptMap.ContainsKey(lowerFileName))
                return promptMap[lowerFileName];
            
            // Try partial match
            foreach (var kvp in promptMap)
            {
                if (lowerFileName.Contains(kvp.Key) || kvp.Key.Contains(lowerFileName))
                    return kvp.Value;
            }
            
            // Fallback: return first prompt containing any word from filename
            string[] fileNameWords = lowerFileName.Split(new[] { '_', '-', ' ' });
            foreach (var word in fileNameWords)
            {
                if (word.Length < 3) continue; // Skip very short words
                
                foreach (var kvp in promptMap)
                {
                    if (kvp.Value.ToLower().Contains(word))
                        return kvp.Value;
                }
            }
            
            return null;
        }

        private ShapeCategory ParseCategory(string category)
        {
            switch (category)
            {
                case "GeometricPrimitives": return ShapeCategory.GeometricPrimitives;
                case "OrganicShapes": return ShapeCategory.OrganicShapes;
                case "SymbolsAndIcons": return ShapeCategory.SymbolsAndIcons;
                case "CompositeShapes": return ShapeCategory.CompositeShapes;
                default: return ShapeCategory.Uncategorized;
            }
        }

        private ComplexityLevel ParseComplexity(string complexity)
        {
            switch (complexity)
            {
                case "Primitive": return ComplexityLevel.Primitive;
                case "Intermediate": return ComplexityLevel.Intermediate;
                case "Complex": return ComplexityLevel.Complex;
                default: return ComplexityLevel.Unknown;
            }
        }

        private SymmetryType ParseSymmetry(string symmetry)
        {
            switch (symmetry)
            {
                case "None": return SymmetryType.None;
                case "Bilateral": return SymmetryType.Bilateral;
                case "Radial": return SymmetryType.Radial;
                case "Both": return SymmetryType.Both;
                default: return SymmetryType.Unknown;
            }
        }

        private void DrawShapeList()
        {
            scrollPos = EditorGUILayout.BeginScrollView(scrollPos);

            foreach (var shape in extractedShapes)
            {
                EditorGUILayout.BeginVertical(EditorStyles.helpBox);
                
                EditorGUILayout.LabelField("File:", shape.fileName, EditorStyles.boldLabel);
                EditorGUILayout.LabelField("Function:", shape.functionName);
                
                EditorGUILayout.Space(3);
                EditorGUILayout.LabelField("Original Prompt:", EditorStyles.miniBoldLabel);
                EditorGUILayout.LabelField(shape.originalPrompt, EditorStyles.wordWrappedMiniLabel);
                
                EditorGUILayout.Space(3);
                EditorGUILayout.LabelField("Visual Description:", EditorStyles.miniBoldLabel);
                EditorGUILayout.LabelField(shape.visualDescription, EditorStyles.wordWrappedMiniLabel);
                
                EditorGUILayout.Space(3);
                EditorGUILayout.LabelField($"Category: {shape.category} | Complexity: {shape.complexity} | Symmetry: {shape.symmetry}");
                EditorGUILayout.LabelField($"Tags: {string.Join(", ", shape.tags)}");
                EditorGUILayout.LabelField($"Parameters: {shape.parameters.Count}");

                EditorGUILayout.EndVertical();
                EditorGUILayout.Space(5);
            }

            EditorGUILayout.EndScrollView();
        }

        private void SaveToJSON()
        {
            var knowledgeBase = new ShapeKnowledgeBase
            {
                version = "1.0",
                generatedDate = System.DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss"),
                totalShapes = extractedShapes.Count,
                shapes = extractedShapes
            };

            string json = JsonConvert.SerializeObject(knowledgeBase, Formatting.Indented);

            // Ensure directory exists
            string directory = Path.GetDirectoryName(OUTPUT_JSON_PATH);
            if (!Directory.Exists(directory))
            {
                Directory.CreateDirectory(directory);
            }

            File.WriteAllText(OUTPUT_JSON_PATH, json);
            AssetDatabase.Refresh();

            EditorUtility.DisplayDialog("Success", 
                $"Saved metadata for {extractedShapes.Count} shapes to:\n{OUTPUT_JSON_PATH}\n\n" +
                "Each shape includes:\n" +
                "• Original prompt\n" +
                "• Detailed visual description (from LLM)\n" +
                "• Category, complexity, symmetry (from LLM)\n" +
                "• Tags (from LLM)\n" +
                "• Function signature and parameters (parsed locally)", 
                "OK");

            Debug.Log($"Knowledge base saved to {OUTPUT_JSON_PATH}");
        }
    }
}