using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.RegularExpressions;

namespace ShaderGraphGenerator
{
    /// <summary>
    /// Refactored to use the helper files (Models + Factories + JsonWriter) while preserving
    /// the exact graph topology and behavior of the previously working generator.
    /// </summary>
    public sealed class ShaderGraphJSONGenerator
    {
        private readonly Dictionary<string, string> guidMap = new();

        private string GetOrCreateGuid(string key)
        {
            if (!guidMap.TryGetValue(key, out var guid))
            {
                // Use the same compact format you used before (no dashes)
                guid = Guid.NewGuid().ToString("N");
                guidMap[key] = guid;
            }
            return guid;
        }

        // =====================================================================
        //  Public API (keep signatures convenient)
        // =====================================================================

        public HLSLFunctionInfo ParseHLSLFunction(string hlslCode)
        {
            var info = new HLSLFunctionInfo();

            // Header: <ret> <name>(<args>)
            var headerMatch = Regex.Match(
                hlslCode,
                @"(?<ret>\w+)\s+(?<name>\w+)\s*\((?<args>[^)]*)\)",
                RegexOptions.Multiline);

            if (!headerMatch.Success)
                throw new Exception("Failed to parse HLSL function header.");

            info.FunctionName = headerMatch.Groups["name"].Value.Trim();

            var args = headerMatch.Groups["args"].Value;
            var argParts = args.Split(new[] { ',' }, StringSplitOptions.RemoveEmptyEntries);

            int slotId = 0;
            foreach (var part in argParts)
            {
                var trimmed = part.Trim();

                // Supports: [in|out|inout] <type> <name>
                var m = Regex.Match(trimmed, @"(?:(in|out|inout)\s+)?(?<type>\w+)\s+(?<name>\w+)", RegexOptions.IgnoreCase);
                if (!m.Success) continue;

                string dir = (m.Groups[1].Success ? m.Groups[1].Value.ToLower() : "in");
                string type = m.Groups["type"].Value.Trim();
                string name = m.Groups["name"].Value.Trim();

                var p = new FunctionParameter
                {
                    Direction = dir,
                    Type = type,
                    Name = name,
                    SlotId = slotId++
                };

                info.Parameters.Add(p);

                if (dir == "out")
                    info.OutputParameters.Add(p);
                else
                    info.InputParameters.Add(p);
            }

            return info;
        }

        public string GenerateShaderGraphJSON(string hlslCode, string hlslFileGUID, bool usePixelation, bool useTransparency)
            => GenerateShaderGraphJSON(ParseHLSLFunction(hlslCode), hlslFileGUID, usePixelation, useTransparency);

