using UnityEditor;
using UnityEngine;
using System.IO;

namespace ShaderGraphGenerator.Editor
{
    /// <summary>
    /// Main editor window for the SDF ShaderGraph Generator.
    /// Provides two modes: Generate from HLSL file or Generate with AI.
    /// 
    /// Architecture:
    /// - This class handles UI state and user interaction
    /// - GeneratorWindowUI: Reusable UI drawing methods
    /// - ShaderGenerationPipeline: Generation logic and iteration
    /// - LLMApiService: API communication
    /// - LLMDataModels: Data structures
    /// </summary>
    public class ShaderGraphGeneratorWindow : EditorWindow
    {
        // ═══════════════════════════════════════════════════════════════════════
        //  FIELDS
        // ═══════════════════════════════════════════════════════════════════════

        // --- From File Section ---
        private Object hlslFile;
        private string outputPath = "Assets/ShaderGraphs/Generated.shadergraph";

        // --- Shared Output Settings ---
        private bool useTransparency = true;
        private bool usePixelation = false;
        private bool createMaterial = true;
        private bool createPreviewQuad = true;
        private bool captureScreenshot = true;
        private string screenshotPath = "Assets/ShaderGraphs/Previews/GeneratedPreview.png";

        // --- AI Generation Section ---
        private string llmPrompt = "a pentagon with dynamic size and stroke, centered, with rotation and corner radius";
        private ShaderGraphGeneratorConfig config;
        private string llmHlslFolder = "Assets/ShaderGraphs/Generated/HLSL";
        private string llmGraphFolder = "Assets/ShaderGraphs/Generated/Graphs";
        private string llmPreviewFolder = "Assets/ShaderGraphs/Generated/Previews";
        private bool isGenerating = false;

        // --- UI State ---
        private Vector2 scrollPos;
        private bool showPromptGuide = false;
        private bool showAdvancedSettings = false;
        private int selectedTab = 0;
        private readonly string[] tabNames = { "Generate from HLSL", "Generate with AI" };

        // ═══════════════════════════════════════════════════════════════════════
        //  MENU & LIFECYCLE
        // ═══════════════════════════════════════════════════════════════════════

        [MenuItem("Tools/ShaderGraph Generator")]
        public static void ShowWindow()
        {
            var window = GetWindow<ShaderGraphGeneratorWindow>("ShaderGraph Generator");
            window.minSize = new Vector2(420, 500);
        }

        private void OnEnable()
        {
            config = AssetDatabase.LoadAssetAtPath<ShaderGraphGeneratorConfig>(
                "Assets/ShaderGraphGeneratorConfig.asset"
            );
        }

        // ═══════════════════════════════════════════════════════════════════════
        //  MAIN GUI
        // ═══════════════════════════════════════════════════════════════════════

        private void OnGUI()
        {
            scrollPos = EditorGUILayout.BeginScrollView(scrollPos);

            GeneratorWindowUI.DrawHeader();
            EditorGUILayout.Space(10);

            // Tab Selection
            selectedTab = GUILayout.Toolbar(selectedTab, tabNames, GUILayout.Height(28));
            EditorGUILayout.Space(15);

            // Draw selected tab content
            if (selectedTab == 0)
                DrawHLSLFileSection();
            else
                DrawAIGenerationSection();

            EditorGUILayout.Space(15);
            DrawSharedOutputSettings();

            EditorGUILayout.Space(10);
            GeneratorWindowUI.DrawFooter();

            EditorGUILayout.EndScrollView();
        }

        // ═══════════════════════════════════════════════════════════════════════
        //  TAB: HLSL FILE
        // ═══════════════════════════════════════════════════════════════════════

        private void DrawHLSLFileSection()
        {
            GeneratorWindowUI.DrawSectionHeader("📄 Generate from HLSL File");

            EditorGUILayout.BeginVertical(EditorStyles.helpBox);

            hlslFile = EditorGUILayout.ObjectField("HLSL File", hlslFile, typeof(Object), false);
            outputPath = EditorGUILayout.TextField("Output Path", outputPath);

            EditorGUILayout.Space(8);

            EditorGUI.BeginDisabledGroup(hlslFile == null);
            if (GUILayout.Button("Generate ShaderGraph", GUILayout.Height(30)))
            {
                GenerateFromFile();
            }
            EditorGUI.EndDisabledGroup();

            EditorGUILayout.EndVertical();

            GeneratorWindowUI.DrawHLSLRequirementsInfo();
        }

