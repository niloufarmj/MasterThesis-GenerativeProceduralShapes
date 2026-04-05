using System;
using System.Collections.Generic;
using System.IO;
using System.Threading.Tasks;
using UnityEngine;
using UnityEditor;
using UnityEditor.Compilation;
using Newtonsoft.Json;
using ShaderGraphGenerator.Editor;
using ShaderGraphGenerator.KnowledgeBase;

namespace ShaderGraphGenerator.RAG
{
    /// <summary>
    /// Handles the full animation generation pipeline and survives domain reloads.
    ///
    /// Domain reload problem:
    ///   Writing a new .cs file triggers Unity to recompile and reload the domain,
    ///   which destroys all in-memory state including EditorWindow instances.
    ///   We survive by serialising pending state to EditorPrefs before the reload
    ///   and restoring it via [InitializeOnLoad] after the reload.
    /// </summary>
    [InitializeOnLoad]
    public static class MaterialAnimatorPipelineManager
    {
        // ─── Output paths ─────────────────────────────────────────────────────
        public const string ANIM_DIR    = "Assets/ShaderGraphs/Animations";
        private const string KB_USE_KEY = "AnimPipeline_UseKB";

        // ─── Domain reload state keys (EditorPrefs) ───────────────────────────
        private const string KEY_PENDING      = "AnimPipeline_Pending";
        private const string KEY_RESULT       = "AnimPipeline_Result";
        private const string KEY_MATERIAL     = "AnimPipeline_MaterialPath";
        private const string KEY_SCRIPT_PATH  = "AnimPipeline_ScriptPath";
        private const string KEY_FILE_NAME    = "AnimPipeline_FileName";
        private const string KEY_WINDOW_OPEN  = "AnimPipeline_WindowOpen";

        // ─── Static constructor — runs after every domain reload ──────────────
        static MaterialAnimatorPipelineManager()
        {
            // If we had a pending script attachment after a domain reload, finish it now.
            if (EditorPrefs.GetBool(KEY_PENDING, false))
            {
                // Delay one frame so Unity finishes its own startup
                EditorApplication.delayCall += ResumeAfterReload;
            }

            // Listen for future compilations
            CompilationPipeline.compilationFinished += OnCompilationFinished;
        }

        // ─── Public API ───────────────────────────────────────────────────────

