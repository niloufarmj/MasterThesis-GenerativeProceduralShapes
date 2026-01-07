namespace ShaderGraphGenerator
{
    /// <summary>
    /// Represents a function parameter parsed from HLSL
    /// </summary>
    public class FunctionParameter
    {
        public string Type;
        public string Name;
        public bool IsOutput;
        public int SlotId;

        public string Direction { get; internal set; }

        public string GetMaterialSlotType()
        {
            switch (Type.ToLower())
            {
                case "float": return "UnityEditor.ShaderGraph.Vector1MaterialSlot";
                case "float2": return "UnityEditor.ShaderGraph.Vector2MaterialSlot";
                case "float3": return "UnityEditor.ShaderGraph.Vector3MaterialSlot";
                case "float4": return "UnityEditor.ShaderGraph.Vector4MaterialSlot";
                default: return "UnityEditor.ShaderGraph.Vector1MaterialSlot";
            }
        }

        public string GetDefaultValue()
        {
            switch (Type.ToLower())
            {
                case "float": return "0.0";
                case "float2": return "\"x\": 0.0, \"y\": 0.0";
                case "float3": return "\"x\": 0.0, \"y\": 0.0, \"z\": 0.0";
                case "float4": return "\"x\": 0.0, \"y\": 0.0, \"z\": 0.0, \"w\": 0.0";
                default: return "0.0";
            }
        }

        // Helper to detect if a float4 should be a Color property
        public bool IsColorProperty()
        {
            return Type.ToLower() == "float4" && Name.ToLower().Contains("color");
        }
    }
}