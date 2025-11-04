using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using UnityEngine;

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
    }

    /// <summary>
    /// Parsed HLSL function information
    /// </summary>
    public class HLSLFunctionInfo
    {
        public string FunctionName;
        public string DisplayName;
        public List<FunctionParameter> Parameters = new List<FunctionParameter>();
        
        public List<FunctionParameter> InputParameters => 
            Parameters.Where(p => !p.IsOutput).ToList();
            
        public List<FunctionParameter> OutputParameters => 
            Parameters.Where(p => p.IsOutput).ToList();
    }

    /// <summary>
    /// Main generator class for creating ShaderGraph JSON files
    /// </summary>
    public class ShaderGraphJSONGenerator
    {
        private Dictionary<string, string> guidMap = new Dictionary<string, string>();
        
        private string GetOrCreateGuid(string key)
        {
            if (!guidMap.ContainsKey(key))
            {
                guidMap[key] = Guid.NewGuid().ToString("N");
            }
            return guidMap[key];
        }
        
        /// <summary>
        /// Parse HLSL function signature
        /// </summary>
        public HLSLFunctionInfo ParseHLSLFunction(string hlslContent)
        {
            var info = new HLSLFunctionInfo();
            
            // Find the function signature - handle multiline
            var functionPattern = @"void\s+(\w+)\s*\(((?:[^()]+|\((?:[^()]+|\([^()]*\))*\))*)\)";
            var match = Regex.Match(hlslContent, functionPattern, RegexOptions.Singleline);
            
            if (!match.Success)
            {
                throw new Exception("Could not parse HLSL function signature");
            }
            
            info.FunctionName = match.Groups[1].Value;
            info.DisplayName = info.FunctionName.Replace("_float", "");
            
            // Parse parameters - be more careful with whitespace and line breaks
            string paramsString = match.Groups[2].Value;
            
            // Remove comments and normalize whitespace
            paramsString = Regex.Replace(paramsString, @"//.*?$", "", RegexOptions.Multiline);
            paramsString = Regex.Replace(paramsString, @"\s+", " ");
            
            // Split by comma
            var paramParts = paramsString.Split(',');
            
            int slotId = 0;
            foreach (var part in paramParts)
            {
                var trimmed = part.Trim();
                if (string.IsNullOrEmpty(trimmed)) continue;
                
                // Match: (out)? type name
                var paramMatch = Regex.Match(trimmed, @"^\s*(out\s+)?(\w+)\s+(\w+)\s*$");
                if (paramMatch.Success)
                {
                    var param = new FunctionParameter
                    {
                        IsOutput = !string.IsNullOrEmpty(paramMatch.Groups[1].Value),
                        Type = paramMatch.Groups[2].Value,
                        Name = paramMatch.Groups[3].Value,
                        SlotId = slotId++
                    };
                    info.Parameters.Add(param);
                    
                    Debug.Log($"Parsed param: {(param.IsOutput ? "out " : "")}{param.Type} {param.Name} (slot {param.SlotId})");
                }
                else
                {
                    Debug.LogWarning($"Could not parse parameter: '{trimmed}'");
                }
            }
            
            if (info.Parameters.Count == 0)
            {
                throw new Exception("No parameters parsed from function signature");
            }
            
            return info;
        }
        
        /// <summary>
        /// Generate complete ShaderGraph JSON - Main Entry Point
        /// </summary>
        public string GenerateShaderGraphJSON(
            HLSLFunctionInfo functionInfo,
            string hlslFileGUID,
            string shaderGraphName = "ProceduralShader",
            bool useTransparency = false)
        {
            guidMap.Clear();
            
            // Pre-create all GUIDs we need
            string graphGuid = GetOrCreateGuid("graph");
            string categoryGuid = GetOrCreateGuid("category");
            string vertexPosBlock = GetOrCreateGuid("vertex_pos");
            string vertexNormalBlock = GetOrCreateGuid("vertex_normal");
            string vertexTangentBlock = GetOrCreateGuid("vertex_tangent");
            string fragmentBaseColorBlock = GetOrCreateGuid("fragment_basecolor");
            string fragmentAlphaBlock = useTransparency ? GetOrCreateGuid("fragment_alpha") : null;
            string customFunctionNode = GetOrCreateGuid("custom_function");
            string uvNode = GetOrCreateGuid("uv_node");
            string splitNode = useTransparency ? GetOrCreateGuid("split_node") : null;
            string targetGuid = GetOrCreateGuid("target");
            string subTargetGuid = GetOrCreateGuid("subtarget");
            
            // Slot GUIDs
            string vertexPosSlot = GetOrCreateGuid("vertex_pos_slot");
            string vertexNormalSlot = GetOrCreateGuid("vertex_normal_slot");
            string vertexTangentSlot = GetOrCreateGuid("vertex_tangent_slot");
            string fragmentBaseColorSlot = GetOrCreateGuid("fragment_basecolor_slot");
            string uvOutputSlot = GetOrCreateGuid("uv_output_slot");
            
            // Property nodes and their slots
            var propertyNodes = new Dictionary<string, string>();
            var propertySlots = new Dictionary<string, string>();
            var propertyDefs = new Dictionary<string, string>();
            
            // Track which parameter will use the UV node
            string uvParamName = null;
            
            foreach (var param in functionInfo.InputParameters)
            {
                // First float2 parameter uses UV node, others become properties
                if (param.Type.ToLower() == "float2" && uvParamName == null)
                {
                    uvParamName = param.Name;
                }
                else
                {
                    // All other parameters become properties
                    propertyNodes[param.Name] = GetOrCreateGuid($"prop_node_{param.Name}");
                    propertySlots[param.Name] = GetOrCreateGuid($"prop_slot_{param.Name}");
                    propertyDefs[param.Name] = GetOrCreateGuid($"prop_def_{param.Name}");
                }
            }
            
            // Custom function slots
            var functionSlots = new Dictionary<string, string>();
            foreach (var param in functionInfo.Parameters)
            {
                functionSlots[param.Name] = GetOrCreateGuid($"func_slot_{param.Name}");
            }
            
            var sb = new StringBuilder();
            
            // ===== ROOT GRAPH OBJECT =====
            sb.AppendLine("{");
            sb.AppendLine("    \"m_SGVersion\": 3,");
            sb.AppendLine("    \"m_Type\": \"UnityEditor.ShaderGraph.GraphData\",");
            sb.AppendLine($"    \"m_ObjectId\": \"{graphGuid}\",");
            
            // Properties
            sb.AppendLine("    \"m_Properties\": [");
            var propRefs = propertyDefs.Values.Select(guid => $"        {{\n            \"m_Id\": \"{guid}\"\n        }}");
            sb.AppendLine(string.Join(",\n", propRefs));
            sb.AppendLine("    ],");
            
            sb.AppendLine("    \"m_Keywords\": [],");
            sb.AppendLine("    \"m_Dropdowns\": [],");
            sb.AppendLine("    \"m_CategoryData\": [");
            sb.AppendLine($"        {{\n            \"m_Id\": \"{categoryGuid}\"\n        }}");
            sb.AppendLine("    ],");
            
            // Nodes
            sb.AppendLine("    \"m_Nodes\": [");
            var nodeRefs = new List<string>();
            nodeRefs.Add($"        {{\n            \"m_Id\": \"{vertexPosBlock}\"\n        }}");
            nodeRefs.Add($"        {{\n            \"m_Id\": \"{vertexNormalBlock}\"\n        }}");
            nodeRefs.Add($"        {{\n            \"m_Id\": \"{vertexTangentBlock}\"\n        }}");
            nodeRefs.Add($"        {{\n            \"m_Id\": \"{fragmentBaseColorBlock}\"\n        }}");
            if (useTransparency && fragmentAlphaBlock != null)
            {
                nodeRefs.Add($"        {{\n            \"m_Id\": \"{fragmentAlphaBlock}\"\n        }}");
            }
            nodeRefs.Add($"        {{\n            \"m_Id\": \"{customFunctionNode}\"\n        }}");
            nodeRefs.Add($"        {{\n            \"m_Id\": \"{uvNode}\"\n        }}");
            if (useTransparency && splitNode != null)
            {
                nodeRefs.Add($"        {{\n            \"m_Id\": \"{splitNode}\"\n        }}");
            }
            foreach (var propNode in propertyNodes.Values)
            {
                nodeRefs.Add($"        {{\n            \"m_Id\": \"{propNode}\"\n        }}");
            }
            sb.AppendLine(string.Join(",\n", nodeRefs));
            sb.AppendLine("    ],");
            
            sb.AppendLine("    \"m_GroupDatas\": [],");
            sb.AppendLine("    \"m_StickyNoteDatas\": [],");
            
            // Edges
            sb.AppendLine("    \"m_Edges\": [");
            var edges = new List<string>();
            
            // UV node -> Custom function first float2 input
            if (!string.IsNullOrEmpty(uvParamName))
            {
                var uvParam = functionInfo.InputParameters.First(p => p.Name == uvParamName);
                edges.Add(FormatEdge(uvNode, 0, customFunctionNode, uvParam.SlotId));
            }
            
            // Property nodes -> Custom function inputs (connect to correct slot IDs)
            foreach (var param in functionInfo.InputParameters)
            {
                if (propertyNodes.ContainsKey(param.Name))
                {
                    edges.Add(FormatEdge(propertyNodes[param.Name], 0, customFunctionNode, param.SlotId));
                }
            }
            
            // Custom function output handling
            var firstOutput = functionInfo.OutputParameters.FirstOrDefault();
            if (firstOutput != null)
            {
                // Connect output to Base Color (ShaderGraph handles float4->float3 conversion automatically)
                edges.Add(FormatEdge(customFunctionNode, firstOutput.SlotId, fragmentBaseColorBlock, 0));
                
                // If transparency, also connect to Alpha block
                if (useTransparency && fragmentAlphaBlock != null && firstOutput.Type.ToLower() == "float4")
                {
                    edges.Add(FormatEdge(customFunctionNode, firstOutput.SlotId, fragmentAlphaBlock, 0));
                }
            }
            
            sb.AppendLine(string.Join(",\n", edges));
            sb.AppendLine("    ],");
            
            // Contexts
            sb.AppendLine("    \"m_VertexContext\": {");
            sb.AppendLine("        \"m_Position\": {");
            sb.AppendLine("            \"x\": 0.0,");
            sb.AppendLine("            \"y\": 0.0");
            sb.AppendLine("        },");
            sb.AppendLine("        \"m_Blocks\": [");
            sb.AppendLine($"            {{\n                \"m_Id\": \"{vertexPosBlock}\"\n            }},");
            sb.AppendLine($"            {{\n                \"m_Id\": \"{vertexNormalBlock}\"\n            }},");
            sb.AppendLine($"            {{\n                \"m_Id\": \"{vertexTangentBlock}\"\n            }}");
            sb.AppendLine("        ]");
            sb.AppendLine("    },");
            
            sb.AppendLine("    \"m_FragmentContext\": {");
            sb.AppendLine("        \"m_Position\": {");
            sb.AppendLine("            \"x\": 0.0,");
            sb.AppendLine("            \"y\": 200.0");
            sb.AppendLine("        },");
            sb.AppendLine("        \"m_Blocks\": [");
            if (useTransparency && fragmentAlphaBlock != null)
            {
                sb.AppendLine($"            {{\n                \"m_Id\": \"{fragmentBaseColorBlock}\"\n            }},");
                sb.AppendLine($"            {{\n                \"m_Id\": \"{fragmentAlphaBlock}\"\n            }}");
            }
            else
            {
                sb.AppendLine($"            {{\n                \"m_Id\": \"{fragmentBaseColorBlock}\"\n            }}");
            }
            sb.AppendLine("        ]");
            sb.AppendLine("    },");
            
            sb.AppendLine("    \"m_PreviewData\": {");
            sb.AppendLine("        \"serializedMesh\": {");
            sb.AppendLine("            \"m_SerializedMesh\": \"{\\\"mesh\\\":{\\\"instanceID\\\":0}}\",");
            sb.AppendLine("            \"m_Guid\": \"\"");
            sb.AppendLine("        },");
            sb.AppendLine("        \"preventRotation\": false");
            sb.AppendLine("    },");
            
            sb.AppendLine("    \"m_Path\": \"Shader Graphs\",");
            sb.AppendLine("    \"m_GraphPrecision\": 1,");
            sb.AppendLine("    \"m_PreviewMode\": 2,");
            sb.AppendLine("    \"m_OutputNode\": {");
            sb.AppendLine("        \"m_Id\": \"\"");
            sb.AppendLine("    },");
            sb.AppendLine("    \"m_SubDatas\": [],");
            sb.AppendLine("    \"m_ActiveTargets\": [");
            sb.AppendLine($"        {{\n            \"m_Id\": \"{targetGuid}\"\n        }}");
            sb.AppendLine("    ]");
            sb.AppendLine("}");
            
            // ===== NOW ALL THE DETAILED NODE DEFINITIONS =====
            
            // Vertex Position Block
            AppendBlockNode(sb, vertexPosBlock, "VertexDescription.Position", "Position", 
                vertexPosSlot, "UnityEditor.ShaderGraph.PositionMaterialSlot");
            
            // Vertex Normal Block
            AppendBlockNode(sb, vertexNormalBlock, "VertexDescription.Normal", "Normal",
                vertexNormalSlot, "UnityEditor.ShaderGraph.NormalMaterialSlot");
            
            // Vertex Tangent Block
            AppendBlockNode(sb, vertexTangentBlock, "VertexDescription.Tangent", "Tangent",
                vertexTangentSlot, "UnityEditor.ShaderGraph.TangentMaterialSlot");
            
            // Fragment Base Color Block
            AppendBlockNode(sb, fragmentBaseColorBlock, "SurfaceDescription.BaseColor", "Base Color",
                fragmentBaseColorSlot, "UnityEditor.ShaderGraph.ColorRGBMaterialSlot");
            
            // Slot definitions for block nodes
            AppendPositionSlot(sb, vertexPosSlot);
            AppendNormalSlot(sb, vertexNormalSlot);
            AppendTangentSlot(sb, vertexTangentSlot);
            AppendColorRGBSlot(sb, fragmentBaseColorSlot);
            
            // Custom Function Node
            AppendCustomFunctionNode(sb, customFunctionNode, functionInfo, hlslFileGUID, functionSlots);
            
            // Custom function slots
            foreach (var param in functionInfo.Parameters)
            {
                AppendFunctionSlot(sb, functionSlots[param.Name], param);
            }
            
            // UV Node
            AppendUVNode(sb, uvNode, uvOutputSlot);
            AppendUVSlot(sb, uvOutputSlot);
            
            // Property nodes
            foreach (var kvp in propertyNodes)
            {
                var param = functionInfo.InputParameters.First(p => p.Name == kvp.Key);
                AppendPropertyNode(sb, kvp.Value, propertyDefs[kvp.Key], propertySlots[kvp.Key], param);
                AppendPropertySlot(sb, propertySlots[kvp.Key], param);
            }
            
            // Property definitions
            foreach (var kvp in propertyDefs)
            {
                var param = functionInfo.InputParameters.First(p => p.Name == kvp.Key);
                AppendPropertyDefinition(sb, kvp.Value, param);
            }
            
            // Category
            AppendCategory(sb, categoryGuid, propertyDefs.Values.ToList());
            
            // Target
            AppendTarget(sb, targetGuid, subTargetGuid);
            AppendSubTarget(sb, subTargetGuid);
            
            return sb.ToString();
        }
        
        private string FormatEdge(string fromNode, int fromSlot, string toNode, int toSlot)
        {
            return $@"        {{
            ""m_OutputSlot"": {{
                ""m_Node"": {{
                    ""m_Id"": ""{fromNode}""
                }},
                ""m_SlotId"": {fromSlot}
            }},
            ""m_InputSlot"": {{
                ""m_Node"": {{
                    ""m_Id"": ""{toNode}""
                }},
                ""m_SlotId"": {toSlot}
            }}
        }}";
        }
        
        private void AppendBlockNode(StringBuilder sb, string guid, string descriptor, 
            string displayName, string slotGuid, string slotType)
        {
            sb.AppendLine($@"
{{
    ""m_SGVersion"": 0,
    ""m_Type"": ""UnityEditor.ShaderGraph.BlockNode"",
    ""m_ObjectId"": ""{guid}"",
    ""m_Group"": {{
        ""m_Id"": """"
    }},
    ""m_Name"": ""{descriptor}"",
    ""m_DrawState"": {{
        ""m_Expanded"": true,
        ""m_Position"": {{
            ""serializedVersion"": ""2"",
            ""x"": 0.0,
            ""y"": 0.0,
            ""width"": 0.0,
            ""height"": 0.0
        }}
    }},
    ""m_Slots"": [
        {{
            ""m_Id"": ""{slotGuid}""
        }}
    ],
    ""synonyms"": [],
    ""m_Precision"": 0,
    ""m_PreviewExpanded"": true,
    ""m_DismissedVersion"": 0,
    ""m_PreviewMode"": 0,
    ""m_CustomColors"": {{
        ""m_SerializableColors"": []
    }},
    ""m_SerializedDescriptor"": ""{descriptor}""
}}");
        }
        
        private void AppendPositionSlot(StringBuilder sb, string guid)
        {
            sb.AppendLine($@"
{{
    ""m_SGVersion"": 0,
    ""m_Type"": ""UnityEditor.ShaderGraph.PositionMaterialSlot"",
    ""m_ObjectId"": ""{guid}"",
    ""m_Id"": 0,
    ""m_DisplayName"": ""Position"",
    ""m_SlotType"": 0,
    ""m_Hidden"": false,
    ""m_ShaderOutputName"": ""Position"",
    ""m_StageCapability"": 1,
    ""m_Value"": {{
        ""x"": 0.0,
        ""y"": 0.0,
        ""z"": 0.0
    }},
    ""m_DefaultValue"": {{
        ""x"": 0.0,
        ""y"": 0.0,
        ""z"": 0.0
    }},
    ""m_Labels"": [],
    ""m_Space"": 0
}}");
        }
        
        private void AppendNormalSlot(StringBuilder sb, string guid)
        {
            sb.AppendLine($@"
{{
    ""m_SGVersion"": 0,
    ""m_Type"": ""UnityEditor.ShaderGraph.NormalMaterialSlot"",
    ""m_ObjectId"": ""{guid}"",
    ""m_Id"": 0,
    ""m_DisplayName"": ""Normal"",
    ""m_SlotType"": 0,
    ""m_Hidden"": false,
    ""m_ShaderOutputName"": ""Normal"",
    ""m_StageCapability"": 1,
    ""m_Value"": {{
        ""x"": 0.0,
        ""y"": 0.0,
        ""z"": 0.0
    }},
    ""m_DefaultValue"": {{
        ""x"": 0.0,
        ""y"": 0.0,
        ""z"": 0.0
    }},
    ""m_Labels"": [],
    ""m_Space"": 0
}}");
        }
        
        private void AppendTangentSlot(StringBuilder sb, string guid)
        {
            sb.AppendLine($@"
{{
    ""m_SGVersion"": 0,
    ""m_Type"": ""UnityEditor.ShaderGraph.TangentMaterialSlot"",
    ""m_ObjectId"": ""{guid}"",
    ""m_Id"": 0,
    ""m_DisplayName"": ""Tangent"",
    ""m_SlotType"": 0,
    ""m_Hidden"": false,
    ""m_ShaderOutputName"": ""Tangent"",
    ""m_StageCapability"": 1,
    ""m_Value"": {{
        ""x"": 0.0,
        ""y"": 0.0,
        ""z"": 0.0
    }},
    ""m_DefaultValue"": {{
        ""x"": 0.0,
        ""y"": 0.0,
        ""z"": 0.0
    }},
    ""m_Labels"": [],
    ""m_Space"": 0
}}");
        }
        
        private void AppendColorRGBSlot(StringBuilder sb, string guid)
        {
            sb.AppendLine($@"
{{
    ""m_SGVersion"": 0,
    ""m_Type"": ""UnityEditor.ShaderGraph.ColorRGBMaterialSlot"",
    ""m_ObjectId"": ""{guid}"",
    ""m_Id"": 0,
    ""m_DisplayName"": ""Base Color"",
    ""m_SlotType"": 0,
    ""m_Hidden"": false,
    ""m_ShaderOutputName"": ""BaseColor"",
    ""m_StageCapability"": 2,
    ""m_Value"": {{
        ""x"": 0.5,
        ""y"": 0.5,
        ""z"": 0.5
    }},
    ""m_DefaultValue"": {{
        ""x"": 0.5,
        ""y"": 0.5,
        ""z"": 0.5
    }},
    ""m_Labels"": [],
    ""m_ColorMode"": 0,
    ""m_DefaultColor"": {{
        ""r"": 0.5,
        ""g"": 0.5,
        ""b"": 0.5,
        ""a"": 1.0
    }}
}}");
        }
        
        private void AppendCustomFunctionNode(StringBuilder sb, string guid, 
            HLSLFunctionInfo functionInfo, string hlslFileGUID, Dictionary<string, string> slotGuids)
        {
            sb.AppendLine($@"
{{
    ""m_SGVersion"": 1,
    ""m_Type"": ""UnityEditor.ShaderGraph.CustomFunctionNode"",
    ""m_ObjectId"": ""{guid}"",
    ""m_Group"": {{
        ""m_Id"": """"
    }},
    ""m_Name"": ""{functionInfo.DisplayName} (Custom Function)"",
    ""m_DrawState"": {{
        ""m_Expanded"": true,
        ""m_Position"": {{
            ""serializedVersion"": ""2"",
            ""x"": -280.0,
            ""y"": 196.8,
            ""width"": 208.0,
            ""height"": 301.6
        }}
    }},
    ""m_Slots"": [");
            
            var slotRefs = functionInfo.Parameters.Select(p => 
                $"        {{\n            \"m_Id\": \"{slotGuids[p.Name]}\"\n        }}");
            sb.AppendLine(string.Join(",\n", slotRefs));
            
            sb.AppendLine($@"    ],
    ""synonyms"": [
        ""code"",
        ""HLSL""
    ],
    ""m_Precision"": 0,
    ""m_PreviewExpanded"": true,
    ""m_DismissedVersion"": 0,
    ""m_PreviewMode"": 0,
    ""m_CustomColors"": {{
        ""m_SerializableColors"": []
    }},
    ""m_SourceType"": 0,
    ""m_FunctionName"": ""{functionInfo.DisplayName}"",
    ""m_FunctionSource"": ""{hlslFileGUID}"",
    ""m_FunctionSourceUsePragmas"": true,
    ""m_FunctionBody"": ""Enter function body here...""
}}");
        }
        
        private void AppendFunctionSlot(StringBuilder sb, string guid, FunctionParameter param)
        {
            string slotType = param.IsOutput ? "1" : "0";
            
            // Generate proper JSON value format based on type
            string valueStr;
            switch (param.Type.ToLower())
            {
                case "float":
                    valueStr = "    \"m_Value\": 0.0,\n    \"m_DefaultValue\": 0.0,";
                    break;
                case "float2":
                    valueStr = "    \"m_Value\": {\n        \"x\": 0.0,\n        \"y\": 0.0\n    },\n    \"m_DefaultValue\": {\n        \"x\": 0.0,\n        \"y\": 0.0\n    },";
                    break;
                case "float3":
                    valueStr = "    \"m_Value\": {\n        \"x\": 0.0,\n        \"y\": 0.0,\n        \"z\": 0.0\n    },\n    \"m_DefaultValue\": {\n        \"x\": 0.0,\n        \"y\": 0.0,\n        \"z\": 0.0\n    },";
                    break;
                case "float4":
                    valueStr = "    \"m_Value\": {\n        \"x\": 0.0,\n        \"y\": 0.0,\n        \"z\": 0.0,\n        \"w\": 0.0\n    },\n    \"m_DefaultValue\": {\n        \"x\": 0.0,\n        \"y\": 0.0,\n        \"z\": 0.0,\n        \"w\": 0.0\n    },";
                    break;
                default:
                    valueStr = "    \"m_Value\": 0.0,\n    \"m_DefaultValue\": 0.0,";
                    break;
            }
            
            sb.AppendLine($@"
{{
    ""m_SGVersion"": 0,
    ""m_Type"": ""{param.GetMaterialSlotType()}"",
    ""m_ObjectId"": ""{guid}"",
    ""m_Id"": {param.SlotId},
    ""m_DisplayName"": ""{param.Name}"",
    ""m_SlotType"": {slotType},
    ""m_Hidden"": false,
    ""m_ShaderOutputName"": ""{param.Name}"",
    ""m_StageCapability"": 3,
{valueStr}
    ""m_Labels"": []
}}");
        }
        
        private void AppendUVNode(StringBuilder sb, string guid, string slotGuid)
        {
            sb.AppendLine($@"
{{
    ""m_SGVersion"": 0,
    ""m_Type"": ""UnityEditor.ShaderGraph.UVNode"",
    ""m_ObjectId"": ""{guid}"",
    ""m_Group"": {{
        ""m_Id"": """"
    }},
    ""m_Name"": ""UV"",
    ""m_DrawState"": {{
        ""m_Expanded"": true,
        ""m_Position"": {{
            ""serializedVersion"": ""2"",
            ""x"": -664.0,
            ""y"": 41.6,
            ""width"": 208.0,
            ""height"": 310.4
        }}
    }},
    ""m_Slots"": [
        {{
            ""m_Id"": ""{slotGuid}""
        }}
    ],
    ""synonyms"": [
        ""texcoords"",
        ""coords"",
        ""coordinates""
    ],
    ""m_Precision"": 0,
    ""m_PreviewExpanded"": true,
    ""m_DismissedVersion"": 0,
    ""m_PreviewMode"": 0,
    ""m_CustomColors"": {{
        ""m_SerializableColors"": []
    }},
    ""m_OutputChannel"": 0
}}");
        }
        
        private void AppendUVSlot(StringBuilder sb, string guid)
        {
            sb.AppendLine($@"
{{
    ""m_SGVersion"": 0,
    ""m_Type"": ""UnityEditor.ShaderGraph.Vector4MaterialSlot"",
    ""m_ObjectId"": ""{guid}"",
    ""m_Id"": 0,
    ""m_DisplayName"": ""Out"",
    ""m_SlotType"": 1,
    ""m_Hidden"": false,
    ""m_ShaderOutputName"": ""Out"",
    ""m_StageCapability"": 3,
    ""m_Value"": {{
        ""x"": 0.0,
        ""y"": 0.0,
        ""z"": 0.0,
        ""w"": 0.0
    }},
    ""m_DefaultValue"": {{
        ""x"": 0.0,
        ""y"": 0.0,
        ""z"": 0.0,
        ""w"": 0.0
    }},
    ""m_Labels"": []
}}");
        }
        
        private void AppendPropertyNode(StringBuilder sb, string nodeGuid, string propDefGuid, 
            string slotGuid, FunctionParameter param)
        {
            sb.AppendLine($@"
{{
    ""m_SGVersion"": 0,
    ""m_Type"": ""UnityEditor.ShaderGraph.PropertyNode"",
    ""m_ObjectId"": ""{nodeGuid}"",
    ""m_Group"": {{
        ""m_Id"": """"
    }},
    ""m_Name"": ""Property"",
    ""m_DrawState"": {{
        ""m_Expanded"": true,
        ""m_Position"": {{
            ""serializedVersion"": ""2"",
            ""x"": -581.6,
            ""y"": 407.7,
            ""width"": 0.0,
            ""height"": 0.0
        }}
    }},
    ""m_Slots"": [
        {{
            ""m_Id"": ""{slotGuid}""
        }}
    ],
    ""synonyms"": [],
    ""m_Precision"": 0,
    ""m_PreviewExpanded"": true,
    ""m_DismissedVersion"": 0,
    ""m_PreviewMode"": 0,
    ""m_CustomColors"": {{
        ""m_SerializableColors"": []
    }},
    ""m_Property"": {{
        ""m_Id"": ""{propDefGuid}""
    }}
}}");
        }
        
        private void AppendPropertySlot(StringBuilder sb, string guid, FunctionParameter param)
        {
            // Generate proper JSON value format based on type
            string valueStr;
            switch (param.Type.ToLower())
            {
                case "float":
                    valueStr = "    \"m_Value\": 0.0,\n    \"m_DefaultValue\": 0.0,";
                    break;
                case "float2":
                    valueStr = "    \"m_Value\": {\n        \"x\": 0.0,\n        \"y\": 0.0\n    },\n    \"m_DefaultValue\": {\n        \"x\": 0.0,\n        \"y\": 0.0\n    },";
                    break;
                case "float3":
                    valueStr = "    \"m_Value\": {\n        \"x\": 0.0,\n        \"y\": 0.0,\n        \"z\": 0.0\n    },\n    \"m_DefaultValue\": {\n        \"x\": 0.0,\n        \"y\": 0.0,\n        \"z\": 0.0\n    },";
                    break;
                case "float4":
                    valueStr = "    \"m_Value\": {\n        \"x\": 0.0,\n        \"y\": 0.0,\n        \"z\": 0.0,\n        \"w\": 0.0\n    },\n    \"m_DefaultValue\": {\n        \"x\": 0.0,\n        \"y\": 0.0,\n        \"z\": 0.0,\n        \"w\": 0.0\n    },";
                    break;
                default:
                    valueStr = "    \"m_Value\": 0.0,\n    \"m_DefaultValue\": 0.0,";
                    break;
            }
                
            sb.AppendLine($@"
{{
    ""m_SGVersion"": 0,
    ""m_Type"": ""{param.GetMaterialSlotType()}"",
    ""m_ObjectId"": ""{guid}"",
    ""m_Id"": 0,
    ""m_DisplayName"": ""{param.Name}"",
    ""m_SlotType"": 1,
    ""m_Hidden"": false,
    ""m_ShaderOutputName"": ""Out"",
    ""m_StageCapability"": 3,
{valueStr}
    ""m_Labels"": []
}}");
        }
        
        private void AppendPropertyDefinition(StringBuilder sb, string guid, FunctionParameter param)
        {
            string propertyType;
            string valueField;
            
            switch (param.Type.ToLower())
            {
                case "float":
                    propertyType = "UnityEditor.ShaderGraph.Internal.Vector1ShaderProperty";
                    valueField = "    \"m_Value\": 0.0,";
                    break;
                case "float2":
                    propertyType = "UnityEditor.ShaderGraph.Internal.Vector2ShaderProperty";
                    valueField = "    \"m_Value\": {\n        \"x\": 0.0,\n        \"y\": 0.0\n    },";
                    break;
                case "float3":
                    propertyType = "UnityEditor.ShaderGraph.Internal.Vector3ShaderProperty";
                    valueField = "    \"m_Value\": {\n        \"x\": 0.0,\n        \"y\": 0.0,\n        \"z\": 0.0\n    },";
                    break;
                case "float4":
                    propertyType = "UnityEditor.ShaderGraph.Internal.Vector4ShaderProperty";
                    valueField = "    \"m_Value\": {\n        \"x\": 0.0,\n        \"y\": 0.0,\n        \"z\": 0.0,\n        \"w\": 0.0\n    },";
                    break;
                default:
                    propertyType = "UnityEditor.ShaderGraph.Internal.Vector1ShaderProperty";
                    valueField = "    \"m_Value\": 0.0,";
                    break;
            }
            
            sb.AppendLine($@"
{{
    ""m_SGVersion"": 1,
    ""m_Type"": ""{propertyType}"",
    ""m_ObjectId"": ""{guid}"",
    ""m_Guid"": {{
        ""m_GuidSerialized"": ""{Guid.NewGuid()}""
    }},
    ""m_Name"": ""{param.Name}"",
    ""m_DefaultRefNameVersion"": 1,
    ""m_RefNameGeneratedByDisplayName"": ""{param.Name}"",
    ""m_DefaultReferenceName"": ""_{param.Name}"",
    ""m_OverrideReferenceName"": """",
    ""m_GeneratePropertyBlock"": true,
    ""m_UseCustomSlotLabel"": false,
    ""m_CustomSlotLabel"": """",
    ""m_DismissedVersion"": 0,
    ""m_Precision"": 0,
    ""overrideHLSLDeclaration"": false,
    ""hlslDeclarationOverride"": 0,
    ""m_Hidden"": false,
{valueField}
    ""m_FloatType"": 0,
    ""m_RangeValues"": {{
        ""x"": 0.0,
        ""y"": 1.0
    }}
}}");
        }
        
        private void AppendCategory(StringBuilder sb, string guid, List<string> propertyGuids)
        {
            sb.AppendLine($@"
{{
    ""m_SGVersion"": 0,
    ""m_Type"": ""UnityEditor.ShaderGraph.CategoryData"",
    ""m_ObjectId"": ""{guid}"",
    ""m_Name"": """",
    ""m_ChildObjectList"": [");
            
            var childRefs = propertyGuids.Select(g => $"        {{\n            \"m_Id\": \"{g}\"\n        }}");
            sb.AppendLine(string.Join(",\n", childRefs));
            sb.AppendLine("    ]");
            sb.AppendLine("}");
        }
        
        private void AppendTarget(StringBuilder sb, string guid, string subTargetGuid)
        {
            sb.AppendLine($@"
{{
    ""m_SGVersion"": 1,
    ""m_Type"": ""UnityEditor.Rendering.Universal.ShaderGraph.UniversalTarget"",
    ""m_ObjectId"": ""{guid}"",
    ""m_Datas"": [],
    ""m_ActiveSubTarget"": {{
        ""m_Id"": ""{subTargetGuid}""
    }},
    ""m_AllowMaterialOverride"": false,
    ""m_SurfaceType"": 0,
    ""m_ZTestMode"": 4,
    ""m_ZWriteControl"": 0,
    ""m_AlphaMode"": 0,
    ""m_RenderFace"": 2,
    ""m_AlphaClip"": false,
    ""m_CastShadows"": true,
    ""m_ReceiveShadows"": true,
    ""m_DisableTint"": false,
    ""m_AdditionalMotionVectorMode"": 0,
    ""m_AlembicMotionVectors"": false,
    ""m_SupportsLODCrossFade"": false,
    ""m_CustomEditorGUI"": """",
    ""m_SupportVFX"": false
}}");
        }
        
        private void AppendSubTarget(StringBuilder sb, string guid)
        {
            sb.AppendLine($@"
{{
    ""m_SGVersion"": 2,
    ""m_Type"": ""UnityEditor.Rendering.Universal.ShaderGraph.UniversalUnlitSubTarget"",
    ""m_ObjectId"": ""{guid}""
}}");
        }
        
        /// <summary>
        /// Main entry point - Generate from HLSL file
        /// </summary>
        public static void GenerateFromHLSL(string hlslFilePath, string hlslFileGUID, string outputPath, bool useTransparency)
        {
            try
            {
                string hlslContent = File.ReadAllText(hlslFilePath);
                
                var generator = new ShaderGraphJSONGenerator();
                var functionInfo = generator.ParseHLSLFunction(hlslContent);
                
                Debug.Log($"=== Parsing HLSL Function ===");
                Debug.Log($"Function: {functionInfo.FunctionName} → Display: {functionInfo.DisplayName}");
                Debug.Log($"Total Parameters: {functionInfo.Parameters.Count}");
                Debug.Log($"  Inputs: {functionInfo.InputParameters.Count}");
                Debug.Log($"  Outputs: {functionInfo.OutputParameters.Count}");
                
                foreach (var p in functionInfo.Parameters)
                {
                    Debug.Log($"  [{p.SlotId}] {(p.IsOutput ? "OUT" : "IN")} {p.Type} {p.Name}");
                }
                
                string json = generator.GenerateShaderGraphJSON(functionInfo, hlslFileGUID);
                
                File.WriteAllText(outputPath, json);
                
                Debug.Log($"✓ Generated ShaderGraph JSON: {outputPath}");
                Debug.Log($"  Function: {functionInfo.FunctionName}");
                Debug.Log($"  Inputs: {string.Join(", ", functionInfo.InputParameters.Select(p => $"{p.Type} {p.Name}"))}");
                Debug.Log($"  Outputs: {string.Join(", ", functionInfo.OutputParameters.Select(p => $"{p.Type} {p.Name}"))}");
            }
            catch (Exception ex)
            {
                Debug.LogError($"Failed to generate ShaderGraph: {ex.Message}\n{ex.StackTrace}");
                throw;
            }
        }
    }
}

#if UNITY_EDITOR
namespace ShaderGraphGenerator.Editor
{
    using UnityEditor;
    using UnityEngine;
    
    /// <summary>
    /// Unity Editor integration for easy ShaderGraph generation
    /// </summary>
    public class ShaderGraphGeneratorWindow : EditorWindow
    {
        private UnityEngine.Object hlslFile;
        private string outputPath = "Assets/ShaderGraphs/Generated.shadergraph";
        private bool useTransparency = false;
        
        [MenuItem("Tools/ShaderGraph Generator")]
        public static void ShowWindow()
        {
            GetWindow<ShaderGraphGeneratorWindow>("ShaderGraph Generator");
        }
        
        private void OnGUI()
        {
            GUILayout.Label("HLSL to ShaderGraph Generator", EditorStyles.boldLabel);
            EditorGUILayout.Space();
            
            hlslFile = EditorGUILayout.ObjectField("HLSL File", hlslFile, typeof(UnityEngine.Object), false);
            outputPath = EditorGUILayout.TextField("Output Path", outputPath);
            useTransparency = EditorGUILayout.Toggle("Use Transparency", useTransparency);
            
            EditorGUILayout.Space();
            
            if (GUILayout.Button("Generate ShaderGraph"))
            {
                if (hlslFile == null)
                {
                    EditorUtility.DisplayDialog("Error", "Please select an HLSL file", "OK");
                    return;
                }
                
                string hlslPath = AssetDatabase.GetAssetPath(hlslFile);
                string guid = AssetDatabase.AssetPathToGUID(hlslPath);
                
                try
                {
                    ShaderGraphJSONGenerator.GenerateFromHLSL(hlslPath, guid, outputPath, useTransparency);
                    AssetDatabase.Refresh();
                    EditorUtility.DisplayDialog("Success", $"ShaderGraph generated at:\n{outputPath}", "OK");
                }
                catch (System.Exception ex)
                {
                    EditorUtility.DisplayDialog("Error", $"Failed to generate ShaderGraph:\n{ex.Message}", "OK");
                }
            }
            
            EditorGUILayout.Space();
            EditorGUILayout.HelpBox(
                "This tool parses HLSL functions and generates complete ShaderGraph JSON files.\n\n" +
                "Requirements:\n" +
                "• HLSL function must follow format: void FunctionName(params)\n" +
                "• Use 'out' modifier for output parameters\n" +
                "• float2 parameters are connected to UV nodes\n" +
                "• Other parameters become shader properties\n\n" +
                "Transparency:\n" +
                "• Check 'Use Transparency' for shaders with alpha output\n" +
                "• float4 outputs automatically connect RGB→BaseColor, A→Alpha",
                MessageType.Info);
        }
    }
    
    /// <summary>
    /// Context menu for generating ShaderGraph from HLSL file
    /// </summary>
    public static class HLSLContextMenu
    {
        [MenuItem("Assets/Generate ShaderGraph from HLSL", false, 100)]
        private static void GenerateShaderGraph()
        {
            var selected = Selection.activeObject;
            if (selected == null) return;
            
            string hlslPath = AssetDatabase.GetAssetPath(selected);
            if (!hlslPath.EndsWith(".hlsl")) return;
            
            string guid = AssetDatabase.AssetPathToGUID(hlslPath);
            string outputPath = hlslPath.Replace(".hlsl", ".shadergraph");
            
            try
            {
                ShaderGraphJSONGenerator.GenerateFromHLSL(hlslPath, guid, outputPath, true);
                AssetDatabase.Refresh();
                EditorUtility.DisplayDialog("Success", $"ShaderGraph generated:\n{outputPath}", "OK");
            }
            catch (System.Exception ex)
            {
                EditorUtility.DisplayDialog("Error", $"Failed:\n{ex.Message}", "OK");
            }
        }
        
        [MenuItem("Assets/Generate ShaderGraph from HLSL", true)]
        private static bool ValidateGenerateShaderGraph()
        {
            var selected = Selection.activeObject;
            if (selected == null) return false;
            
            string path = AssetDatabase.GetAssetPath(selected);
            return path.EndsWith(".hlsl");
        }
    }
}
#endif

/* 
=============================================================================
USAGE INSTRUCTIONS
=============================================================================

METHOD 1: Editor Window
------------------------
1. In Unity, go to Tools > ShaderGraph Generator
2. Drag your HLSL file into the "HLSL File" field
3. Set output path (e.g., "Assets/ShaderGraphs/MyShader.shadergraph")
4. Click "Generate ShaderGraph"

METHOD 2: Context Menu
-----------------------
1. Right-click on any .hlsl file in Project window
2. Select "Generate ShaderGraph from HLSL"
3. ShaderGraph will be created in the same folder with .shadergraph extension

METHOD 3: Script (Runtime/Custom Tool)
---------------------------------------
ShaderGraphJSONGenerator.GenerateFromHLSL(
    "Assets/Shaders/PrimitiveFunction1.hlsl",
    "YOUR_HLSL_FILE_GUID",  // Get from Unity meta file
    "Assets/ShaderGraphs/Generated.shadergraph"
);

=============================================================================
HLSL REQUIREMENTS
=============================================================================

Your HLSL function must follow this format:

void FunctionName_float(float2 UV, float param1, out float Output)
{
    // Your shader code here
}

Key Points:
• Function must return void
• Use 'out' modifier for output parameters
• float2 inputs are automatically connected to UV nodes
• Other inputs become shader properties
• The '_float' suffix is removed in the ShaderGraph display name

Example:
void Circle01_float(float2 UV, float radius, out float Inside01)
{
    float2 p = UV - float2(0.5, 0.5);
    float sd = length(p) - radius;
    Inside01 = (sd <= 0.0) ? 1.0 : 0.0;
}

This creates:
• Custom Function Node named "Circle01"
• UV input (connected to UV node)
• "radius" property (exposed parameter)
• "Inside01" output (connected to Base Color)

=============================================================================
*/