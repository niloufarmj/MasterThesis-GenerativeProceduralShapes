using System;
using System.Collections.Generic;
using UnityEngine;

namespace ShaderGraphGenerator
{
    /// <summary>
    /// Creates NodeModel instances for common ShaderGraph nodes.
    /// This factory does NOT serialize JSON. It only builds the in-memory model (NodeModel).
    /// 
    /// Conventions:
    /// - "Type" is the ShaderGraph node type string (e.g. UnityEditor.ShaderGraph.MultiplyNode).
    /// - SlotObjectIds are the slot object GUIDs referenced by the node's "m_Slots" list.
    /// - Node-specific fields (e.g. m_OutputChannel, m_TextureType, etc.) are stored in NodeModel.Extra.
    /// 
    /// Your future JsonWriter should map:
    /// - NodeModel.Type -> "m_Type"
    /// - NodeModel.ObjectId -> "m_ObjectId"
    /// - NodeModel.Name -> "m_Name"
    /// - NodeModel.DrawState -> "m_DrawState"
    /// - NodeModel.SlotObjectIds -> "m_Slots" (as list of { m_Id = ... })
    /// - NodeModel.Extra -> additional fields on the node
    /// </summary>
    public sealed class ShaderGraphNodeFactory
    {
        // -------- Common type strings --------
        public const string T_BlockNode = "UnityEditor.ShaderGraph.BlockNode";
        public const string T_CustomFunctionNode = "UnityEditor.ShaderGraph.CustomFunctionNode";
        public const string T_PropertyNode = "UnityEditor.ShaderGraph.PropertyNode";
        public const string T_UVNode = "UnityEditor.ShaderGraph.UVNode";
        public const string T_SampleTexture2DNode = "UnityEditor.ShaderGraph.SampleTexture2DNode";
        public const string T_MultiplyNode = "UnityEditor.ShaderGraph.MultiplyNode";
        public const string T_DivideNode = "UnityEditor.ShaderGraph.DivideNode";
        public const string T_FloorNode = "UnityEditor.ShaderGraph.FloorNode";
        public const string T_SplitNode = "UnityEditor.ShaderGraph.SplitNode";
        public const string T_Vector3Node = "UnityEditor.ShaderGraph.Vector3Node";

        // Default visuals (match what you were generating before)
        private const float DefaultNodeWidth = 208f;

        // Minimal group payload used by ShaderGraph JSON.
        // Writer should output it as: "m_Group": { "m_Id": "" }
        private static readonly Dictionary<string, object> EmptyGroup = new()
        {
            { "m_Id", "" }
        };

        // -------- Base helper --------
        private static NodeModel CreateBase(
            string type,
            string nodeId,
            string name,
            float x,
            float y,
            float width,
            float height,
            bool expanded)
        {
            var n = new NodeModel(type, nodeId, name, sgVersion: 0)
                .SetPosition(x, y, width, height, expanded);

            // Always present on your generated nodes
            n.SetExtra("m_Group", EmptyGroup);
            n.SetExtra("m_Precision", 0);
            n.SetExtra("m_PreviewExpanded", true);
            n.SetExtra("m_DismissedVersion", 0);
            n.SetExtra("m_PreviewMode", 0);

            // Custom colors block (empty)
            n.SetExtra("m_CustomColors", new Dictionary<string, object>
            {
                { "m_SerializableColors", new List<object>() }
            });

            return n;
        }

        private static void SetSynonyms(NodeModel node, params string[] synonyms)
        {
            node.SetExtra("synonyms", new List<string>(synonyms ?? Array.Empty<string>()));
        }

        // =====================================================================
        //  Node creators
        // =====================================================================

        /// <summary>
        /// UV node with a single output slot. Also stores m_OutputChannel.
        /// </summary>
        public NodeModel CreateUVNode(string nodeId, string outSlotObjectId, float x = -664f, float y = 41.6f, int outputChannel = 0)
        {
            var n = CreateBase(
                type: T_UVNode,
                nodeId: nodeId,
                name: "UV",
                x: x,
                y: y,
                width: DefaultNodeWidth,
                height: 310.4f,
                expanded: true);

            n.AddSlot(outSlotObjectId);

            SetSynonyms(n, "texcoords", "coords", "coordinates");

            // Node-specific
            n.SetExtra("m_OutputChannel", outputChannel);
            return n;
        }

