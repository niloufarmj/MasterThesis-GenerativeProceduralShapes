using System;
using System.Collections.Generic;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace ShaderGraphGenerator.Editor
{
    /// <summary>
    /// Response structure for LLM visual evaluation scores.
    /// </summary>
    [Serializable]
    public class LLMMatchScoreResponse
    {
        public int score;          // 1–10
        public string explanation; // short text
    }

    /// <summary>
    /// Represents a vector value from LLM response (x, y, z, w components).
    /// </summary>
    [Serializable]
    public struct LLMValueObject
    {
        public float x;
        public float y;
        public float z;
        public float w;

        // Constructor for single float value
        public LLMValueObject(float value)
        {
            x = value;
            y = 0f;
            z = 0f;
            w = 0f;
        }

        // Constructor for float2
        public LLMValueObject(float x, float y)
        {
            this.x = x;
            this.y = y;
            this.z = 0f;
            this.w = 0f;
        }

        // Constructor for float3
        public LLMValueObject(float x, float y, float z)
        {
            this.x = x;
            this.y = y;
            this.z = z;
            this.w = 0f;
        }

        // Constructor for float4
        public LLMValueObject(float x, float y, float z, float w)
        {
            this.x = x;
            this.y = y;
            this.z = z;
            this.w = w;
        }
    }

    /// <summary>
    /// Represents a shader property definition from LLM response.
    /// </summary>
    [Serializable]
    public class LLMShaderProperty
    {
        public string name;
        public string type;
        
        [JsonConverter(typeof(FlexibleValueConverter))]
        public LLMValueObject default_value;
    }

    /// <summary>
    /// Complete LLM response containing generated shader code and properties.
    /// </summary>
    [Serializable]
    public class LLMShaderResponse
    {
        public string file_name;
        public string hlsl_code;
        public List<LLMShaderProperty> properties;
    }

    /// <summary>
    /// Custom JSON converter that handles both scalar and object formats for default_value
    /// Supports:
    /// - float: 0.5
    /// - float2/float3/float4: {"x": 1.0, "y": 0.5, ...}
    /// </summary>
    public class FlexibleValueConverter : JsonConverter<LLMValueObject>
    {
        public override LLMValueObject ReadJson(JsonReader reader, Type objectType, LLMValueObject existingValue, bool hasExistingValue, JsonSerializer serializer)
        {
            JToken token = JToken.Load(reader);

            // Case 1: Single number (for float type)
            if (token.Type == JTokenType.Float || token.Type == JTokenType.Integer)
            {
                float value = token.Value<float>();
                return new LLMValueObject(value);
            }

            // Case 2: Object with x, y, z, w components (for float2/float3/float4)
            if (token.Type == JTokenType.Object)
            {
                var obj = token.ToObject<LLMValueObject>();
                return obj;
            }

            // Fallback: return default
            return new LLMValueObject(0f);
        }

        public override void WriteJson(JsonWriter writer, LLMValueObject value, JsonSerializer serializer)
        {
            // Write as object with x, y, z, w
            writer.WriteStartObject();
            writer.WritePropertyName("x");
            writer.WriteValue(value.x);
            writer.WritePropertyName("y");
            writer.WriteValue(value.y);
            writer.WritePropertyName("z");
            writer.WriteValue(value.z);
            writer.WritePropertyName("w");
            writer.WriteValue(value.w);
            writer.WriteEndObject();
        }
    }
}