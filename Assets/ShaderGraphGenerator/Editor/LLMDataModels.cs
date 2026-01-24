using System.Collections.Generic;

namespace ShaderGraphGenerator.Editor
{
    /// <summary>
    /// Response structure for LLM visual evaluation scores.
    /// </summary>
    [System.Serializable]
    public class LLMMatchScoreResponse
    {
        public int score;          // 1–10
        public string explanation; // short text
    }

    /// <summary>
    /// Represents a vector value from LLM response (x, y, z, w components).
    /// </summary>
    [System.Serializable]
    public struct LLMValueObject
    {
        public float x;
        public float y;
        public float z;
        public float w;
    }

    /// <summary>
    /// Represents a shader property definition from LLM response.
    /// </summary>
    [System.Serializable]
    public class LLMShaderProperty
    {
        public string name;
        public string type;
        public LLMValueObject default_value;
    }

    /// <summary>
    /// Complete LLM response containing generated shader code and properties.
    /// </summary>
    [System.Serializable]
    public class LLMShaderResponse
    {
        public string file_name;
        public string hlsl_code;
        public List<LLMShaderProperty> properties;
    }
}