        /// <summary>
        /// Multiply node with slots A, B, Out (slot object ids are passed in correct order).
        /// </summary>
        public NodeModel CreateMultiplyNode(string nodeId, string slotA, string slotB, string slotOut, float x, float y)
        {
            var n = CreateBase(
                type: T_MultiplyNode,
                nodeId: nodeId,
                name: "Multiply",
                x: x,
                y: y,
                width: DefaultNodeWidth,
                height: 302f,
                expanded: true);

            n.AddSlot(slotA).AddSlot(slotB).AddSlot(slotOut);
            SetSynonyms(n, "multiplication", "times", "x");
            return n;
        }

        /// <summary>
        /// Floor node with slots Out, In (ShaderGraph usually lists output first).
        /// Your old JSON used [Out, In], so we keep that order here.
        /// </summary>
        public NodeModel CreateFloorNode(string nodeId, string outSlot, string inSlot, float x, float y)
        {
            var n = CreateBase(
                type: T_FloorNode,
                nodeId: nodeId,
                name: "Floor",
                x: x,
                y: y,
                width: DefaultNodeWidth,
                height: 140f,
                expanded: true);

            n.AddSlot(outSlot).AddSlot(inSlot);
            SetSynonyms(n, "rounddown");
            return n;
        }

        /// <summary>
        /// Divide node with slots A, B, Out.
        /// </summary>
        public NodeModel CreateDivideNode(string nodeId, string slotA, string slotB, string slotOut, float x, float y)
        {
            var n = CreateBase(
                type: T_DivideNode,
                nodeId: nodeId,
                name: "Divide",
                x: x,
                y: y,
                width: DefaultNodeWidth,
                height: 200f,
                expanded: true);

            n.AddSlot(slotA).AddSlot(slotB).AddSlot(slotOut);
            SetSynonyms(n, "division");
            return n;
        }

        /// <summary>
        /// Property node that references a ShaderProperty definition (propertyDefId).
        /// Node has a single output slot.
        /// </summary>
        public NodeModel CreatePropertyNode(
            string nodeId,
            string outSlotObjectId,
            string propertyDefId,
            float x,
            float y)
        {
            var n = CreateBase(
                type: T_PropertyNode,
                nodeId: nodeId,
                name: "Property",
                x: x,
                y: y,
                width: 0f,
                height: 0f,
                expanded: true);

            n.AddSlot(outSlotObjectId);

            // Node-specific: m_Property : { m_Id : "<propertyDefId>" }
            n.SetExtra("m_Property", new Dictionary<string, object>
            {
                { "m_Id", propertyDefId }
            });

            SetSynonyms(n); // empty list
            return n;
        }

        /// <summary>
        /// Sample Texture 2D node.
        /// IMPORTANT: the node contains more slots than just UV/Tex/RGBA.
        /// To match your working generator, pass in the full slot list in the exact order you want.
        ///
        /// If you want the "classic" order used in your old JSON:
        /// [ RGBA, (random), (random), (random), (random), Texture, UV, (random) ]
        /// you can construct that list in your builder and pass it here.
        /// </summary>
        public NodeModel CreateSampleTexture2DNode(
            string nodeId,
            IReadOnlyList<string> slotObjectIdsInOrder,
            float x = -280f,
            float y = 450f,
            float width = DefaultNodeWidth,
            float height = 437f,
            int textureType = 0,
            int normalMapSpace = 0,
            bool enableGlobalMipBias = true,
            int mipSamplingMode = 0)
        {
            var n = CreateBase(
                type: T_SampleTexture2DNode,
                nodeId: nodeId,
                name: "Sample Texture 2D",
                x: x,
                y: y,
                width: width,
                height: height,
                expanded: true);

            if (slotObjectIdsInOrder != null)
            {
                for (int i = 0; i < slotObjectIdsInOrder.Count; i++)
                    n.AddSlot(slotObjectIdsInOrder[i]);
            }

            SetSynonyms(n, "tex2d");

            // Node-specific fields used in your previous JSON
            n.SetExtra("m_TextureType", textureType);
            n.SetExtra("m_NormalMapSpace", normalMapSpace);
            n.SetExtra("m_EnableGlobalMipBias", enableGlobalMipBias);
            n.SetExtra("m_MipSamplingMode", mipSamplingMode);

            return n;
        }

