// Phase2ExperimentDataModels.cs
// Data models for Phase 2 (RAG-based) experiment.
// Three experiment types: Generation, Edit, Animation, Image-to-Shader.
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

    /// <summary>
    /// Identifies which LLM provider was used for a given run.
    /// Each provider maps to a specific model ID and pricing tier — see LlmPricing.
    /// </summary>
    public enum LlmProvider
    {
        Gemini,    // Google — gemini-2.5-pro (current default)
        OpenAI,    // OpenAI  — gpt-4.1
        DeepSeek,  // DeepSeek — deepseek-v3
        Mistral    // Mistral AI — mistral-large-latest
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //  TOKEN & COST TRACKING
    // ═══════════════════════════════════════════════════════════════════════════

    /// <summary>
    /// Tracks token usage and computed USD cost for a single LLM call.
    /// Populate input_tokens and output_tokens from the API response;
    /// call LlmPricing.Fill() to compute cost_usd automatically.
    /// </summary>
    [Serializable]
    public class LlmUsageStats
    {
        public int    input_tokens;
        public int    output_tokens;
        public int    total_tokens;   // input + output
        public double cost_usd;       // computed via LlmPricing.Fill()
    }

    /// <summary>
    /// Static pricing config. Model IDs and $/1M-token rates per provider.
    /// Update model_id and pricing constants here when upgrading models.
    ///
    /// Current rates (April 2026, standard tier, no batch/caching discount):
    ///   Gemini  (gemini-2.5-pro)        $1.25 in / $10.00 out  per 1M tokens
    ///   OpenAI  (gpt-4.1)               $2.00 in /  $8.00 out  per 1M tokens
    ///   DeepSeek(deepseek-v3)           $0.27 in /  $1.10 out  per 1M tokens
    ///   Mistral (mistral-large-latest)  $2.00 in /  $6.00 out  per 1M tokens
    /// </summary>
    public static class LlmPricing
    {
        public static readonly Dictionary<LlmProvider, LlmProviderConfig> Config =
            new Dictionary<LlmProvider, LlmProviderConfig>
            {
                {
                    LlmProvider.Gemini,
                    new LlmProviderConfig("gemini-2.5-pro",       inputPer1M: 1.25,  outputPer1M: 10.00)
                },
                {
                    LlmProvider.OpenAI,
                    new LlmProviderConfig("gpt-4.1",              inputPer1M: 2.00,  outputPer1M:  8.00)
                },
                {
                    LlmProvider.DeepSeek,
                    new LlmProviderConfig("deepseek-v3",          inputPer1M: 0.27,  outputPer1M:  1.10)
                },
                {
                    LlmProvider.Mistral,
                    new LlmProviderConfig("mistral-large-latest", inputPer1M: 2.00,  outputPer1M:  6.00)
                },
            };

        /// <summary>
        /// Fills total_tokens and cost_usd on stats given a provider.
        /// Call this immediately after receiving a response from the API.
        /// </summary>
        public static void Fill(LlmUsageStats stats, LlmProvider provider)
        {
            stats.total_tokens = stats.input_tokens + stats.output_tokens;
            if (!Config.TryGetValue(provider, out var cfg)) return;
            stats.cost_usd = (stats.input_tokens  / 1_000_000.0) * cfg.InputPer1M
                           + (stats.output_tokens / 1_000_000.0) * cfg.OutputPer1M;
        }

        /// <summary>Sums a collection of per-call stats into a single aggregate.</summary>
        public static LlmUsageStats Aggregate(IEnumerable<LlmUsageStats> all)
        {
            var result = new LlmUsageStats();
            foreach (var s in all)
            {
                if (s == null) continue;
                result.input_tokens  += s.input_tokens;
                result.output_tokens += s.output_tokens;
                result.total_tokens  += s.total_tokens;
                result.cost_usd      += s.cost_usd;
            }
            return result;
        }
    }

    /// <summary>Pricing constants for one provider/model pair.</summary>
    public class LlmProviderConfig
    {
        public readonly string ModelId;
        public readonly double InputPer1M;
        public readonly double OutputPer1M;

        public LlmProviderConfig(string modelId, double inputPer1M, double outputPer1M)
        {
            ModelId     = modelId;
            InputPer1M  = inputPer1M;
            OutputPer1M = outputPer1M;
        }
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

        // Token & cost tracking for this single LLM call
        public LlmUsageStats llm_usage = new LlmUsageStats();
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

        // Aggregated token & cost across all iterations for this shape
        public LlmUsageStats llm_usage_total = new LlmUsageStats();

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
        public string shape_set_name;     // e.g. "Simple_InRAG" | "Complex_NotInRAG"
        public string llm_provider;       // "Gemini" | "OpenAI" | "DeepSeek" | "Mistral"
        public string llm_model_id;       // exact model string used (from LlmPricing.Config)
        public string eval_provider;      // provider used for VLM evaluation

        public int    max_iterations;
        public int    success_threshold;
        public bool   require_human_score;

        // Quality summaries
        public float  summary_success_rate;
        public float  summary_avg_vlm_score;
        public float  summary_avg_iterations;
        public float  summary_avg_time_ms;
        public float  summary_compile_rate;
        public float  summary_avg_human_score;
        public float  summary_first_pass_compile_rate;

        // Token & cost summaries (aggregated across all shapes in this run)
        public int    summary_total_input_tokens;
        public int    summary_total_output_tokens;
        public int    summary_total_tokens;
        public double summary_total_cost_usd;

        public List<GenerationShapeResult> shapes = new List<GenerationShapeResult>();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //  EDIT EXPERIMENT
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

        // Token & cost for this single edit call
        public LlmUsageStats llm_usage = new LlmUsageStats();
    }

    /// <summary>
    /// Result for a single edit request applied to a specific material.
    /// </summary>
    [Serializable]
    public class EditExperimentItem
    {
        public string source_type;        // "complex_notinrag" | "image_ref"
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

        // Aggregated token & cost across all iterations for this edit
        public LlmUsageStats llm_usage_total = new LlmUsageStats();

        public List<EditIterationResult> iterations = new List<EditIterationResult>();
    }

    /// <summary>A full edit experiment session.</summary>
    [Serializable]
    public class EditExperimentRun
    {
        public string experiment_type = "edit";
        public string run_id;
        public string timestamp_utc;

        public string llm_provider;
        public string llm_model_id;
        public string eval_provider;

        // Quality summaries
        public float  summary_success_rate;
        public float  summary_avg_score_improvement;
        public float  summary_property_change_rate;
        public float  summary_hlsl_update_rate;
        public float  summary_avg_time_ms;

        // Token & cost summaries
        public int    summary_total_input_tokens;
        public int    summary_total_output_tokens;
        public int    summary_total_tokens;
        public double summary_total_cost_usd;

        public List<EditExperimentItem> items = new List<EditExperimentItem>();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //  ANIMATION EXPERIMENT
    // ═══════════════════════════════════════════════════════════════════════════

    /// <summary>Result for a single animation request.</summary>
    [Serializable]
    public class AnimationExperimentItem
    {
        public string source_type;        // "complex_notinrag" | "image_ref"
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

        // Token & cost for this animation generation call
        public LlmUsageStats llm_usage = new LlmUsageStats();
    }

    /// <summary>A full animation experiment session.</summary>
    [Serializable]
    public class AnimationExperimentRun
    {
        public string experiment_type = "animation";
        public string run_id;
        public string timestamp_utc;

        public string llm_provider;
        public string llm_model_id;

        // Quality summaries
        public float  summary_success_rate;
        public float  summary_avg_time_ms;
        public float  summary_avg_human_score;

        // Token & cost summaries
        public int    summary_total_input_tokens;
        public int    summary_total_output_tokens;
        public int    summary_total_tokens;
        public double summary_total_cost_usd;

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
        public string preview_image_path;
        public string error_message;

        // Human evaluation
        public int    human_score;
        public bool   accepted_by_human;

        // Token & cost for the description + generation calls
        public LlmUsageStats llm_usage = new LlmUsageStats();
    }

    /// <summary>A full image-to-shader experiment session.</summary>
    [Serializable]
    public class ImageExperimentRun
    {
        public string experiment_type = "image_to_shader";
        public string run_id;
        public string timestamp_utc;

        public string llm_provider;
        public string llm_model_id;
        public string eval_provider;

        // Quality summaries
        public float  summary_success_rate;
        public float  summary_avg_vlm_score;
        public float  summary_avg_time_ms;
        public float  summary_avg_human_score;

        // Token & cost summaries
        public int    summary_total_input_tokens;
        public int    summary_total_output_tokens;
        public int    summary_total_tokens;
        public double summary_total_cost_usd;

        public List<ImageExperimentItem> items = new List<ImageExperimentItem>();
    }
}