        public string GenerateShaderGraphJSON(HLSLFunctionInfo functionInfo, string hlslFileGUID, bool usePixelation, bool useTransparency)
        {
            if (functionInfo == null) throw new ArgumentNullException(nameof(functionInfo));
            if (functionInfo.OutputParameters == null || functionInfo.OutputParameters.Count == 0)
                throw new Exception("No output parameter detected in the HLSL function.");

            // -----------------------------------------------------------------
            //  Deterministic object ids (same keys as your previous generator)
            // -----------------------------------------------------------------

            // Graph/root
            string graphGuid = GetOrCreateGuid("graph");
            string categoryGuid = GetOrCreateGuid("category");

            // Targets
            string targetGuid = GetOrCreateGuid("target");
            string subTargetGuid = GetOrCreateGuid("subtarget");

            // Nodes
            string customFunctionNodeGuid = GetOrCreateGuid("custom_function");
            string uvNodeGuid = GetOrCreateGuid("uv_node");
            string sampleTextureNodeGuid = GetOrCreateGuid("sample_tex_node");
            string multiplyNodeGuid = GetOrCreateGuid("multiply_node");

            // Block nodes
            string vertexPosNodeGuid = GetOrCreateGuid("vertex_pos_node");
            string vertexNormalNodeGuid = GetOrCreateGuid("vertex_normal_node");
            string vertexTangentNodeGuid = GetOrCreateGuid("vertex_tangent_node");
            string fragmentBaseColorNodeGuid = GetOrCreateGuid("fragment_basecolor_node");

            // Block slots
            string vertexPosSlotGuid = GetOrCreateGuid("vertex_pos_slot");
            string vertexNormalSlotGuid = GetOrCreateGuid("vertex_normal_slot");
            string vertexTangentSlotGuid = GetOrCreateGuid("vertex_tangent_slot");
            string fragmentBaseColorSlotGuid = GetOrCreateGuid("fragment_basecolor_slot");

            // UV slot
            string uvOutputSlotGuid = GetOrCreateGuid("uv_output_slot");

            // MainTex property + node + slot
            string mainTexPropDefGuid = GetOrCreateGuid("main_tex_prop_def");
            string mainTexPropNodeGuid = GetOrCreateGuid("main_tex_prop_node");
            string mainTexPropSlotGuid = GetOrCreateGuid("main_tex_prop_slot");

            // SampleTex slots (the 3 real ones)
            string sampleTexSlotRGBA = GetOrCreateGuid("sample_tex_slot_rgba");
            string sampleTexSlotTex = GetOrCreateGuid("sample_tex_slot_tex");
            string sampleTexSlotUV = GetOrCreateGuid("sample_tex_slot_uv");

            // Multiply slots
            string multiplySlotA = GetOrCreateGuid("multiply_slot_a");
            string multiplySlotB = GetOrCreateGuid("multiply_slot_b");
            string multiplySlotOut = GetOrCreateGuid("multiply_slot_out");

            // Pixelation (optional)
            string pixelCountPropDefGuid = null;
            string pixelCountPropNodeGuid = null;
            string pixelCountPropSlotGuid = null;

            string pixelMultiplyNodeGuid = null;
            string pixelMultiplySlotA = null;
            string pixelMultiplySlotB = null;
            string pixelMultiplySlotOut = null;

            string floorNodeGuid = null;
            string floorSlotOut = null; // Floor node lists Out first, but slot ids are In=0 Out=1
            string floorSlotIn = null;

            string divideNodeGuid = null;
            string divideSlotA = null;
            string divideSlotB = null;
            string divideSlotOut = null;

            if (usePixelation)
            {
                pixelCountPropDefGuid = GetOrCreateGuid("pixelcount_prop_def");
                pixelCountPropNodeGuid = GetOrCreateGuid("pixelcount_prop_node");
                pixelCountPropSlotGuid = GetOrCreateGuid("pixelcount_prop_slot");

                pixelMultiplyNodeGuid = GetOrCreateGuid("pixel_multiply_node");
                pixelMultiplySlotA = GetOrCreateGuid("pixel_multiply_slot_a");
                pixelMultiplySlotB = GetOrCreateGuid("pixel_multiply_slot_b");
                pixelMultiplySlotOut = GetOrCreateGuid("pixel_multiply_slot_out");

                floorNodeGuid = GetOrCreateGuid("floor_node");
                floorSlotOut = GetOrCreateGuid("floor_slot_out");
                floorSlotIn = GetOrCreateGuid("floor_slot_in");

                divideNodeGuid = GetOrCreateGuid("divide_node");
                divideSlotA = GetOrCreateGuid("divide_slot_a");
                divideSlotB = GetOrCreateGuid("divide_slot_b");
                divideSlotOut = GetOrCreateGuid("divide_slot_out");
            }

            // Transparency (optional) only when first output is float4
            bool splitAlpha = useTransparency && functionInfo.OutputParameters[0].Type.ToLower() == "float4";

            string outputSplitNodeGuid = null;
            string outputVec3NodeGuid = null;

            string splitIn = null, splitR = null, splitG = null, splitB = null, splitA = null;
            string vec3Out = null, vec3X = null, vec3Y = null, vec3Z = null;

            string alphaBlockNodeGuid = null;
            string alphaBlockSlotGuid = null;

            if (splitAlpha)
            {
                outputSplitNodeGuid = GetOrCreateGuid("output_split_node");
                outputVec3NodeGuid = GetOrCreateGuid("output_vec3_node");

                splitIn = GetOrCreateGuid("output_split_in");
                splitR = GetOrCreateGuid("output_split_r");
                splitG = GetOrCreateGuid("output_split_g");
                splitB = GetOrCreateGuid("output_split_b");
                splitA = GetOrCreateGuid("output_split_a");

                vec3Out = GetOrCreateGuid("output_vec3_out");
                vec3X = GetOrCreateGuid("output_vec3_x");
                vec3Y = GetOrCreateGuid("output_vec3_y");
                vec3Z = GetOrCreateGuid("output_vec3_z");

                alphaBlockNodeGuid = GetOrCreateGuid("fragment_alpha_node");
                alphaBlockSlotGuid = GetOrCreateGuid("fragment_alpha_slot");
            }

            // Function parameter slots
            var functionSlotGuids = new Dictionary<string, string>();
            foreach (var p in functionInfo.Parameters)
                functionSlotGuids[p.Name] = GetOrCreateGuid($"cf_slot_{p.Name}");

            // Input properties (all non-UV float2 inputs become properties; the first float2 becomes UV input)
            string uvParamName = functionInfo.InputParameters.FirstOrDefault(p => p.Type.ToLower() == "float2")?.Name;

            var propertyDefGuids = new Dictionary<string, string>();
            var propertyNodeGuids = new Dictionary<string, string>();
            var propertySlotGuids = new Dictionary<string, string>();

            foreach (var p in functionInfo.InputParameters)
            {
                if (p.Name == uvParamName) continue;

                propertyDefGuids[p.Name] = GetOrCreateGuid($"prop_def_{p.Name}");
                propertyNodeGuids[p.Name] = GetOrCreateGuid($"prop_node_{p.Name}");
                propertySlotGuids[p.Name] = GetOrCreateGuid($"prop_slot_{p.Name}");
            }

            // -----------------------------------------------------------------
            //  Build in-memory model (factories) then serialize (writer)
            // -----------------------------------------------------------------

            var nodeFactory = new ShaderGraphNodeFactory();
            var slotFactory = new ShaderGraphSlotFactory();
            var propFactory = new ShaderGraphPropertyFactory();

            var graph = new ShaderGraphDataModel(graphGuid);

            // --- Properties + refs ---
            var mainTexProp = propFactory.CreateTexture2D(mainTexPropDefGuid, "MainTex", "MainTex", useTilingAndOffset: false, isMainTexture: false, defaultType: 0);
            graph.PropertyRefs.Add(mainTexProp.AsRef());
            graph.Definitions.Add(mainTexProp);

            ShaderPropertyModel pixelCountProp = null;
            if (usePixelation)
            {
                // Match your working defaults: PixelCount (float) default 50 range 1..256
                pixelCountProp = propFactory.CreateVector1(pixelCountPropDefGuid, "PixelCount", "PixelCount", defaultValue: 50f, floatType: 0, rangeMin: 1f, rangeMax: 256f);
                graph.PropertyRefs.Add(pixelCountProp.AsRef());
                graph.Definitions.Add(pixelCountProp);
            }

            foreach (var kvp in propertyDefGuids)
            {
                var p = functionInfo.InputParameters.First(x => x.Name == kvp.Key);
                var prop = CreatePropertyForParam(propFactory, kvp.Value, p);
                graph.PropertyRefs.Add(prop.AsRef());
                graph.Definitions.Add(prop);
            }

            // --- Category (properties list) ---
            var category = new CategoryDataModel(categoryGuid, name: "", sgVersion: 0);
            category.AddProperty(mainTexProp.AsRef());
            if (pixelCountProp != null) category.AddProperty(pixelCountProp.AsRef());
            foreach (var kvp in propertyDefGuids) category.AddProperty(new PropertyRef(kvp.Value));
            graph.Categories.Add(category);
            graph.Definitions.Add(category);

            // --- Targets ---
            graph.Targets.Add(BuildUniversalTarget(targetGuid, subTargetGuid, useTransparency));
            graph.Targets.Add(BuildUniversalUnlitSubTarget(subTargetGuid));
            graph.Definitions.AddRange(graph.Targets);

            // --- Nodes refs ---
            // Master stack block nodes
            var nPos = nodeFactory.CreateBlockNode(vertexPosNodeGuid, "VertexDescription.Position", vertexPosSlotGuid, x: -26.4f, y: -243.2f);
            var nNrm = nodeFactory.CreateBlockNode(vertexNormalNodeGuid, "VertexDescription.Normal", vertexNormalSlotGuid, x: -26.4f, y: -203.2f);
            var nTan = nodeFactory.CreateBlockNode(vertexTangentNodeGuid, "VertexDescription.Tangent", vertexTangentSlotGuid, x: -26.4f, y: -163.2f);
            var nBase = nodeFactory.CreateBlockNode(fragmentBaseColorNodeGuid, "SurfaceDescription.BaseColor", fragmentBaseColorSlotGuid, x: 2.4f, y: 233.6f);

            graph.NodeRefs.Add(nPos.AsRef());
            graph.NodeRefs.Add(nNrm.AsRef());
            graph.NodeRefs.Add(nTan.AsRef());
            graph.NodeRefs.Add(nBase.AsRef());

            graph.Definitions.Add(nPos);
            graph.Definitions.Add(nNrm);
            graph.Definitions.Add(nTan);
            graph.Definitions.Add(nBase);

            graph.Definitions.Add(slotFactory.CreatePositionBlockSlot(vertexPosSlotGuid));
            graph.Definitions.Add(slotFactory.CreateNormalBlockSlot(vertexNormalSlotGuid));
            graph.Definitions.Add(slotFactory.CreateTangentBlockSlot(vertexTangentSlotGuid));
            graph.Definitions.Add(slotFactory.CreateBaseColorBlockSlot(fragmentBaseColorSlotGuid));

            // UV node + slot
            var uvNode = nodeFactory.CreateUVNode(uvNodeGuid, uvOutputSlotGuid, x: -664f, y: 41.6f, outputChannel: 0);
            graph.NodeRefs.Add(uvNode.AsRef());
            graph.Definitions.Add(uvNode);
            graph.Definitions.Add(slotFactory.CreateUVNodeOut(uvOutputSlotGuid));

            // Pixelation chain
            if (usePixelation)
            {
                var pNode = nodeFactory.CreatePropertyNode(pixelCountPropNodeGuid, pixelCountPropSlotGuid, pixelCountPropDefGuid, x: -580f, y: 250f);
                graph.NodeRefs.Add(pNode.AsRef());
                graph.Definitions.Add(pNode);
                graph.Definitions.Add(slotFactory.CreatePropertyVector1Out(pixelCountPropSlotGuid, "PixelCount"));

                var mul = nodeFactory.CreateMultiplyNode(pixelMultiplyNodeGuid, pixelMultiplySlotA, pixelMultiplySlotB, pixelMultiplySlotOut, x: -450f, y: 196.8f);
                graph.NodeRefs.Add(mul.AsRef());
                graph.Definitions.Add(mul);
                graph.Definitions.Add(slotFactory.CreateMultiplyA(pixelMultiplySlotA));
                graph.Definitions.Add(slotFactory.CreateMultiplyB(pixelMultiplySlotB));
                graph.Definitions.Add(slotFactory.CreateMultiplyOut(pixelMultiplySlotOut));

                // Floor node lists [Out, In] in node slot list, but slot ids remain (In=0, Out=1)
                var floor = nodeFactory.CreateFloorNode(floorNodeGuid, floorSlotOut, floorSlotIn, x: -250f, y: 196.8f);
                graph.NodeRefs.Add(floor.AsRef());
                graph.Definitions.Add(floor);
                graph.Definitions.Add(slotFactory.CreateFloorIn(floorSlotIn));
                graph.Definitions.Add(slotFactory.CreateFloorOut(floorSlotOut));

                var div = nodeFactory.CreateDivideNode(divideNodeGuid, divideSlotA, divideSlotB, divideSlotOut, x: -80f, y: 196.8f);
                graph.NodeRefs.Add(div.AsRef());
                graph.Definitions.Add(div);
                graph.Definitions.Add(slotFactory.CreateDivideA(divideSlotA));
                graph.Definitions.Add(slotFactory.CreateDivideB(divideSlotB));
                graph.Definitions.Add(slotFactory.CreateDivideOut(divideSlotOut));
            }

            // MainTex property node + slot
            var mainTexNode = nodeFactory.CreatePropertyNode(mainTexPropNodeGuid, mainTexPropSlotGuid, mainTexPropDefGuid, x: -580f, y: 400f);
            graph.NodeRefs.Add(mainTexNode.AsRef());
            graph.Definitions.Add(mainTexNode);
            graph.Definitions.Add(slotFactory.CreatePropertyTexture2DOut(mainTexPropSlotGuid, "MainTex"));

            // Sample Texture 2D node (with the same slot list pattern your old JSON used)
            // classic order: [ RGBA, random, random, random, random, Texture, UV, random ]
            var stRand1 = GetOrCreateGuid("sample_tex_slot_rand1");
            var stRand2 = GetOrCreateGuid("sample_tex_slot_rand2");
            var stRand3 = GetOrCreateGuid("sample_tex_slot_rand3");
            var stRand4 = GetOrCreateGuid("sample_tex_slot_rand4");
            var stRand5 = GetOrCreateGuid("sample_tex_slot_rand5");

            var sampleSlotsOrder = new List<string>
            {
                sampleTexSlotRGBA,
                stRand1,
                stRand2,
                stRand3,
                stRand4,
                sampleTexSlotTex,
                sampleTexSlotUV,
                stRand5
            };

            var sampleNode = nodeFactory.CreateSampleTexture2DNode(sampleTextureNodeGuid, sampleSlotsOrder, x: -280f, y: 450f, width: 208f, height: 437f);
            graph.NodeRefs.Add(sampleNode.AsRef());
            graph.Definitions.Add(sampleNode);

            // Only define the 3 slots you previously defined (RGBA, Texture, UV)
            graph.Definitions.Add(slotFactory.CreateSampleTexture2DRGBAOut(sampleTexSlotRGBA));
            graph.Definitions.Add(slotFactory.CreateSampleTexture2DTextureIn(sampleTexSlotTex));
            graph.Definitions.Add(slotFactory.CreateSampleTexture2DUVIn(sampleTexSlotUV, channel: 0));

            // Multiply node (mask * texture)
            var mulNode = nodeFactory.CreateMultiplyNode(multiplyNodeGuid, multiplySlotA, multiplySlotB, multiplySlotOut, x: 10f, y: 520f);
            graph.NodeRefs.Add(mulNode.AsRef());
            graph.Definitions.Add(mulNode);
            graph.Definitions.Add(slotFactory.CreateMultiplyA(multiplySlotA));
            graph.Definitions.Add(slotFactory.CreateMultiplyB(multiplySlotB));
            graph.Definitions.Add(slotFactory.CreateMultiplyOut(multiplySlotOut));

            // Function input property nodes
            float propY = 600f;
            foreach (var kvp in propertyNodeGuids)
            {
                var param = functionInfo.InputParameters.First(p => p.Name == kvp.Key);

                var pn = nodeFactory.CreatePropertyNode(kvp.Value, propertySlotGuids[kvp.Key], propertyDefGuids[kvp.Key], x: -580f, y: propY);
                graph.NodeRefs.Add(pn.AsRef());
                graph.Definitions.Add(pn);

                graph.Definitions.Add(CreatePropertyNodeOutSlot(slotFactory, propertySlotGuids[kvp.Key], param));

                propY += 120f;
            }

            // Custom Function Node + slots (slot order must match signature)
            var cfSlotOrder = functionInfo.Parameters.Select(p => functionSlotGuids[p.Name]).ToList();

            var cfNode = nodeFactory.CreateCustomFunctionNode(
                nodeId: customFunctionNodeGuid,
                displayName: functionInfo.FunctionName,
                slotObjectIdsInOrder: cfSlotOrder,
                hlslFileGuid: hlslFileGUID,
                functionNameForNode: functionInfo.FunctionName,
                usePragmas: true,
                x: -280f,
                y: 196.8f,
                width: 208f,
                height: 301.6f);

            graph.NodeRefs.Add(cfNode.AsRef());
            graph.Definitions.Add(cfNode);

            // Function param slots
            foreach (var p in functionInfo.Parameters)
            {
                var matSlotType = GetMaterialSlotType(p);
                var s = slotFactory.CreateFunctionParamSlot(
                    objectId: functionSlotGuids[p.Name],
                    slotId: p.SlotId,
                    paramName: p.Name,
                    materialSlotType: matSlotType,
                    isOutput: p.Direction == "out",
                    shaderOutputName: p.Name);

                // Keep float3 vertex outputs as Vertex stage capability
                if (p.Direction == "out" && p.Type.Equals("float3", StringComparison.OrdinalIgnoreCase))
                    s.SetStageCapability(ShaderGraphSlotFactory.Stage_Vertex);

                graph.Definitions.Add(s);
            }

            // Optional Split + Vector3 + Alpha block
            if (splitAlpha)
            {
                var splitNode = nodeFactory.CreateSplitNode(outputSplitNodeGuid, splitIn, splitR, splitG, splitB, splitA, x: -20f, y: 196.8f);
                graph.NodeRefs.Add(splitNode.AsRef());
                graph.Definitions.Add(splitNode);

                graph.Definitions.Add(slotFactory.CreateSplitIn(splitIn));
                graph.Definitions.Add(slotFactory.CreateSplitOutR(splitR));
                graph.Definitions.Add(slotFactory.CreateSplitOutG(splitG));
                graph.Definitions.Add(slotFactory.CreateSplitOutB(splitB));
                graph.Definitions.Add(slotFactory.CreateSplitOutA(splitA));

                var vec3Node = nodeFactory.CreateVector3Node(outputVec3NodeGuid, vec3Out, vec3X, vec3Y, vec3Z, x: 150f, y: 196.8f);
                graph.NodeRefs.Add(vec3Node.AsRef());
                graph.Definitions.Add(vec3Node);

                graph.Definitions.Add(slotFactory.CreateVector3NodeOut(vec3Out));
                graph.Definitions.Add(slotFactory.CreateVector3NodeInX(vec3X));
                graph.Definitions.Add(slotFactory.CreateVector3NodeInY(vec3Y));
                graph.Definitions.Add(slotFactory.CreateVector3NodeInZ(vec3Z));

                var alphaNode = nodeFactory.CreateBlockNode(alphaBlockNodeGuid, "SurfaceDescription.Alpha", alphaBlockSlotGuid, x: 2.4f, y: 273.6f);
                graph.NodeRefs.Add(alphaNode.AsRef());
                graph.Definitions.Add(alphaNode);
                graph.Definitions.Add(slotFactory.CreateAlphaBlockSlot(alphaBlockSlotGuid));
            }

            // -----------------------------------------------------------------
            //  Edges (topology identical)
            // -----------------------------------------------------------------

            // Custom function vertex outputs -> vertex blocks
            var outPos = FindVertexOut(functionInfo, "position");
            var outNrm = FindVertexOut(functionInfo, "normal");
            var outTan = FindVertexOut(functionInfo, "tangent");

            if (outPos != null) graph.Edges.Add(new EdgeModel(new SlotRef(new NodeRef(customFunctionNodeGuid), outPos.SlotId), new SlotRef(new NodeRef(vertexPosNodeGuid), 0)));
            if (outNrm != null) graph.Edges.Add(new EdgeModel(new SlotRef(new NodeRef(customFunctionNodeGuid), outNrm.SlotId), new SlotRef(new NodeRef(vertexNormalNodeGuid), 0)));
            if (outTan != null) graph.Edges.Add(new EdgeModel(new SlotRef(new NodeRef(customFunctionNodeGuid), outTan.SlotId), new SlotRef(new NodeRef(vertexTangentNodeGuid), 0)));

            // Block inputs -> custom function inputs (Position/Normal/Tangent)
            var inPos = FindVertexIn(functionInfo, "position");
            var inNrm = FindVertexIn(functionInfo, "normal");
            var inTan = FindVertexIn(functionInfo, "tangent");

            if (inPos != null) graph.Edges.Add(new EdgeModel(new SlotRef(new NodeRef(vertexPosNodeGuid), 0), new SlotRef(new NodeRef(customFunctionNodeGuid), inPos.SlotId)));
            if (inNrm != null) graph.Edges.Add(new EdgeModel(new SlotRef(new NodeRef(vertexNormalNodeGuid), 0), new SlotRef(new NodeRef(customFunctionNodeGuid), inNrm.SlotId)));
            if (inTan != null) graph.Edges.Add(new EdgeModel(new SlotRef(new NodeRef(vertexTangentNodeGuid), 0), new SlotRef(new NodeRef(customFunctionNodeGuid), inTan.SlotId)));

            // UV -> custom function input (the first float2 input) (the first float2 input)
            if (!string.IsNullOrEmpty(uvParamName))
            {
                graph.Edges.Add(new EdgeModel(
                    new SlotRef(new NodeRef(uvNodeGuid), 0),
                    new SlotRef(new NodeRef(customFunctionNodeGuid), GetSlotId(functionInfo, uvParamName))));
            }

            // Other property nodes -> custom function inputs
            foreach (var p in functionInfo.InputParameters)
            {
                if (p.Name == uvParamName) continue;

                graph.Edges.Add(new EdgeModel(
                    new SlotRef(new NodeRef(propertyNodeGuids[p.Name]), 0),
                    new SlotRef(new NodeRef(customFunctionNodeGuid), GetSlotId(functionInfo, p.Name))));
            }

            // UV pipeline into Sample Texture UV
            if (usePixelation)
            {
                // UV -> PixelMultiply A
                graph.Edges.Add(new EdgeModel(new SlotRef(new NodeRef(uvNodeGuid), 0), new SlotRef(new NodeRef(pixelMultiplyNodeGuid), 0)));
                // PixelCount -> PixelMultiply B
                graph.Edges.Add(new EdgeModel(new SlotRef(new NodeRef(pixelCountPropNodeGuid), 0), new SlotRef(new NodeRef(pixelMultiplyNodeGuid), 1)));
                // PixelMultiply Out -> Floor In (Floor In slot id = 0)
                graph.Edges.Add(new EdgeModel(new SlotRef(new NodeRef(pixelMultiplyNodeGuid), 2), new SlotRef(new NodeRef(floorNodeGuid), 0)));
                // Floor Out (id 1) -> Divide A
                graph.Edges.Add(new EdgeModel(new SlotRef(new NodeRef(floorNodeGuid), 1), new SlotRef(new NodeRef(divideNodeGuid), 0)));
                // PixelCount -> Divide B
                graph.Edges.Add(new EdgeModel(new SlotRef(new NodeRef(pixelCountPropNodeGuid), 0), new SlotRef(new NodeRef(divideNodeGuid), 1)));
                // Divide Out -> SampleTex UV (slot id 2)
                graph.Edges.Add(new EdgeModel(new SlotRef(new NodeRef(divideNodeGuid), 2), new SlotRef(new NodeRef(sampleTextureNodeGuid), 2)));
            }
            else
            {
                graph.Edges.Add(new EdgeModel(new SlotRef(new NodeRef(uvNodeGuid), 0), new SlotRef(new NodeRef(sampleTextureNodeGuid), 2)));
            }

            // MainTex -> SampleTex Texture (slot id 1)
            graph.Edges.Add(new EdgeModel(new SlotRef(new NodeRef(mainTexPropNodeGuid), 0), new SlotRef(new NodeRef(sampleTextureNodeGuid), 1)));

            // SampleTex RGBA (slot id 4) -> Multiply B
            graph.Edges.Add(new EdgeModel(new SlotRef(new NodeRef(sampleTextureNodeGuid), 4), new SlotRef(new NodeRef(multiplyNodeGuid), 1)));

            // Custom function primary output -> Multiply A
            var mainOut = FindMainOutput(functionInfo);
            graph.Edges.Add(new EdgeModel(new SlotRef(new NodeRef(customFunctionNodeGuid), mainOut.SlotId), new SlotRef(new NodeRef(multiplyNodeGuid), 0)));

            // Multiply Out -> BaseColor OR Split/Alpha pipeline
            if (splitAlpha)
            {
                graph.Edges.Add(new EdgeModel(new SlotRef(new NodeRef(multiplyNodeGuid), 2), new SlotRef(new NodeRef(outputSplitNodeGuid), 0)));

                // Split RGB -> Vector3 XYZ
                graph.Edges.Add(new EdgeModel(new SlotRef(new NodeRef(outputSplitNodeGuid), 1), new SlotRef(new NodeRef(outputVec3NodeGuid), 1)));
                graph.Edges.Add(new EdgeModel(new SlotRef(new NodeRef(outputSplitNodeGuid), 2), new SlotRef(new NodeRef(outputVec3NodeGuid), 2)));
                graph.Edges.Add(new EdgeModel(new SlotRef(new NodeRef(outputSplitNodeGuid), 3), new SlotRef(new NodeRef(outputVec3NodeGuid), 3)));

                // Vec3 Out -> BaseColor
                graph.Edges.Add(new EdgeModel(new SlotRef(new NodeRef(outputVec3NodeGuid), 0), new SlotRef(new NodeRef(fragmentBaseColorNodeGuid), 0)));

                // Split A -> Alpha block
                graph.Edges.Add(new EdgeModel(new SlotRef(new NodeRef(outputSplitNodeGuid), 4), new SlotRef(new NodeRef(alphaBlockNodeGuid), 0)));
            }
            else
            {
                graph.Edges.Add(new EdgeModel(new SlotRef(new NodeRef(multiplyNodeGuid), 2), new SlotRef(new NodeRef(fragmentBaseColorNodeGuid), 0)));
            }

            return ShaderGraphJsonWriter.Write(graph);
        }

