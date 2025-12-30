using System;

[Serializable]
public class ExperimentResult
{
    public string shapeName;
    public string shapeCategory; // Simple / Complex
    
    public string codeModel;     // Gemini / ChatGPT
    public string evalModel;     // Gemini / ChatGPT
    public string evalMode;      // Fast / Full (optional, latency-related)

    public int iterations;
    public float totalTimeSeconds;
    public bool success;

    public int llmScore;     // 1–10
    public int humanScore;   // 1–10
}