        // ═══════════════════════════════════════════════════════════════════════
        //  TAB: AI GENERATION
        // ═══════════════════════════════════════════════════════════════════════

        private void DrawAIGenerationSection()
        {
            GeneratorWindowUI.DrawSectionHeader("🤖 Generate with AI");

            EditorGUILayout.BeginVertical(EditorStyles.helpBox);

            EditorGUILayout.LabelField("Describe your shape:", EditorStyles.boldLabel);
            llmPrompt = EditorGUILayout.TextArea(llmPrompt, GUILayout.Height(80));

            EditorGUILayout.Space(8);

            // Generate Button
            EditorGUI.BeginDisabledGroup(isGenerating || config == null);
            string buttonText = isGenerating ? "⏳ Generating..." : "✨ Generate Shape";
            if (GUILayout.Button(buttonText, GUILayout.Height(35)))
            {
                GenerateFromLLMAsync();
            }
            EditorGUI.EndDisabledGroup();

            if (config == null)
            {
                GeneratorWindowUI.DrawConfigMissingWarning();
            }

            EditorGUILayout.EndVertical();

            // Prompt Guide
            EditorGUILayout.Space(5);
            showPromptGuide = EditorGUILayout.Foldout(showPromptGuide, "📖 Prompt Writing Guide", true);

            if (showPromptGuide)
            {
                string selectedExample = GeneratorWindowUI.DrawPromptGuide();
                if (!string.IsNullOrEmpty(selectedExample))
                {
                    llmPrompt = selectedExample;
                }
            }
        }

        // ═══════════════════════════════════════════════════════════════════════
        //  SHARED OUTPUT SETTINGS
        // ═══════════════════════════════════════════════════════════════════════

        private void DrawSharedOutputSettings()
        {
            GeneratorWindowUI.DrawSectionHeader("⚙️ Output Settings");

            EditorGUILayout.BeginVertical(EditorStyles.helpBox);

            // Rendering Options
            EditorGUILayout.LabelField("Rendering", EditorStyles.boldLabel);
            useTransparency = EditorGUILayout.Toggle(
                new GUIContent("Transparency", "Enable alpha channel for transparent backgrounds"),
                useTransparency);
            usePixelation = EditorGUILayout.Toggle(
                new GUIContent("Pixelation Effect", "Add PixelCount property for retro pixel art style"),
                usePixelation);

            EditorGUILayout.Space(5);

            // Asset Creation Options
            EditorGUILayout.LabelField("Asset Creation", EditorStyles.boldLabel);
            createMaterial = EditorGUILayout.Toggle(
                new GUIContent("Create Material", "Automatically create a material using the generated shader"),
                createMaterial);
            createPreviewQuad = EditorGUILayout.Toggle(
                new GUIContent("Create Preview Quad", "Create a quad in scene to preview the shader"),
                createPreviewQuad);

            EditorGUI.BeginDisabledGroup(!createPreviewQuad);
            EditorGUI.indentLevel++;
            captureScreenshot = EditorGUILayout.Toggle(
                new GUIContent("Capture Screenshot", "Save a PNG preview of the generated shape"),
                captureScreenshot);

            if (captureScreenshot)
            {
                screenshotPath = EditorGUILayout.TextField("Screenshot Path", screenshotPath);
            }
            EditorGUI.indentLevel--;
            EditorGUI.EndDisabledGroup();

            EditorGUILayout.EndVertical();

            // Advanced Settings
            showAdvancedSettings = EditorGUILayout.Foldout(showAdvancedSettings, "🔧 Advanced Settings", true);
            if (showAdvancedSettings)
            {
                DrawAdvancedSettings();
            }
        }