        // =====================================================================
        //  Helpers
        // =====================================================================


        private static FunctionParameter FindVertexOut(HLSLFunctionInfo info, string keyword)
        {
            var p = info.OutputParameters.FirstOrDefault(x => x.Type.Equals("float3", StringComparison.OrdinalIgnoreCase)
                                                             && x.Name.IndexOf(keyword, StringComparison.OrdinalIgnoreCase) >= 0);
            if (p != null) return p;

            // Fallback: first float3 out parameters in order
            return info.OutputParameters.FirstOrDefault(x => x.Type.Equals("float3", StringComparison.OrdinalIgnoreCase));
        }

        private static FunctionParameter FindVertexIn(HLSLFunctionInfo info, string keyword)
        {
            var p = info.InputParameters.FirstOrDefault(x => x.Type.Equals("float3", StringComparison.OrdinalIgnoreCase)
                                                            && x.Name.IndexOf(keyword, StringComparison.OrdinalIgnoreCase) >= 0);
            if (p != null) return p;

            // Fallback: first float3 inputs in order
            return info.InputParameters.FirstOrDefault(x => x.Type.Equals("float3", StringComparison.OrdinalIgnoreCase));
        }

        private static FunctionParameter FindMainOutput(HLSLFunctionInfo info)
        {
            // Prefer the first out param that is NOT a float3 vertex output (mask/rgba etc)
            var p = info.OutputParameters.FirstOrDefault(x => !x.Type.Equals("float3", StringComparison.OrdinalIgnoreCase));
            return p ?? info.OutputParameters[0];
        }
        private static int GetSlotId(HLSLFunctionInfo info, string paramName)
        {
            var p = info.Parameters.FirstOrDefault(x => x.Name == paramName);
            if (p == null) throw new Exception($"Missing function parameter '{paramName}'. Keep the same parameter naming as your working version.");
            return p.SlotId;
        }

