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
            string targetGuid = GetOrCreateGuid("target");
            string subTargetGuid = GetOrCreateGuid("subtarget");

            // --- NEW GUIDS FOR MAINTEX SUPPORT ---
            string mainTexPropNode = GetOrCreateGuid("main_tex_prop_node");
            string mainTexPropSlot = GetOrCreateGuid("main_tex_prop_slot");
            string mainTexPropDef = GetOrCreateGuid("main_tex_prop_def");
            string sampleTexNode = GetOrCreateGuid("sample_tex_node");
            string multiplyNode = GetOrCreateGuid("multiply_node");

            // Explicit slot GUIDs for Sample Texture and Multiply to ensure connections work
            string sampleTexSlotUV = GetOrCreateGuid("sample_tex_slot_uv");
            string sampleTexSlotTex = GetOrCreateGuid("sample_tex_slot_tex");
            string sampleTexSlotRGBA = GetOrCreateGuid("sample_tex_slot_rgba");
            string multiplySlotA = GetOrCreateGuid("multiply_slot_a");
            string multiplySlotB = GetOrCreateGuid("multiply_slot_b");
            string multiplySlotOut = GetOrCreateGuid("multiply_slot_out");

            // GUIDs for output splitting
            string outputSplitNode = null;
            string outputVec3Node = null;
            var outputSplitSlotGuids = new Dictionary<string, string>(); // In, R, G, B, A
            var outputVec3SlotGuids = new Dictionary<string, string>(); // X, Y, Z, Out

            if (useTransparency)
            {
                var firstOutput_ = functionInfo.OutputParameters.FirstOrDefault();
                if (firstOutput_ != null && firstOutput_.Type.ToLower() == "float4")
                {
                    outputSplitNode = GetOrCreateGuid("output_split_node");
                    outputVec3Node = GetOrCreateGuid("output_vec3_node");
                    outputSplitSlotGuids["In"] = GetOrCreateGuid("output_split_in");
                    outputSplitSlotGuids["R"] = GetOrCreateGuid("output_split_r");
                    outputSplitSlotGuids["G"] = GetOrCreateGuid("output_split_g");
                    outputSplitSlotGuids["B"] = GetOrCreateGuid("output_split_b");
                    outputSplitSlotGuids["A"] = GetOrCreateGuid("output_split_a");
                    outputVec3SlotGuids["X"] = GetOrCreateGuid("output_vec3_x");
                    outputVec3SlotGuids["Y"] = GetOrCreateGuid("output_vec3_y");
                    outputVec3SlotGuids["Z"] = GetOrCreateGuid("output_vec3_z");
                    outputVec3SlotGuids["Out"] = GetOrCreateGuid("output_vec3_out");
                }
            }

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

            // Add MainTex property reference
            sb.AppendLine($"        {{\n            \"m_Id\": \"{mainTexPropDef}\"\n        }},");

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

            // Add MainTex specific nodes
            nodeRefs.Add($"        {{\n            \"m_Id\": \"{mainTexPropNode}\"\n        }}");
            nodeRefs.Add($"        {{\n            \"m_Id\": \"{sampleTexNode}\"\n        }}");
            nodeRefs.Add($"        {{\n            \"m_Id\": \"{multiplyNode}\"\n        }}");

            // Add split/vec3 nodes to the graph
            if (outputSplitNode != null)
            {
                nodeRefs.Add($"        {{\n            \"m_Id\": \"{outputSplitNode}\"\n        }}");
            }
            if (outputVec3Node != null)
            {
                nodeRefs.Add($"        {{\n            \"m_Id\": \"{outputVec3Node}\"\n        }}");
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

            // 1. UV node -> Custom function first float2 input
            if (!string.IsNullOrEmpty(uvParamName))
            {
                var uvParam = functionInfo.InputParameters.First(p => p.Name == uvParamName);
                edges.Add(FormatEdge(uvNode, 0, customFunctionNode, uvParam.SlotId));
            }
            // 1b. UV Node -> Sample Texture 2D UV Slot
            edges.Add(FormatEdge(uvNode, 0, sampleTexNode, 2)); // 2 is UV input on SampleTex

            // 2. Property nodes -> Custom function inputs
            foreach (var param in functionInfo.InputParameters)
            {
                if (propertyNodes.ContainsKey(param.Name))
                {
                    edges.Add(FormatEdge(propertyNodes[param.Name], 0, customFunctionNode, param.SlotId));
                }
            }

            // 3. MainTex Property -> Sample Texture 2D
            edges.Add(FormatEdge(mainTexPropNode, 0, sampleTexNode, 1)); // 1 is Texture input

            // 4. Connect Outputs via Multiply
            // We need to connect:
            // CustomFunction(Out) -> Multiply(A)
            // SampleTexture(RGBA) -> Multiply(B)
            // Multiply(Out) -> [SplitNode OR MasterStack]

            var firstOutput = functionInfo.OutputParameters.FirstOrDefault();
            if (firstOutput != null)
            {
                // A. Custom Function -> Multiply Node A (Slot 0)
                edges.Add(FormatEdge(customFunctionNode, firstOutput.SlotId, multiplyNode, 0));

                // B. Sample Texture RGBA -> Multiply Node B (Slot 1)
                edges.Add(FormatEdge(sampleTexNode, 4, multiplyNode, 1)); // 4 is RGBA output of SampleTex

                // C. Multiply Out (Slot 2) -> Final Destination
                string sourceNodeForFinal = multiplyNode;
                int sourceSlotForFinal = 2; // Output of multiply

                // Check if we are doing the split logic (Transparency)
                if (useTransparency && outputSplitNode != null && outputVec3Node != null && fragmentAlphaBlock != null)
                {
                    // Multiply Out -> Split In
                    edges.Add(FormatEdge(sourceNodeForFinal, sourceSlotForFinal, outputSplitNode, 0));

                    // Split R -> Vec3 X
                    edges.Add(FormatEdge(outputSplitNode, 1, outputVec3Node, 1));
                    // Split G -> Vec3 Y
                    edges.Add(FormatEdge(outputSplitNode, 2, outputVec3Node, 2));
                    // Split B -> Vec3 Z
                    edges.Add(FormatEdge(outputSplitNode, 3, outputVec3Node, 3));
                    // Vec3 Out -> Base Color In
                    edges.Add(FormatEdge(outputVec3Node, 0, fragmentBaseColorBlock, 0));
                    // Split A -> Alpha In
                    edges.Add(FormatEdge(outputSplitNode, 4, fragmentAlphaBlock, 0));
                }
                else
                {
                    // Opaque path: Multiply Out -> Base Color In
                    edges.Add(FormatEdge(sourceNodeForFinal, sourceSlotForFinal, fragmentBaseColorBlock, 0));
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

            // ===== NODE DEFINITIONS =====

            // Vertex/Fragment Blocks
            AppendBlockNode(sb, vertexPosBlock, "VertexDescription.Position", "Position", vertexPosSlot, "UnityEditor.ShaderGraph.PositionMaterialSlot");
            AppendBlockNode(sb, vertexNormalBlock, "VertexDescription.Normal", "Normal", vertexNormalSlot, "UnityEditor.ShaderGraph.NormalMaterialSlot");
            AppendBlockNode(sb, vertexTangentBlock, "VertexDescription.Tangent", "Tangent", vertexTangentSlot, "UnityEditor.ShaderGraph.TangentMaterialSlot");
            AppendBlockNode(sb, fragmentBaseColorBlock, "SurfaceDescription.BaseColor", "Base Color", fragmentBaseColorSlot, "UnityEditor.ShaderGraph.ColorRGBMaterialSlot");

            if (useTransparency && fragmentAlphaBlock != null)
            {
                string fragmentAlphaSlot = GetOrCreateGuid("fragment_alpha_slot");
                AppendBlockNode(sb, fragmentAlphaBlock, "SurfaceDescription.Alpha", "Alpha", fragmentAlphaSlot, "UnityEditor.ShaderGraph.Vector1MaterialSlot");
                AppendAlphaSlot(sb, fragmentAlphaSlot);
            }

            AppendPositionSlot(sb, vertexPosSlot);
            AppendNormalSlot(sb, vertexNormalSlot);
            AppendTangentSlot(sb, vertexTangentSlot);
            AppendColorRGBSlot(sb, fragmentBaseColorSlot);

            // Custom Function Node
            AppendCustomFunctionNode(sb, customFunctionNode, functionInfo, hlslFileGUID, functionSlots);
            foreach (var param in functionInfo.Parameters)
            {
                AppendFunctionSlot(sb, functionSlots[param.Name], param);
            }

            // UV Node
            AppendUVNode(sb, uvNode, uvOutputSlot);
            AppendUVSlot(sb, uvOutputSlot);

            // --- NEW NODE DEFINITIONS ---

            // MainTex Property Node
            AppendPropertyNode(sb, mainTexPropNode, mainTexPropDef, mainTexPropSlot, "MainTex");
            AppendTexture2DSlot(sb, mainTexPropSlot); // Property node output slot

            // MainTex Property Definition
            AppendTexture2DPropertyDefinition(sb, mainTexPropDef);

            // Sample Texture 2D Node
            AppendSampleTexture2DNode(sb, sampleTexNode, sampleTexSlotUV, sampleTexSlotTex, sampleTexSlotRGBA);

            // Multiply Node
            AppendMultiplyNode(sb, multiplyNode, multiplySlotA, multiplySlotB, multiplySlotOut);


            // Other Property nodes
            foreach (var kvp in propertyNodes)
            {
                var param = functionInfo.InputParameters.First(p => p.Name == kvp.Key);
                // Use the simplified signature for property node
                AppendPropertyNode(sb, kvp.Value, propertyDefs[kvp.Key], propertySlots[kvp.Key], param.Name);
                AppendPropertySlot(sb, propertySlots[kvp.Key], param);
            }

            // Property definitions
            foreach (var kvp in propertyDefs)
            {
                var param = functionInfo.InputParameters.First(p => p.Name == kvp.Key);
                AppendPropertyDefinition(sb, kvp.Value, param);
            }

            // Category - Add MainTex to list
            var allProps = new List<string> { mainTexPropDef };
            allProps.AddRange(propertyDefs.Values);
            AppendCategory(sb, categoryGuid, allProps);

            // Target
            AppendTarget(sb, targetGuid, subTargetGuid, useTransparency);
            AppendSubTarget(sb, subTargetGuid);

            // Output split nodes
            if (outputSplitNode != null)
            {
                AppendSplitNode(sb, outputSplitNode, outputSplitSlotGuids);
                AppendSplitSlotIn(sb, outputSplitSlotGuids["In"], 0);
                AppendSplitSlotOut(sb, outputSplitSlotGuids["R"], 1, "R");
                AppendSplitSlotOut(sb, outputSplitSlotGuids["G"], 2, "G");
                AppendSplitSlotOut(sb, outputSplitSlotGuids["B"], 3, "B");
                AppendSplitSlotOut(sb, outputSplitSlotGuids["A"], 4, "A");
            }
            if (outputVec3Node != null)
            {
                AppendVector3Node(sb, outputVec3Node, outputVec3SlotGuids);
                AppendVector3SlotIn(sb, outputVec3SlotGuids["X"], 1, "X");
                AppendVector3SlotIn(sb, outputVec3SlotGuids["Y"], 2, "Y");
                AppendVector3SlotIn(sb, outputVec3SlotGuids["Z"], 3, "Z");
                AppendVector3SlotOut(sb, outputVec3SlotGuids["Out"], 0, "Out");
            }

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

        // --- NEW APPENDERS ---

        private void AppendSampleTexture2DNode(StringBuilder sb, string guid, string uvSlot, string texSlot, string rgbaSlot)
        {
            sb.AppendLine($@"
{{
    ""m_SGVersion"": 0,
    ""m_Type"": ""UnityEditor.ShaderGraph.SampleTexture2DNode"",
    ""m_ObjectId"": ""{guid}"",
    ""m_Group"": {{ ""m_Id"": """" }},
    ""m_Name"": ""Sample Texture 2D"",
    ""m_DrawState"": {{
        ""m_Expanded"": true,
        ""m_Position"": {{ ""serializedVersion"": ""2"", ""x"": -280.0, ""y"": 450.0, ""width"": 208.0, ""height"": 437.0 }}
    }},
    ""m_Slots"": [
        {{
            ""m_Id"": ""{rgbaSlot}""
        }},
        {{
            ""m_Id"": ""{Guid.NewGuid().ToString("N")}""
        }},
        {{
            ""m_Id"": ""{Guid.NewGuid().ToString("N")}""
        }},
        {{
            ""m_Id"": ""{Guid.NewGuid().ToString("N")}""
        }},
        {{
            ""m_Id"": ""{Guid.NewGuid().ToString("N")}""
        }},
        {{
            ""m_Id"": ""{texSlot}""
        }},
        {{
            ""m_Id"": ""{uvSlot}""
        }},
        {{
            ""m_Id"": ""{Guid.NewGuid().ToString("N")}""
        }}
    ],
    ""synonyms"": [ ""tex2d"" ],
    ""m_Precision"": 0,
    ""m_PreviewExpanded"": false,
    ""m_DismissedVersion"": 0,
    ""m_PreviewMode"": 0,
    ""m_CustomColors"": {{ ""m_SerializableColors"": [] }},
    ""m_TextureType"": 0,
    ""m_NormalMapSpace"": 0,
    ""m_EnableGlobalMipBias"": true,
    ""m_MipSamplingMode"": 0
}}");
            // Add the actual slots definitions for the Sample Texture Node
            // Slot 4: RGBA Out
            sb.AppendLine($@"
{{
    ""m_SGVersion"": 0,
    ""m_Type"": ""UnityEditor.ShaderGraph.Vector4MaterialSlot"",
    ""m_ObjectId"": ""{rgbaSlot}"",
    ""m_Id"": 4,
    ""m_DisplayName"": ""RGBA"",
    ""m_SlotType"": 1,
    ""m_Hidden"": false,
    ""m_ShaderOutputName"": ""RGBA"",
    ""m_StageCapability"": 2,
    ""m_Value"": {{ ""x"": 0.0, ""y"": 0.0, ""z"": 0.0, ""w"": 0.0 }},
    ""m_DefaultValue"": {{ ""x"": 0.0, ""y"": 0.0, ""z"": 0.0, ""w"": 0.0 }},
    ""m_Labels"": []
}}");
            // Slot 1: Texture In
            sb.AppendLine($@"
{{
    ""m_SGVersion"": 0,
    ""m_Type"": ""UnityEditor.ShaderGraph.Texture2DInputMaterialSlot"",
    ""m_ObjectId"": ""{texSlot}"",
    ""m_Id"": 1,
    ""m_DisplayName"": ""Texture"",
    ""m_SlotType"": 0,
    ""m_Hidden"": false,
    ""m_ShaderOutputName"": ""Texture"",
    ""m_StageCapability"": 3,
    ""m_BareResource"": false,
    ""m_Texture"": {{ ""m_SerializedTexture"": ""{{\""texture\"":{{\""instanceID\"":0}}}}"", ""m_Guid"": """" }},
    ""m_DefaultType"": 0
}}");
            // Slot 2: UV In
            sb.AppendLine($@"
{{
    ""m_SGVersion"": 0,
    ""m_Type"": ""UnityEditor.ShaderGraph.UVMaterialSlot"",
    ""m_ObjectId"": ""{uvSlot}"",
    ""m_Id"": 2,
    ""m_DisplayName"": ""UV"",
    ""m_SlotType"": 0,
    ""m_Hidden"": false,
    ""m_ShaderOutputName"": ""UV"",
    ""m_StageCapability"": 3,
    ""m_Value"": {{ ""x"": 0.0, ""y"": 0.0 }},
    ""m_DefaultValue"": {{ ""x"": 0.0, ""y"": 0.0 }},
    ""m_Labels"": [],
    ""m_Channel"": 0
}}");
        }

        private void AppendMultiplyNode(StringBuilder sb, string guid, string slotA, string slotB, string slotOut)
        {
            sb.AppendLine($@"
{{
    ""m_SGVersion"": 0,
    ""m_Type"": ""UnityEditor.ShaderGraph.MultiplyNode"",
    ""m_ObjectId"": ""{guid}"",
    ""m_Group"": {{ ""m_Id"": """" }},
    ""m_Name"": ""Multiply"",
    ""m_DrawState"": {{
        ""m_Expanded"": true,
        ""m_Position"": {{ ""serializedVersion"": ""2"", ""x"": 50.0, ""y"": 200.0, ""width"": 208.0, ""height"": 302.0 }}
    }},
    ""m_Slots"": [
        {{ ""m_Id"": ""{slotA}"" }},
        {{ ""m_Id"": ""{slotB}"" }},
        {{ ""m_Id"": ""{slotOut}"" }}
    ],
    ""synonyms"": [ ""multiplication"", ""times"", ""x"" ],
    ""m_Precision"": 0,
    ""m_PreviewExpanded"": false,
    ""m_DismissedVersion"": 0,
    ""m_PreviewMode"": 0,
    ""m_CustomColors"": {{ ""m_SerializableColors"": [] }}
}}");
            // Slot A (0)
            sb.AppendLine($@"
{{
    ""m_SGVersion"": 0,
    ""m_Type"": ""UnityEditor.ShaderGraph.DynamicValueMaterialSlot"",
    ""m_ObjectId"": ""{slotA}"",
    ""m_Id"": 0,
    ""m_DisplayName"": ""A"",
    ""m_SlotType"": 0,
    ""m_Hidden"": false,
    ""m_ShaderOutputName"": ""A"",
    ""m_StageCapability"": 3,
    ""m_Value"": {{ ""e00"": 0.5, ""e01"": 0.5, ""e02"": 0.5, ""e03"": 0.5, ""e10"": 2.0, ""e11"": 2.0, ""e12"": 2.0, ""e13"": 2.0, ""e20"": 2.0, ""e21"": 2.0, ""e22"": 2.0, ""e23"": 2.0, ""e30"": 2.0, ""e31"": 2.0, ""e32"": 2.0, ""e33"": 2.0 }},
    ""m_DefaultValue"": {{ ""e00"": 1.0, ""e01"": 0.0, ""e02"": 0.0, ""e03"": 0.0, ""e10"": 0.0, ""e11"": 1.0, ""e12"": 0.0, ""e13"": 0.0, ""e20"": 0.0, ""e21"": 0.0, ""e22"": 1.0, ""e23"": 0.0, ""e30"": 0.0, ""e31"": 0.0, ""e32"": 0.0, ""e33"": 1.0 }}
}}");
            // Slot B (1)
            sb.AppendLine($@"
{{
    ""m_SGVersion"": 0,
    ""m_Type"": ""UnityEditor.ShaderGraph.DynamicValueMaterialSlot"",
    ""m_ObjectId"": ""{slotB}"",
    ""m_Id"": 1,
    ""m_DisplayName"": ""B"",
    ""m_SlotType"": 0,
    ""m_Hidden"": false,
    ""m_ShaderOutputName"": ""B"",
    ""m_StageCapability"": 3,
    ""m_Value"": {{ ""e00"": 2.0, ""e01"": 2.0, ""e02"": 2.0, ""e03"": 2.0, ""e10"": 2.0, ""e11"": 2.0, ""e12"": 2.0, ""e13"": 2.0, ""e20"": 2.0, ""e21"": 2.0, ""e22"": 2.0, ""e23"": 2.0, ""e30"": 2.0, ""e31"": 2.0, ""e32"": 2.0, ""e33"": 2.0 }},
    ""m_DefaultValue"": {{ ""e00"": 1.0, ""e01"": 0.0, ""e02"": 0.0, ""e03"": 0.0, ""e10"": 0.0, ""e11"": 1.0, ""e12"": 0.0, ""e13"": 0.0, ""e20"": 0.0, ""e21"": 0.0, ""e22"": 1.0, ""e23"": 0.0, ""e30"": 0.0, ""e31"": 0.0, ""e32"": 0.0, ""e33"": 1.0 }}
}}");
            // Slot Out (2)
            sb.AppendLine($@"
{{
    ""m_SGVersion"": 0,
    ""m_Type"": ""UnityEditor.ShaderGraph.DynamicValueMaterialSlot"",
    ""m_ObjectId"": ""{slotOut}"",
    ""m_Id"": 2,
    ""m_DisplayName"": ""Out"",
    ""m_SlotType"": 1,
    ""m_Hidden"": false,
    ""m_ShaderOutputName"": ""Out"",
    ""m_StageCapability"": 3,
    ""m_Value"": {{ ""e00"": 0.0, ""e01"": 0.0, ""e02"": 0.0, ""e03"": 0.0, ""e10"": 0.0, ""e11"": 0.0, ""e12"": 0.0, ""e13"": 0.0, ""e20"": 0.0, ""e21"": 0.0, ""e22"": 0.0, ""e23"": 0.0, ""e30"": 0.0, ""e31"": 0.0, ""e32"": 0.0, ""e33"": 0.0 }},
    ""m_DefaultValue"": {{ ""e00"": 1.0, ""e01"": 0.0, ""e02"": 0.0, ""e03"": 0.0, ""e10"": 0.0, ""e11"": 1.0, ""e12"": 0.0, ""e13"": 0.0, ""e20"": 0.0, ""e21"": 0.0, ""e22"": 1.0, ""e23"": 0.0, ""e30"": 0.0, ""e31"": 0.0, ""e32"": 0.0, ""e33"": 1.0 }}
}}");
        }

        private void AppendTexture2DPropertyDefinition(StringBuilder sb, string guid)
        {
            sb.AppendLine($@"
{{
    ""m_SGVersion"": 0,
    ""m_Type"": ""UnityEditor.ShaderGraph.Internal.Texture2DShaderProperty"",
    ""m_ObjectId"": ""{guid}"",
    ""m_Guid"": {{
        ""m_GuidSerialized"": ""{Guid.NewGuid().ToString()}""
    }},
    ""m_Name"": ""MainTex"",
    ""m_DefaultRefNameVersion"": 1,
    ""m_RefNameGeneratedByDisplayName"": ""MainTex"",
    ""m_DefaultReferenceName"": ""_MainTex"",
    ""m_OverrideReferenceName"": ""_MainTex"",
    ""m_GeneratePropertyBlock"": true,
    ""m_UseCustomSlotLabel"": false,
    ""m_CustomSlotLabel"": """",
    ""m_DismissedVersion"": 0,
    ""m_Precision"": 0,
    ""overrideHLSLDeclaration"": false,
    ""hlslDeclarationOverride"": 0,
    ""m_Hidden"": false,
    ""m_Value"": {{
        ""m_SerializedTexture"": ""{{\""texture\"":{{\""instanceID\"":0}}}}"",
        ""m_Guid"": """"
    }},
    ""isMainTexture"": false,
    ""useTilingAndOffset"": false,
    ""m_Modifiable"": true,
    ""m_DefaultType"": 0
}}");
        }

        private void AppendTexture2DSlot(StringBuilder sb, string guid)
        {
            sb.AppendLine($@"
{{
    ""m_SGVersion"": 0,
    ""m_Type"": ""UnityEditor.ShaderGraph.Texture2DMaterialSlot"",
    ""m_ObjectId"": ""{guid}"",
    ""m_Id"": 0,
    ""m_DisplayName"": ""MainTex"",
    ""m_SlotType"": 1,
    ""m_Hidden"": false,
    ""m_ShaderOutputName"": ""Out"",
    ""m_StageCapability"": 3,
    ""m_BareResource"": false
}}");
        }

        private void AppendPropertyNode(StringBuilder sb, string nodeGuid, string propDefGuid,
            string slotGuid, string displayName)
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
            ""x"": -580.0,
            ""y"": 400.0,
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

        // Keep this for backward compatibility or refactor to use the one above
        private void AppendPropertyNode(StringBuilder sb, string nodeGuid, string propDefGuid,
            string slotGuid, FunctionParameter param)
        {
            AppendPropertyNode(sb, nodeGuid, propDefGuid, slotGuid, param.Name);
        }

        // ... [The rest of the helper methods remain unchanged from your original file]
        // (AppendBlockNode, AppendPositionSlot, AppendNormalSlot, AppendTangentSlot, 
        //  AppendColorRGBSlot, AppendAlphaSlot, AppendCustomFunctionNode, AppendFunctionSlot,
        //  AppendUVNode, AppendUVSlot, AppendPropertySlot, AppendPropertyDefinition,
        //  AppendCategory, AppendTarget, AppendSubTarget, AppendSplitNode, etc.)

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

        private void AppendAlphaSlot(StringBuilder sb, string guid)
        {
            sb.AppendLine($@"
{{
    ""m_SGVersion"": 0,
    ""m_Type"": ""UnityEditor.ShaderGraph.Vector1MaterialSlot"",
    ""m_ObjectId"": ""{guid}"",
    ""m_Id"": 0,
    ""m_DisplayName"": ""Alpha"",
    ""m_SlotType"": 0,
    ""m_Hidden"": false,
    ""m_ShaderOutputName"": ""Alpha"",
    ""m_StageCapability"": 2,
    ""m_Value"": 1.0,
    ""m_DefaultValue"": 1.0,
    ""m_Labels"": []
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

        private void AppendPropertySlot(StringBuilder sb, string guid, FunctionParameter param)
        {
            string valueStr;
            string slotType = param.GetMaterialSlotType();

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
    ""m_Type"": ""{slotType}"",
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
            string extras = "";

            if (param.IsColorProperty())
            {
                propertyType = "UnityEditor.ShaderGraph.Internal.ColorShaderProperty";
                valueField = "    \"m_Value\": {\n        \"r\": 0.0,\n        \"g\": 0.0,\n        \"b\": 0.0,\n        \"a\": 1.0\n    },";
                extras = ",\n    \"isMainColor\": false,\n    \"m_ColorMode\": 0";
            }
            else
            {
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
    }}{extras}
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

        private void AppendTarget(StringBuilder sb, string guid, string subTargetGuid, bool useTransparency)
        {
            string surfaceType = useTransparency ? "1" : "0";
            string zWriteControl = useTransparency ? "2" : "0";

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
    ""m_SurfaceType"": {surfaceType},
    ""m_ZTestMode"": 4,
    ""m_ZWriteControl"": {zWriteControl},
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

        private void AppendSplitNode(StringBuilder sb, string guid, Dictionary<string, string> slotGuids)
        {
            sb.AppendLine($@"
{{
    ""m_SGVersion"": 0,
    ""m_Type"": ""UnityEditor.ShaderGraph.SplitNode"",
    ""m_ObjectId"": ""{guid}"",
    ""m_Group"": {{ ""m_Id"": """" }},
    ""m_Name"": ""Split"",
    ""m_DrawState"": {{
        ""m_Expanded"": true,
        ""m_Position"": {{
            ""serializedVersion"": ""2"",
            ""x"": -20.0,
            ""y"": 196.8,
            ""width"": 119.2,
            ""height"": 148.8
        }}
    }},
    ""m_Slots"": [
        {{ ""m_Id"": ""{slotGuids["In"]}"", ""m_SGVersion"": 0 }},
        {{ ""m_Id"": ""{slotGuids["R"]}"", ""m_SGVersion"": 0 }},
        {{ ""m_Id"": ""{slotGuids["G"]}"", ""m_SGVersion"": 0 }},
        {{ ""m_Id"": ""{slotGuids["B"]}"", ""m_SGVersion"": 0 }},
        {{ ""m_Id"": ""{slotGuids["A"]}"", ""m_SGVersion"": 0 }}
    ],
    ""synonyms"": [ ""separate"" ],
    ""m_Precision"": 0,
    ""m_PreviewExpanded"": true,
    ""m_DismissedVersion"": 0,
    ""m_PreviewMode"": 0,
    ""m_CustomColors"": {{ ""m_SerializableColors"": [] }}
}}");
        }

        private void AppendSplitSlotIn(StringBuilder sb, string guid, int id)
        {
            sb.AppendLine($@"
{{
    ""m_SGVersion"": 0,
    ""m_Type"": ""UnityEditor.ShaderGraph.DynamicVectorMaterialSlot"",
    ""m_ObjectId"": ""{guid}"",
    ""m_Id"": {id},
    ""m_DisplayName"": ""In"",
    ""m_SlotType"": 0,
    ""m_Hidden"": false,
    ""m_ShaderOutputName"": ""In"",
    ""m_StageCapability"": 3,
    ""m_Value"": {{ ""x"": 0.0, ""y"": 0.0, ""z"": 0.0, ""w"": 0.0 }},
    ""m_DefaultValue"": {{ ""x"": 0.0, ""y"": 0.0, ""z"": 0.0, ""w"": 0.0 }}
}}");
        }

        private void AppendSplitSlotOut(StringBuilder sb, string guid, int id, string name)
        {
            sb.AppendLine($@"
{{
    ""m_SGVersion"": 0,
    ""m_Type"": ""UnityEditor.ShaderGraph.Vector1MaterialSlot"",
    ""m_ObjectId"": ""{guid}"",
    ""m_Id"": {id},
    ""m_DisplayName"": ""{name}"",
    ""m_SlotType"": 1,
    ""m_Hidden"": false,
    ""m_ShaderOutputName"": ""{name}"",
    ""m_StageCapability"": 3,
    ""m_Value"": 0.0,
    ""m_DefaultValue"": 0.0,
    ""m_Labels"": []
}}");
        }

        private void AppendVector3Node(StringBuilder sb, string guid, Dictionary<string, string> slotGuids)
        {
            sb.AppendLine($@"
{{
    ""m_SGVersion"": 0,
    ""m_Type"": ""UnityEditor.ShaderGraph.Vector3Node"",
    ""m_ObjectId"": ""{guid}"",
    ""m_Group"": {{ ""m_Id"": """" }},
    ""m_Name"": ""Vector 3"",
    ""m_DrawState"": {{
        ""m_Expanded"": true,
        ""m_Position"": {{
            ""serializedVersion"": ""2"",
            ""x"": 150.0,
            ""y"": 196.8,
            ""width"": 128.0,
            ""height"": 124.8
        }}
    }},
    ""m_Slots"": [
        {{ ""m_Id"": ""{slotGuids["Out"]}"", ""m_SGVersion"": 0 }},
        {{ ""m_Id"": ""{slotGuids["X"]}"", ""m_SGVersion"": 0 }},
        {{ ""m_Id"": ""{slotGuids["Y"]}"", ""m_SGVersion"": 0 }},
        {{ ""m_Id"": ""{slotGuids["Z"]}"", ""m_SGVersion"": 0 }}
    ],
    ""synonyms"": [ ""3"", ""v3"", ""vec3"", ""float3"" ],
    ""m_Precision"": 0,
    ""m_PreviewExpanded"": true,
    ""m_DismissedVersion"": 0,
    ""m_PreviewMode"": 0,
    ""m_CustomColors"": {{ ""m_SerializableColors"": [] }},
    ""m_Value"": {{ ""x"": 0.0, ""y"": 0.0, ""z"": 0.0 }}
}}");
        }

        private void AppendVector3SlotIn(StringBuilder sb, string guid, int id, string name)
        {
            sb.AppendLine($@"
{{
    ""m_SGVersion"": 0,
    ""m_Type"": ""UnityEditor.ShaderGraph.Vector1MaterialSlot"",
    ""m_ObjectId"": ""{guid}"",
    ""m_Id"": {id},
    ""m_DisplayName"": ""{name}"",
    ""m_SlotType"": 0,
    ""m_Hidden"": false,
    ""m_ShaderOutputName"": ""{name}"",
    ""m_StageCapability"": 3,
    ""m_Value"": 0.0,
    ""m_DefaultValue"": 0.0,
    ""m_Labels"": [ ""{name}"" ]
}}");
        }

        private void AppendVector3SlotOut(StringBuilder sb, string guid, int id, string name)
        {
            sb.AppendLine($@"
{{
    ""m_SGVersion"": 0,
    ""m_Type"": ""UnityEditor.ShaderGraph.Vector3MaterialSlot"",
    ""m_ObjectId"": ""{guid}"",
    ""m_Id"": {id},
    ""m_DisplayName"": ""{name}"",
    ""m_SlotType"": 1,
    ""m_Hidden"": false,
    ""m_ShaderOutputName"": ""{name}"",
    ""m_StageCapability"": 3,
    ""m_Value"": {{ ""x"": 0.0, ""y"": 0.0, ""z"": 0.0 }},
    ""m_DefaultValue"": {{ ""x"": 0.0, ""y"": 0.0, ""z"": 0.0 }},
    ""m_Labels"": []
}}");
        }

        /// <summary>
        /// Main entry point - Generate from HLSL file
        /// </summary>
        public static HLSLFunctionInfo GenerateFromHLSL(string hlslFilePath, string hlslFileGUID, string outputPath, bool useTransparency)
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

                string json = generator.GenerateShaderGraphJSON(functionInfo, hlslFileGUID, "GeneratedShader", useTransparency);

                File.WriteAllText(outputPath, json);

                Debug.Log($"✓ Generated ShaderGraph JSON: {outputPath}");
                Debug.Log($"  Function: {functionInfo.FunctionName}");
                Debug.Log($"  Inputs: {string.Join(", ", functionInfo.InputParameters.Select(p => $"{p.Type} {p.Name}"))}");
                Debug.Log($"  Outputs: {string.Join(", ", functionInfo.OutputParameters.Select(p => $"{p.Type} {p.Name}"))}");

                return functionInfo;
            }
            catch (Exception ex)
            {
                Debug.LogError($"Failed to generate ShaderGraph: {ex.Message}\n{ex.StackTrace}");
                throw;
            }
        }
    }
}