        private void DrawAdvancedSettings()
        {
            EditorGUILayout.BeginVertical(EditorStyles.helpBox);

            EditorGUILayout.LabelField("AI Generation Paths", EditorStyles.boldLabel);
            llmHlslFolder = EditorGUILayout.TextField("HLSL Output", llmHlslFolder);
            llmGraphFolder = EditorGUILayout.TextField("Graph Output", llmGraphFolder);
            llmPreviewFolder = EditorGUILayout.TextField("Preview Output", llmPreviewFolder);

            EditorGUILayout.Space(5);

            EditorGUILayout.LabelField("API Configuration", EditorStyles.boldLabel);
            config = (ShaderGraphGeneratorConfig)EditorGUILayout.ObjectField(
                "Config Asset", config, typeof(ShaderGraphGeneratorConfig), false);

            EditorGUILayout.EndVertical();
        }

        // ═══════════════════════════════════════════════════════════════════════
        //  GENERATION METHODS
        // ═══════════════════════════════════════════════════════════════════════

        private void GenerateFromFile()
        {
            if (hlslFile == null)
            {
                EditorUtility.DisplayDialog("Error", "Please select an HLSL file", "OK");
                return;
            }

            string hlslPath = AssetDatabase.GetAssetPath(hlslFile);
            if (string.IsNullOrEmpty(hlslPath)) return;

            string guid = AssetDatabase.AssetPathToGUID(hlslPath);
            if (string.IsNullOrEmpty(guid)) return;

            try
            {
                // Generate the ShaderGraph
                HLSLFunctionInfo functionInfo = ShaderGraphJSONGenerator.GenerateFromHLSL(
                    hlslPath, guid, outputPath, useTransparency, usePixelation
                );

                AssetDatabase.Refresh();

                string successMessage = $"ShaderGraph generated at:\n{outputPath}";
                Material mat = null;

                if (createMaterial)
                {
                    mat = ShaderGraphGeneratorEditorUtility.CreateMaterialForShaderGraph(outputPath);
                    if (mat != null)
                    {
                        if (functionInfo != null)
                        {
                            ShaderGraphGeneratorEditorUtility.SetRandomMaterialProperties(mat, functionInfo);
                            if (mat.HasProperty("_PixelCount"))
                                mat.SetFloat("_PixelCount", 50.0f);
                        }
                        successMessage += $"\n\nMaterial created at:\n{AssetDatabase.GetAssetPath(mat)}";
                    }
                }

                if (createPreviewQuad && mat != null && functionInfo != null)
                {
                    GameObject quad = ShaderGraphGeneratorEditorUtility.CreatePreviewQuad(
                        mat, captureScreenshot, screenshotPath);
                    successMessage += $"\n\nCreated Preview Quad: {quad.name}";
                }

                AssetDatabase.Refresh();
                EditorUtility.DisplayDialog("Success", successMessage, "OK");
            }
            catch (System.Exception ex)
            {
                EditorUtility.DisplayDialog("Error", $"Failed to generate ShaderGraph:\n{ex.Message}", "OK");
            }
        }

        private async void GenerateFromLLMAsync()
        {
            if (isGenerating) return;

            isGenerating = true;
            Repaint();

            var settings = new GenerationSettings
            {
                UseTransparency = useTransparency,
                UsePixelation = usePixelation,
                CreateMaterial = createMaterial,
                CreatePreviewQuad = createPreviewQuad,
                CaptureScreenshot = captureScreenshot,
                HlslFolder = llmHlslFolder,
                GraphFolder = llmGraphFolder,
                PreviewFolder = llmPreviewFolder
            };

            var result = await ShaderGenerationPipeline.GenerateWithFeedbackAsync(
                llmPrompt,
                settings,
                config,
                (iteration, status) => Debug.Log($"[Generation] {status}")
            );

            if (result.Success)
            {
                EditorUtility.DisplayDialog("Success",
                    $"Shape generated successfully!\n" +
                    $"Score: {result.FinalScore}/10\n" +
                    $"Iterations: {result.IterationsUsed}\n\n" +
                    $"{result.Explanation}", "OK");
            }
            else
            {
                EditorUtility.DisplayDialog("Generation Incomplete",
                    "Max refinement attempts reached. The shape may need manual adjustment.\n\n" +
                    "Check the generated assets in the output folders.", "OK");
            }

            isGenerating = false;
            Repaint();
        }
    }
}