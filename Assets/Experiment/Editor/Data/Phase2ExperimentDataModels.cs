// Phase2ExperimentDataModels.cs
// Data models for Phase 2 (RAG-based) experiment.
// Three experiment types: Generation, Edit, Animation.
// All saved as JSON for post-hoc analysis with the Python visualizer.

using System;
using System.Collections.Generic;

namespace ShaderGraphExperiments.Editor
{
    // ═══════════════════════════════════════════════════════════════════════════
    //  ENUMS
    // ═══════════════════════════════════════════════════════════════════════════

    public enum PipelineType
    {
        RAG,    // Phase 2 — RAG-augmented generation
        NoRAG   // Phase 1 equivalent — direct LLM, no retrieval
    }

    public enum ShapeComplexity
    {
        Simple,
        Complex
    }

    public enum EditType
    {
        Unknown,
        PropertyChange,   // Only material property values changed (no HLSL rewrite)
        HLSLUpdate        // Full HLSL shader modification required
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //  GENERATION EXPERIMENT
    // ═══════════════════════════════════════════════════════════════════════════

    /// <summary>
    /// A single iteration inside a shape generation run.
    /// Captured once per LLM call (1-N per shape).
    /// </summary>
    [Serializable]
    public class GenerationIterationResult
    {
        public int    iteration_index;
        public double iteration_time_ms;

        public bool   compile_ok;
        public int    vlm_score;          // 1–10 from the evaluator VLM
        public string vlm_explanation;

        public int    hlsl_length;        // length of generated HLSL code in characters
        public string hlsl_asset_path;
        public string shadergraph_asset_path;
        public string material_asset_path;
        public string screenshot_path;

        // RAG-specific (null/0 for No-RAG)
        public int    rag_components_decomposed;
        public int    rag_retrieved_examples;
        public float  rag_avg_similarity_score;
    }

    /// <summary>
    /// Full result for a single shape prompt in the generation experiment.
    /// </summary>
    [Serializable]
    public class GenerationShapeResult
    {
        public string prompt;
        public string shape_complexity;       // "Simple" | "Complex"
        public bool   in_knowledge_base;      // Was this shape already in the RAG KB?

        public bool   success;
        public int    iterations_used;
        public double total_time_ms;

        // Final quality scores
        public int    final_vlm_score;
        public string final_vlm_explanation;
        public int    human_score;            // 0 if not collected
        public bool   accepted_by_human;

        // First-pass compile (did iteration 1 produce valid HLSL?)
        public bool   first_pass_compiled;

        // RAG-specific per-shape stats (0 / 0.0 for No-RAG)
        public int    rag_components_decomposed;
        public int    rag_retrieved_examples;
        public float  rag_avg_similarity_score;

        // Per-iteration breakdown
        public List<GenerationIterationResult> iterations = new List<GenerationIterationResult>();
    }

    /// <summary>
    /// A full generation experiment run: N shapes tested with one pipeline configuration.
    /// </summary>
    [Serializable]
    public class GenerationExperimentRun
    {
        public string experiment_type = "generation";   // discriminator for Python script
        public string run_id;
        public string timestamp_utc;

        public string pipeline;           // "RAG" | "NoRAG"
        public string shape_set_name;     // "Simple" | "Complex" | "InRAG" | "Custom"
        public string code_provider;      // "Gemini" | "OpenAI"
        public string eval_provider;      // "OpenAI" | "Gemini"

        public int    max_iterations;
        public int    success_threshold;
        public bool   require_human_score;

        // Populated at run end
        public float  summary_success_rate;
        public float  summary_avg_vlm_score;
        public float  summary_avg_iterations;
        public float  summary_avg_time_ms;
        public float  summary_compile_rate;
        public float  summary_avg_human_score;
        public float  summary_first_pass_compile_rate;