        /// <summary>
        /// Main pipeline entry point. Runs steps 1-3 synchronously (in async context),
        /// saves the .cs file, then returns. After Unity recompiles, ResumeAfterReload
        /// attaches the script to a new quad and fires the window callback.
        /// </summary>
        public static async Task<AnimationPipelineResult> RunPipelineAsync(
            Material             sourceMaterial,
            string               animationRequest,
            ShaderGraphGeneratorConfig config,
            ShapeKnowledgeBase   kb,
            bool                 useKB        = true,
            string               userFeedback = null,
            Action<string>       onProgress   = null)
        {
            var result = new AnimationPipelineResult
            {
                animationRequest    = animationRequest,
                sourceMaterialName  = sourceMaterial != null ? sourceMaterial.name : "Unknown"
            };

            try
            {
                if (sourceMaterial == null)
                {
                    result.errorMessage = "No material provided.";
                    return result;
                }

                if (!Directory.Exists(ANIM_DIR)) Directory.CreateDirectory(ANIM_DIR);

                // ── Step 1: Extract material properties ───────────────────────
                onProgress?.Invoke("Step 1/4: Reading material properties…");
                var properties = AnimationScriptGenerator.ExtractMaterialProperties(sourceMaterial);
                if (properties.Count == 0)
                {
                    result.errorMessage = "Material has no animatable properties (float/color/vector).";
                    return result;
                }
                Debug.Log($"[AnimPipeline] Found {properties.Count} animatable properties.");

                // ── Step 2: Match material to KB shape + retrieve animations ─────
                ShapeMetadata matchedShape = null;
                var retrieved = new List<(AnimatorEntry, ShapeMetadata, float)>();

                if (useKB && kb != null)
                {
                    onProgress?.Invoke("Step 2/4: Matching material to knowledge base…");

                    matchedShape = AnimationKBHelper.FindMatchingShape(sourceMaterial, kb);
                    if (matchedShape != null)
                        Debug.Log($"[AnimPipeline] Material matched KB shape: '{matchedShape.fileName}' " +
                                  $"({matchedShape.animators.Count} existing animator(s)).");
                    else
                        Debug.Log("[AnimPipeline] Material not found in KB — animation won't be linked to a shape.");

                    // Retrieve similar animations across all shapes for LLM examples
                    if (kb.shapes.Count > 0)
                    {
                        retrieved = await AnimationKBHelper.SearchAnimationsAsync(
                            animationRequest, kb, config.openAIKey, topK: 2);
                        Debug.Log($"[AnimPipeline] Retrieved {retrieved.Count} animation example(s) from KB.");
                    }
                }
                else
                {
                    onProgress?.Invoke("Step 2/4: Skipping KB (disabled)…");
                }

                // ── Step 3: LLM generates C# script ──────────────────────────
                onProgress?.Invoke("Step 3/4: Generating animation script with Gemini…");
                // Convert to the format AnimationScriptGenerator expects
                var retrievedForGen = new List<(AnimatorEntry, float)>();
                foreach (var (anim, shape, sim) in retrieved)
                    retrievedForGen.Add((anim, sim));

                var llmResponse = await AnimationScriptGenerator.GenerateAnimationScriptAsync(
                    animationRequest,
                    sourceMaterial.name,
                    properties,
                    retrievedForGen,
                    config.geminiKey,
                    userFeedback);

                if (llmResponse == null)
                {
                    result.errorMessage = "LLM generation failed — null response.";
                    return result;
                }

                // Clean file name (no spaces, valid C# class name)
                string fileName  = SanitizeClassName(llmResponse.file_name);
                string csCode    = llmResponse.cs_code;

                // Make sure class name in code matches file name
                csCode = EnsureClassNameMatches(csCode, fileName);

                result.fileName        = fileName;
                result.csCode          = csCode;
                result.animationSummary = llmResponse.animation_summary;
                result.propertiesUsed  = llmResponse.properties_used;
                result.tags            = llmResponse.animation_tags;

                // ── Step 4: Save .cs file ─────────────────────────────────────
                onProgress?.Invoke("Step 4/4: Saving script (Unity will recompile)…");
                string scriptPath = Path.Combine(ANIM_DIR, $"{fileName}.cs");
                File.WriteAllText(scriptPath, csCode);

                result.scriptAssetPath = scriptPath;
                result.matchedShape    = matchedShape;

                // Persist state so we can resume after domain reload
                string matPath = AssetDatabase.GetAssetPath(sourceMaterial);
                EditorPrefs.SetBool(KEY_PENDING,     true);
                EditorPrefs.SetString(KEY_MATERIAL,  matPath);
                EditorPrefs.SetString(KEY_SCRIPT_PATH, scriptPath);
                EditorPrefs.SetString(KEY_FILE_NAME, fileName);
                EditorPrefs.SetBool(KEY_WINDOW_OPEN, true);

                AssetDatabase.Refresh(); // triggers recompile → domain reload

                // After domain reload, ResumeAfterReload() will create the quad.
                // We return here — the window will be notified via EditorPrefs polling.
                result.success = true;
                return result;
            }
            catch (Exception ex)
            {
                result.errorMessage = ex.Message;
                Debug.LogError($"[AnimPipeline] Exception: {ex.Message}\n{ex.StackTrace}");
                return result;
            }
        }

        // ─── Domain reload resume ─────────────────────────────────────────────

        private static void OnCompilationFinished(object obj)
        {
            // Compilation finished — if we were waiting, set up the delay call
            if (EditorPrefs.GetBool(KEY_PENDING, false))
                EditorApplication.delayCall += ResumeAfterReload;
        }