        private static string GetMaterialSlotType(FunctionParameter p)
        {
            // Colors are encoded as Vector4 slots in your helper factory,
            // while numeric values map to vector arity.
            if (p.IsColorProperty()) return ShaderGraphSlotFactory.S_Vector4;

            switch (p.Type.ToLower())
            {
                case "float": return ShaderGraphSlotFactory.S_Vector1;
                case "float2": return ShaderGraphSlotFactory.S_Vector2;
                case "float3": return ShaderGraphSlotFactory.S_Vector3;
                case "float4": return ShaderGraphSlotFactory.S_Vector4;
                default: return ShaderGraphSlotFactory.S_Vector1;
            }
        }

        private static ShaderPropertyModel CreatePropertyForParam(ShaderGraphPropertyFactory propFactory, string propertyObjectId, FunctionParameter param)
        {
            string refName = param.Name;

            if (param.IsColorProperty())
                return propFactory.CreateColor(propertyObjectId, param.Name, refName, r: 0f, g: 0f, b: 0f, a: 1f, colorMode: 0, isMainColor: false);

            switch (param.Type.ToLower())
            {
                case "float": return propFactory.CreateVector1(propertyObjectId, param.Name, refName, defaultValue: 0f, floatType: 0, rangeMin: 0f, rangeMax: 1f);
                case "float2": return propFactory.CreateVector2(propertyObjectId, param.Name, refName, x: 0f, y: 0f);
                case "float3": return propFactory.CreateVector3(propertyObjectId, param.Name, refName, x: 0f, y: 0f, z: 0f);
                case "float4": return propFactory.CreateVector4(propertyObjectId, param.Name, refName, x: 0f, y: 0f, z: 0f, w: 0f);
                default: return propFactory.CreateVector1(propertyObjectId, param.Name, refName, defaultValue: 0f, floatType: 0, rangeMin: 0f, rangeMax: 1f);
            }
        }

