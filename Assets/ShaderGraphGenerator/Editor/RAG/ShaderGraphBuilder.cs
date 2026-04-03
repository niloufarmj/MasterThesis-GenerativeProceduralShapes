using UnityEditor;

namespace ShaderGraphGenerator.RAG
{
    /// <summary>
    /// Builds and saves a ShaderGraph JSON file from an LLM response.
    /// Delegates to ShaderGraphJSONGenerator which owns the full graph topology logic.
    /// </summary>
    public static class ShaderGraphBuilder
    {
        /// <summary>
        /// Builds and writes a .shadergraph JSON file from an LLM response.
        /// The HLSL file must already be saved to disk and visible to AssetDatabase.
        /// </summary>
        public static void BuildShaderGraphFromLLMResponse(
            string hlslPath,
            string outputPath,
            bool useTransparency = true)
        {
            string hlslGuid = AssetDatabase.AssetPathToGUID(hlslPath);
            ShaderGraphJSONGenerator.GenerateFromHLSL(hlslPath, hlslGuid, outputPath, useTransparency, usePixelation: false);
        }
    }
}