        private static void ResumeAfterReload()
        {
            if (!EditorPrefs.GetBool(KEY_PENDING, false)) return;

            string matPath    = EditorPrefs.GetString(KEY_MATERIAL,    "");
            string scriptPath = EditorPrefs.GetString(KEY_SCRIPT_PATH, "");
            string fileName   = EditorPrefs.GetString(KEY_FILE_NAME,   "");

            // Clear immediately so we don't run twice
            EditorPrefs.SetBool(KEY_PENDING, false);

            if (string.IsNullOrEmpty(scriptPath) || string.IsNullOrEmpty(fileName))
            {
                Debug.LogWarning("[AnimPipeline] Resume: missing state, aborting.");
                NotifyWindow(false, "State lost during domain reload.");
                return;
            }

            // Find the compiled script type
            var scriptType = FindType(fileName);
            if (scriptType == null)
            {
                Debug.LogWarning($"[AnimPipeline] Resume: type '{fileName}' not found. Compilation may have failed.");
                NotifyWindow(false, $"Script '{fileName}' did not compile. Check the Console for errors.");
                return;
            }

            // Load material
            Material mat = null;
            if (!string.IsNullOrEmpty(matPath))
                mat = AssetDatabase.LoadAssetAtPath<Material>(matPath);

            // Create quad in scene
            var quad = GameObject.CreatePrimitive(PrimitiveType.Quad);
            quad.name = $"Animation Preview — {fileName}";

            if (mat != null)
                quad.GetComponent<Renderer>().material = mat;

            // Attach the animation script
            quad.AddComponent(scriptType);

            // Frame it in scene view
            Selection.activeGameObject = quad;
            if (SceneView.lastActiveSceneView != null)
                SceneView.lastActiveSceneView.FrameSelected();

            Debug.Log($"[AnimPipeline] ✓ Created '{quad.name}' with {scriptType.Name} attached. Press Play to preview.");

            NotifyWindow(true, quad.name);
        }

        // ─── Window notification via EditorPrefs ──────────────────────────────
        // Since the window is recreated after domain reload, we use EditorPrefs
        // as a message bus. The window polls this each OnGUI frame.

        private const string KEY_NOTIFY_SUCCESS = "AnimPipeline_NotifySuccess";
        private const string KEY_NOTIFY_MSG     = "AnimPipeline_NotifyMsg";
        private const string KEY_NOTIFY_READY   = "AnimPipeline_NotifyReady";

        private static void NotifyWindow(bool success, string message)
        {
            EditorPrefs.SetBool(KEY_NOTIFY_SUCCESS, success);
            EditorPrefs.SetString(KEY_NOTIFY_MSG,   message);
            EditorPrefs.SetBool(KEY_NOTIFY_READY,   true);
        }

        /// <summary>
        /// Called by the window each OnGUI to check if resume completed.
        /// Returns true if there's a pending notification (consumes it).
        /// </summary>
        public static bool PollResumeNotification(out bool success, out string message)
        {
            if (!EditorPrefs.GetBool(KEY_NOTIFY_READY, false))
            {
                success = false; message = null; return false;
            }
            success = EditorPrefs.GetBool(KEY_NOTIFY_SUCCESS, false);
            message = EditorPrefs.GetString(KEY_NOTIFY_MSG, "");
            EditorPrefs.SetBool(KEY_NOTIFY_READY, false);
            return true;
        }

        /// <summary> True while waiting for compilation/domain reload. </summary>
        public static bool IsPendingReload => EditorPrefs.GetBool(KEY_PENDING, false);

        // ─── Helpers ──────────────────────────────────────────────────────────

        private static Type FindType(string typeName)
        {
            foreach (var asm in AppDomain.CurrentDomain.GetAssemblies())
            {
                var t = asm.GetType(typeName);
                if (t != null) return t;
            }
            // Also try without namespace
            foreach (var asm in AppDomain.CurrentDomain.GetAssemblies())
            {
                foreach (var t in asm.GetTypes())
                    if (t.Name == typeName) return t;
            }
            return null;
        }

        private static string SanitizeClassName(string name)
        {
            if (string.IsNullOrEmpty(name)) return "GeneratedAnimation";
            // Remove spaces and invalid chars
            var sb = new System.Text.StringBuilder();
            bool capitaliseNext = false;
            foreach (char c in name)
            {
                if (char.IsLetterOrDigit(c))
                {
                    sb.Append(capitaliseNext ? char.ToUpper(c) : c);
                    capitaliseNext = false;
                }
                else
                {
                    capitaliseNext = true;
                }
            }
            string result = sb.ToString();
            // Must start with letter
            if (result.Length == 0 || !char.IsLetter(result[0]))
                result = "Anim" + result;
            return result;
        }

        private static string EnsureClassNameMatches(string csCode, string className)
        {
            if (string.IsNullOrEmpty(csCode)) return csCode;
            // Replace the first occurrence of "class <anything> : MonoBehaviour"
            return System.Text.RegularExpressions.Regex.Replace(
                csCode,
                @"class\s+\w+\s*:\s*MonoBehaviour",
                $"class {className} : MonoBehaviour",
                System.Text.RegularExpressions.RegexOptions.Multiline);
        }
    }
}