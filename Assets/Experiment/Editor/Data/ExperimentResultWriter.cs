using System;
using System.IO;
using Newtonsoft.Json;
using UnityEngine;

namespace ShaderGraphExperiments
{
    public static class ExperimentResultWriter
    {
        public static string EnsureFolder(string folder)
        {
            if (!Directory.Exists(folder)) Directory.CreateDirectory(folder);
            return folder;
        }

        public static string WriteRunJson(ExperimentRun run, string folder)
        {
            EnsureFolder(folder);

            if (string.IsNullOrEmpty(run.run_id))
                run.run_id = Guid.NewGuid().ToString("N");

            if (string.IsNullOrEmpty(run.timestamp_utc))
                run.timestamp_utc = DateTime.UtcNow.ToString("o");

            string fileName = $"experiment_run_{DateTime.UtcNow:yyyyMMdd_HHmmss}_{run.run_id}.json";
            string path = Path.Combine(folder, fileName);

            string json = JsonConvert.SerializeObject(run, Formatting.Indented);
            File.WriteAllText(path, json);

            Debug.Log($"✓ Experiment JSON saved: {path}");
            return path.Replace("\\", "/");
        }
    }
}
