using System;
using System.Collections.Generic;
using System.IO;
using System.Text.RegularExpressions;
using UnityEngine;

namespace ShaderGraphGenerator.KnowledgeBase
{
    /// <summary>
    /// Parses HLSL files to extract function signatures and parameters (LOCAL ONLY)
    /// </summary>
    public static class HLSLParser
    {
        /// <summary>
        /// Extract LOCAL metadata from an HLSL file (no LLM)
        /// </summary>
        public static ShapeMetadata ParseHLSLFileLocal(string filePath)
        {
            if (!File.Exists(filePath))
            {
                Debug.LogError($"HLSL file not found: {filePath}");
                return null;
            }

            string content = File.ReadAllText(filePath);
            string fileName = Path.GetFileNameWithoutExtension(filePath);

            var metadata = new ShapeMetadata
            {
                id = GenerateID(fileName),
                fileName = fileName,
                filePath = filePath,
                category = ShapeCategory.Uncategorized,
                complexity = ComplexityLevel.Unknown,
                symmetry = SymmetryType.Unknown,
                dateAdded = DateTime.Now.ToString("yyyy-MM-dd"),
                verificationScore = 7 // Default assumption: it's in SuccessfulResults
            };

            // Extract function name and parameters LOCALLY
            ExtractFunctionSignature(content, metadata);

            return metadata;
        }

        public static string ReadHLSLContent(string filePath)
        {
            if (!File.Exists(filePath))
                return null;
            return File.ReadAllText(filePath);
        }

        private static string GenerateID(string fileName)
        {
            // Create a unique ID from filename + timestamp hash
            string baseId = fileName.Replace(" ", "_").ToLower();
            return $"{baseId}_{Guid.NewGuid().ToString().Substring(0, 8)}";
        }

        private static void ExtractFunctionSignature(string hlslContent, ShapeMetadata metadata)
        {
            // Pattern: void FunctionName_float(float2 UV, [params...], out float4 outColor)
            var functionPattern = @"void\s+(\w+)_float\s*\((.*?)\)";
            var match = Regex.Match(hlslContent, functionPattern, RegexOptions.Singleline);

            if (!match.Success)
            {
                Debug.LogWarning($"Could not find function signature in {metadata.fileName}");
                metadata.functionName = metadata.fileName + "_float";
                return;
            }

            metadata.functionName = match.Groups[1].Value;
            string paramString = match.Groups[2].Value;

            // Parse parameters
            ParseParameters(paramString, metadata);
        }

        private static void ParseParameters(string paramString, ShapeMetadata metadata)
        {
            // Split by comma, but be careful with nested types
            var paramParts = SplitParameters(paramString);

            foreach (string part in paramParts)
            {
                string trimmed = part.Trim();
                
                // Skip UV (first param) and outColor (last param)
                if (trimmed.Contains("float2") && trimmed.Contains("UV"))
                    continue;
                if (trimmed.Contains("out") && trimmed.Contains("float4"))
                    continue;

                // Parse parameter: "float Radius" or "float4 Color"
                var paramMatch = Regex.Match(trimmed, @"(float\d?)\s+(\w+)");
                if (paramMatch.Success)
                {
                    string type = paramMatch.Groups[1].Value;
                    string name = paramMatch.Groups[2].Value;

                    metadata.parameters.Add(new ShapeParameter
                    {
                        name = name,
                        type = type,
                        defaultValue = GetDefaultValueForType(type)
                    });
                }
            }
        }

        private static List<string> SplitParameters(string paramString)
        {
            var result = new List<string>();
            int depth = 0;
            int start = 0;

            for (int i = 0; i < paramString.Length; i++)
            {
                char c = paramString[i];
                if (c == '(') depth++;
                if (c == ')') depth--;
                
                if (c == ',' && depth == 0)
                {
                    result.Add(paramString.Substring(start, i - start));
                    start = i + 1;
                }
            }

            // Add last parameter
            if (start < paramString.Length)
                result.Add(paramString.Substring(start));

            return result;
        }

        private static string GetDefaultValueForType(string type)
        {
            switch (type)
            {
                case "float": return "0.5";
                case "float2": return "0.5, 0.5";
                case "float3": return "0.5, 0.5, 0.5";
                case "float4": return "1.0, 1.0, 1.0, 1.0";
                default: return "0.0";
            }
        }
    }
}