        private static SlotModel CreatePropertyNodeOutSlot(ShaderGraphSlotFactory slotFactory, string slotObjectId, FunctionParameter param)
        {
            if (param.IsColorProperty())
            {
                var s = new SlotModel(ShaderGraphSlotFactory.S_Vector4, slotObjectId, id: 0, displayName: param.Name, slotType: ShaderGraphSlotFactory.Output, shaderOutputName: "Out")
                    .SetStageCapability(ShaderGraphSlotFactory.Stage_All)
                    .SetValue(ShaderGraphSlotFactory.V4(0, 0, 0, 0), ShaderGraphSlotFactory.V4(0, 0, 0, 0));
                s.Labels = new List<string>();
                return s;
            }

            switch (param.Type.ToLower())
            {
                case "float":
                    return slotFactory.CreatePropertyVector1Out(slotObjectId, param.Name);

                case "float2":
                    return new SlotModel(ShaderGraphSlotFactory.S_Vector2, slotObjectId, 0, param.Name, ShaderGraphSlotFactory.Output, "Out")
                        .SetStageCapability(ShaderGraphSlotFactory.Stage_All)
                        .SetValue(ShaderGraphSlotFactory.V2(0, 0), ShaderGraphSlotFactory.V2(0, 0));

                case "float3":
                    return new SlotModel(ShaderGraphSlotFactory.S_Vector3, slotObjectId, 0, param.Name, ShaderGraphSlotFactory.Output, "Out")
                        .SetStageCapability(ShaderGraphSlotFactory.Stage_All)
                        .SetValue(ShaderGraphSlotFactory.V3(0, 0, 0), ShaderGraphSlotFactory.V3(0, 0, 0));

                case "float4":
                    return new SlotModel(ShaderGraphSlotFactory.S_Vector4, slotObjectId, 0, param.Name, ShaderGraphSlotFactory.Output, "Out")
                        .SetStageCapability(ShaderGraphSlotFactory.Stage_All)
                        .SetValue(ShaderGraphSlotFactory.V4(0, 0, 0, 0), ShaderGraphSlotFactory.V4(0, 0, 0, 0));

                default:
                    return slotFactory.CreatePropertyVector1Out(slotObjectId, param.Name);
            }
        }