        /// <summary>
        /// Custom Function node. Slots must be in the exact order matching the function signature.
        /// </summary>
        public NodeModel CreateCustomFunctionNode(
            string nodeId,
            string displayName,
            IReadOnlyList<string> slotObjectIdsInOrder,
            string hlslFileGuid,
            string functionNameForNode,
            bool usePragmas = true,
            float x = -280f,
            float y = 196.8f,
            float width = DefaultNodeWidth,
            float height = 301.6f)
        {
            // NOTE: CustomFunction node in your old JSON used m_SGVersion = 1
            var n = new NodeModel(T_CustomFunctionNode, nodeId, $"{displayName} (Custom Function)", sgVersion: 1)
                .SetPosition(x, y, width, height, expanded: true);

            // Common fields
            n.SetExtra("m_Group", EmptyGroup);
            n.SetExtra("m_Precision", 0);
            n.SetExtra("m_PreviewExpanded", true);
            n.SetExtra("m_DismissedVersion", 0);
            n.SetExtra("m_PreviewMode", 0);
            n.SetExtra("m_CustomColors", new Dictionary<string, object>
            {
                { "m_SerializableColors", new List<object>() }
            });

            if (slotObjectIdsInOrder != null)
            {
                for (int i = 0; i < slotObjectIdsInOrder.Count; i++)
                    n.AddSlot(slotObjectIdsInOrder[i]);
            }

            SetSynonyms(n, "code", "HLSL");

            // Node-specific
            n.SetExtra("m_SourceType", 0);
            n.SetExtra("m_FunctionName", functionNameForNode);
            n.SetExtra("m_FunctionSource", hlslFileGuid);
            n.SetExtra("m_FunctionSourceUsePragmas", usePragmas);
            n.SetExtra("m_FunctionBody", "Enter function body here...");

            return n;
        }

        /// <summary>
        /// Block node (Vertex/Fragment stack blocks). Has a single slot.
        /// </summary>
        public NodeModel CreateBlockNode(
            string nodeId,
            string serializedDescriptor,
            string slotObjectId,
            float x = 0f,
            float y = 0f)
        {
            var n = CreateBase(
                type: T_BlockNode,
                nodeId: nodeId,
                name: serializedDescriptor,
                x: x,
                y: y,
                width: 0f,
                height: 0f,
                expanded: true);

            n.AddSlot(slotObjectId);
            SetSynonyms(n); // empty list

            // Node-specific
            n.SetExtra("m_SerializedDescriptor", serializedDescriptor);
            return n;
        }

        /// <summary>
        /// Split node with slot order: In, R, G, B, A (match your old JSON ordering).
        /// </summary>
        public NodeModel CreateSplitNode(
            string nodeId,
            string inSlot,
            string rSlot,
            string gSlot,
            string bSlot,
            string aSlot,
            float x = -20f,
            float y = 196.8f,
            float width = 119.2f,
            float height = 148.8f)
        {
            var n = CreateBase(
                type: T_SplitNode,
                nodeId: nodeId,
                name: "Split",
                x: x,
                y: y,
                width: width,
                height: height,
                expanded: true);

            n.AddSlot(inSlot).AddSlot(rSlot).AddSlot(gSlot).AddSlot(bSlot).AddSlot(aSlot);
            SetSynonyms(n, "separate");
            return n;
        }

        /// <summary>
        /// Vector 3 node: slot order Out, X, Y, Z (match your old JSON ordering).
        /// </summary>
        public NodeModel CreateVector3Node(
            string nodeId,
            string outSlot,
            string xSlot,
            string ySlot,
            string zSlot,
            float x = 150f,
            float y = 196.8f,
            float width = 128f,
            float height = 124.8f)
        {
            var n = CreateBase(
                type: T_Vector3Node,
                nodeId: nodeId,
                name: "Vector 3",
                x: x,
                y: y,
                width: width,
                height: height,
                expanded: true);

            n.AddSlot(outSlot).AddSlot(xSlot).AddSlot(ySlot).AddSlot(zSlot);
            SetSynonyms(n, "3", "v3", "vec3", "float3");

            // Node-specific
            n.SetExtra("m_Value", new Dictionary<string, object>
            {
                { "x", 0.0f },
                { "y", 0.0f },
                { "z", 0.0f },
            });

            return n;
        }
    }
}
