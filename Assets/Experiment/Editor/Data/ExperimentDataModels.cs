using System;
using System.Collections.Generic;

namespace ShaderGraphExperiments
{
    [Serializable]
    public class ExperimentRun
    {
        public string run_id;
        public string timestamp_utc;
        public string shape_set;              // "Simple" / "Complex"
        public string code_provider;          // "Gemini" / "OpenAI"
        public string eval_provider;          // "Gemini" / "OpenAI"
        public int max_iterations;
        public int success_threshold;         // e.g. 7
        public bool require_human_score;

        public List<ShapeRunResult> shapes = new List<ShapeRunResult>();

        // summary fields (optional; you can compute later in Python)
        public float avg_iteration_time_ms;
        public float avg_iterations_to_success;
        public float avg_success_quality;     // you can define formula later
    }

    [Serializable]
    public class ShapeRunResult
    {
        public string prompt;
        public bool success;
        public int iterations_used;

        public double total_time_ms;

        public int final_vlm_score;
        public string final_vlm_explanation;

        public int human_score;               // 0 if not provided
        public bool accepted_by_human;

        public List<IterationResult> iterations = new List<IterationResult>();
    }

    [Serializable]
    public class IterationResult
    {
        public int iteration_index;
        public double iteration_time_ms;

        public string generated_file_name;
        public string hlsl_asset_path;
        public string shadergraph_asset_path;
        public string material_asset_path;

        public string screenshot_path;

        public bool compile_ok;
        public int vlm_score;
        public string vlm_explanation;

        public string llm_raw_json;           // store raw response for debugging
    }

    [Serializable]
    public class VLMScore
    {
        public int score;
        public string explanation;
    }
}