        private static TargetModel BuildUniversalTarget(string targetId, string subTargetId, bool useTransparency)
        {
            int surfaceType = useTransparency ? 1 : 0;
            int zWriteControl = useTransparency ? 2 : 0;

            var t = new TargetModel("UnityEditor.Rendering.Universal.ShaderGraph.UniversalTarget", targetId, sgVersion: 1);

            t.SetExtra("m_Datas", new List<object>());
            t.SetExtra("m_ActiveSubTarget", new Dictionary<string, object> { { "m_Id", subTargetId } });
            t.SetExtra("m_AllowMaterialOverride", false);
            t.SetExtra("m_SurfaceType", surfaceType);
            t.SetExtra("m_ZTestMode", 4);
            t.SetExtra("m_ZWriteControl", zWriteControl);
            t.SetExtra("m_AlphaMode", 0);
            t.SetExtra("m_RenderFace", 2);
            t.SetExtra("m_AlphaClip", false);
            t.SetExtra("m_CastShadows", true);
            t.SetExtra("m_ReceiveShadows", true);
            t.SetExtra("m_DisableTint", false);
            t.SetExtra("m_AdditionalMotionVectorMode", 0);
            t.SetExtra("m_AlembicMotionVectors", false);
            t.SetExtra("m_SupportsLODCrossFade", false);
            t.SetExtra("m_DebugSymbols", false);
            t.SetExtra("m_UseVFXGraph", false);
            t.SetExtra("m_IncludeStrippingInformation", false);
            t.SetExtra("m_IncludeAdditionalProperties", false);
            t.SetExtra("m_AllowSRPBatcher", true);
            t.SetExtra("m_CustomEditorGUI", "");
            t.SetExtra("m_CustomEditorGUIEnabled", false);
            t.SetExtra("m_SupportsFog", true);
            t.SetExtra("m_RenderGraphSettings", new Dictionary<string, object>
            {
                { "m_UseRenderGraph", false },
                { "m_UseRenderGraphForPreview", false }
            });

            return t;
        }

        private static TargetModel BuildUniversalUnlitSubTarget(string subTargetId)
        {
            var st = new TargetModel("UnityEditor.Rendering.Universal.ShaderGraph.UniversalUnlitSubTarget", subTargetId, sgVersion: 2);

            st.SetExtra("m_WorkflowMode", 0);
            st.SetExtra("m_NormalDropOffSpace", 0);
            st.SetExtra("m_BlendMode", 0);
            st.SetExtra("m_TwoSided", false);
            st.SetExtra("m_AlphaClip", false);
            st.SetExtra("m_QueueControl", 0);
            st.SetExtra("m_QueueOffset", 0);
            st.SetExtra("m_DepthWrite", true);
            st.SetExtra("m_AlphaToMask", false);
            st.SetExtra("m_SupportsMeshLOD", false);
            st.SetExtra("m_OverrideEnabled", false);
            st.SetExtra("m_Override", new Dictionary<string, object>
            {
                { "m_Dithering", false },
                { "m_ZWrite", false },
                { "m_ZTest", 4 }
            });

            return st;
        }
    }
}