        public List<GenerationShapeResult> shapes = new List<GenerationShapeResult>();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //  EDIT EXPERIMENT  (Phase 2 only — no Phase 1 equivalent)
    // ═══════════════════════════════════════════════════════════════════════════

    /// <summary>Single iteration in an HLSL-update edit.</summary>
    [Serializable]
    public class EditIterationResult
    {
        public int    iteration_index;
        public double iteration_time_ms;
        public int    vlm_score;
        public string vlm_explanation;
        public string screenshot_path;
        public bool   compile_ok;
    }

    /// <summary>
    /// Result for a single edit request applied to a specific material.
    /// </summary>
    [Serializable]
    public class EditExperimentItem
    {
        public string base_shape_prompt;
        public string material_name;
        public string material_path;
        public string edit_request;

        // Classification result
        public string edit_type;          // "PropertyChange" | "HLSLUpdate" | "Unknown"
        public string classification_reason;

        public bool   success;
        public int    iterations_used;    // 0 for PropertyChange (always 1 pass)
        public double total_time_ms;

        // VLM scores before and after
        public int    vlm_score_before;
        public int    vlm_score_after;
        public int    score_improvement;  // after - before

        public string screenshot_before_path;
        public string screenshot_after_path;

        // Human evaluation
        public int    human_score;
        public bool   accepted_by_human;

        public List<EditIterationResult> iterations = new List<EditIterationResult>();
    }

    /// <summary>A full edit experiment session.</summary>
    [Serializable]
    public class EditExperimentRun
    {
        public string experiment_type = "edit";
        public string run_id;
        public string timestamp_utc;

        // Summaries
        public float  summary_success_rate;
        public float  summary_avg_score_improvement;
        public float  summary_property_change_rate;   // fraction that were PropertyChange
        public float  summary_hlsl_update_rate;
        public float  summary_avg_time_ms;

        public List<EditExperimentItem> items = new List<EditExperimentItem>();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //  ANIMATION EXPERIMENT  (Phase 2 only — no Phase 1 equivalent)
    // ═══════════════════════════════════════════════════════════════════════════

    /// <summary>Result for a single animation request.</summary>
    [Serializable]
    public class AnimationExperimentItem
    {
        public string base_shape_prompt;
        public string material_name;
        public string material_path;
        public string animation_request;

        public bool   success;
        public double total_time_ms;

        public string generated_script_path;
        public string error_message;

        // Human evaluation
        public int    human_score;
        public bool   accepted_by_human;
    }

    /// <summary>A full animation experiment session.</summary>
    [Serializable]
    public class AnimationExperimentRun
    {
        public string experiment_type = "animation";
        public string run_id;
        public string timestamp_utc;

        public float  summary_success_rate;
        public float  summary_avg_time_ms;
        public float  summary_avg_human_score;

        public List<AnimationExperimentItem> items = new List<AnimationExperimentItem>();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //  IMAGE-TO-SHADER EXPERIMENT
    // ═══════════════════════════════════════════════════════════════════════════

    /// <summary>Result for a single image-to-shader generation.</summary>
    [Serializable]
    public class ImageExperimentItem
    {
        public string image_path;           // path to the reference image
        public string editable_hints;       // user's adjustable-properties note
        public string visual_description;   // VLM's description of the image

        public bool   success;
        public int    vlm_score;
        public string vlm_feedback;
        public double total_time_ms;

        public string shader_graph_path;
        public string material_path;
        public string preview_image_path;   // rendered output
        public string error_message;

        public int    human_score;
        public bool   accepted_by_human;
    }

    /// <summary>A full image-to-shader experiment session.</summary>
    [Serializable]
    public class ImageExperimentRun
    {
        public string experiment_type = "image_to_shader";
        public string run_id;
        public string timestamp_utc;

        public float  summary_success_rate;
        public float  summary_avg_vlm_score;
        public float  summary_avg_time_ms;
        public float  summary_avg_human_score;

        public List<ImageExperimentItem> items = new List<ImageExperimentItem>();
    }
}
