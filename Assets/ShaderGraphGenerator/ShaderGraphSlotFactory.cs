using System;
using System.Collections.Generic;
using UnityEngine;

namespace ShaderGraphGenerator
{
    /// <summary>
    /// Creates SlotModel instances for common ShaderGraph slot types.
    /// This factory does NOT serialize JSON. It only builds the in-memory model (SlotModel).
    ///
    /// Writer mapping (later):
    /// - SlotModel.Type -> "m_Type"
    /// - SlotModel.ObjectId -> "m_ObjectId"
    /// - SlotModel.Id -> "m_Id"
    /// - SlotModel.DisplayName -> "m_DisplayName"
    /// - SlotModel.SlotType -> "m_SlotType" (0=input, 1=output)
    /// - SlotModel.Hidden -> "m_Hidden"
    /// - SlotModel.ShaderOutputName -> "m_ShaderOutputName"
    /// - SlotModel.StageCapability -> "m_StageCapability"
    /// - SlotModel.Value / DefaultValue -> "m_Value" / "m_DefaultValue"
    /// - SlotModel.Labels -> "m_Labels"
    /// - SlotModel.Extra -> additional fields on the slot
    /// </summary>
    public sealed class ShaderGraphSlotFactory
    {
        // -------- Slot type strings --------
        public const string S_Vector1 = "UnityEditor.ShaderGraph.Vector1MaterialSlot";
        public const string S_Vector2 = "UnityEditor.ShaderGraph.Vector2MaterialSlot";
        public const string S_Vector3 = "UnityEditor.ShaderGraph.Vector3MaterialSlot";
        public const string S_Vector4 = "UnityEditor.ShaderGraph.Vector4MaterialSlot";

        public const string S_UV = "UnityEditor.ShaderGraph.UVMaterialSlot";

        public const string S_DynamicVector = "UnityEditor.ShaderGraph.DynamicVectorMaterialSlot";
        public const string S_DynamicValue = "UnityEditor.ShaderGraph.DynamicValueMaterialSlot";

        public const string S_Texture2DMaterial = "UnityEditor.ShaderGraph.Texture2DMaterialSlot";
        public const string S_Texture2DInput = "UnityEditor.ShaderGraph.Texture2DInputMaterialSlot";

        public const string S_ColorRGB = "UnityEditor.ShaderGraph.ColorRGBMaterialSlot";
        public const string S_Position = "UnityEditor.ShaderGraph.PositionMaterialSlot";
        public const string S_Normal = "UnityEditor.ShaderGraph.NormalMaterialSlot";
        public const string S_Tangent = "UnityEditor.ShaderGraph.TangentMaterialSlot";

        // Stage capability values often used by SG:
        // 1 = Vertex, 2 = Fragment, 3 = All (both)
        public const int Stage_Vertex = 1;
        public const int Stage_Fragment = 2;
        public const int Stage_All = 3;

        // Slot direction used across the whole generator
        public const int Input = 0;
        public const int Output = 1;

        // =====================================================================
        //  Value helpers (match JSON shapes later)
        // =====================================================================

        public static Dictionary<string, object> V2(float x, float y) =>
            new() { { "x", x }, { "y", y } };

        public static Dictionary<string, object> V3(float x, float y, float z) =>
            new() { { "x", x }, { "y", y }, { "z", z } };

        public static Dictionary<string, object> V4(float x, float y, float z, float w) =>
            new() { { "x", x }, { "y", y }, { "z", z }, { "w", w } };

        public static Dictionary<string, object> Color(float r, float g, float b, float a) =>
            new() { { "r", r }, { "g", g }, { "b", b }, { "a", a } };

        /// <summary>
        /// DynamicValueMaterialSlot uses the "matrix" payload in your existing JSON.
        /// Keep the exact keys so output matches your current generator.
        /// </summary>
        public static Dictionary<string, object> DynValueMatrix(
            float e00, float e01, float e02, float e03,
            float e10, float e11, float e12, float e13,
            float e20, float e21, float e22, float e23,
            float e30, float e31, float e32, float e33)
        {
            return new Dictionary<string, object>
            {
                { "e00", e00 }, { "e01", e01 }, { "e02", e02 }, { "e03", e03 },
                { "e10", e10 }, { "e11", e11 }, { "e12", e12 }, { "e13", e13 },
                { "e20", e20 }, { "e21", e21 }, { "e22", e22 }, { "e23", e23 },
                { "e30", e30 }, { "e31", e31 }, { "e32", e32 }, { "e33", e33 },
            };
        }

        // =====================================================================
        //  Generic builders
        // =====================================================================

        public SlotModel CreateVector1(string objectId, int id, string displayName, int direction, string shaderOutputName, int stage = Stage_All)
        {
            return new SlotModel(S_Vector1, objectId, id, displayName, direction, shaderOutputName)
                .SetStageCapability(stage)
                .SetValue(0.0f, 0.0f)
                .SetExtra("m_Labels", new List<object>()); // writer may also map SlotModel.Labels
        }

        public SlotModel CreateVector2(string objectId, int id, string displayName, int direction, string shaderOutputName, int stage = Stage_All)
        {
            return new SlotModel(S_Vector2, objectId, id, displayName, direction, shaderOutputName)
                .SetStageCapability(stage)
                .SetValue(V2(0, 0), V2(0, 0));
        }

        public SlotModel CreateVector3(string objectId, int id, string displayName, int direction, string shaderOutputName, int stage = Stage_All)
        {
            return new SlotModel(S_Vector3, objectId, id, displayName, direction, shaderOutputName)
                .SetStageCapability(stage)
                .SetValue(V3(0, 0, 0), V3(0, 0, 0));
        }

        public SlotModel CreateVector4(string objectId, int id, string displayName, int direction, string shaderOutputName, int stage = Stage_All)
        {
            return new SlotModel(S_Vector4, objectId, id, displayName, direction, shaderOutputName)
                .SetStageCapability(stage)
                .SetValue(V4(0, 0, 0, 0), V4(0, 0, 0, 0));
        }

        public SlotModel CreateDynamicVector(string objectId, int id, string displayName, int direction, string shaderOutputName, int stage = Stage_All)
        {
            // Your current generator uses DynamicVector with x/y/z/w payload.
            return new SlotModel(S_DynamicVector, objectId, id, displayName, direction, shaderOutputName)
                .SetStageCapability(stage)
                .SetValue(V4(0, 0, 0, 0), V4(0, 0, 0, 0));
        }

        public SlotModel CreateDynamicValue(string objectId, int id, string displayName, int direction, string shaderOutputName, int stage = Stage_All)
        {
            // Matches your old MultiplyNode slots (value = zeros, default = identity matrix)
            var value = DynValueMatrix(
                0, 0, 0, 0,
                0, 0, 0, 0,
                0, 0, 0, 0,
                0, 0, 0, 0);

            var def = DynValueMatrix(
                1, 0, 0, 0,
                0, 1, 0, 0,
                0, 0, 1, 0,
                0, 0, 0, 1);

            return new SlotModel(S_DynamicValue, objectId, id, displayName, direction, shaderOutputName)
                .SetStageCapability(stage)
                .SetValue(value, def);
        }

        // =====================================================================
        //  Specific slots used by your graphs
        // =====================================================================

        // --- UV Node output (Vector4MaterialSlot Out) ---
        public SlotModel CreateUVNodeOut(string objectId)
            => CreateVector4(objectId, id: 0, displayName: "Out", direction: Output, shaderOutputName: "Out", stage: Stage_All);

        // --- Sample Texture 2D slots (Texture in, UV in, RGBA out) ---
        public SlotModel CreateSampleTexture2DUVIn(string objectId, int channel = 0)
        {
            var s = new SlotModel(S_UV, objectId, id: 2, displayName: "UV", slotType: Input, shaderOutputName: "UV")
                .SetStageCapability(Stage_All)
                .SetValue(V2(0, 0), V2(0, 0));

            s.SetExtra("m_Channel", channel);
            return s;
        }

        public SlotModel CreateSampleTexture2DTextureIn(string objectId)
        {
            // Matches your existing JSON shape for Texture2DInputMaterialSlot.
            var s = new SlotModel(S_Texture2DInput, objectId, id: 1, displayName: "Texture", slotType: Input, shaderOutputName: "Texture")
                .SetStageCapability(Stage_All);

            s.SetExtra("m_BareResource", false);
            s.SetExtra("m_Texture", new Dictionary<string, object>
            {
                { "m_SerializedTexture", "{\"texture\":{\"instanceID\":0}}" },
                { "m_Guid", "" }
            });
            s.SetExtra("m_DefaultType", 0);
            return s;
        }

        public SlotModel CreateSampleTexture2DRGBAOut(string objectId)
            => CreateVector4(objectId, id: 4, displayName: "RGBA", direction: Output, shaderOutputName: "RGBA", stage: Stage_Fragment);

        // --- Multiply node slots (DynamicValue) ---
        public SlotModel CreateMultiplyA(string objectId) => CreateDynamicValue(objectId, id: 0, displayName: "A", direction: Input, shaderOutputName: "A");
        public SlotModel CreateMultiplyB(string objectId) => CreateDynamicValue(objectId, id: 1, displayName: "B", direction: Input, shaderOutputName: "B");
        public SlotModel CreateMultiplyOut(string objectId) => CreateDynamicValue(objectId, id: 2, displayName: "Out", direction: Output, shaderOutputName: "Out");

        // --- Floor node slots (DynamicVector) ---
        // Your old JSON used: Out slot first in node slot list, but slot ids are In=0, Out=1.
        public SlotModel CreateFloorIn(string objectId) => CreateDynamicVector(objectId, id: 0, displayName: "In", direction: Input, shaderOutputName: "In");
        public SlotModel CreateFloorOut(string objectId) => CreateDynamicVector(objectId, id: 1, displayName: "Out", direction: Output, shaderOutputName: "Out");

        // --- Divide node slots (DynamicVector) ---
        public SlotModel CreateDivideA(string objectId) => CreateDynamicVector(objectId, id: 0, displayName: "A", direction: Input, shaderOutputName: "A");
        public SlotModel CreateDivideB(string objectId) => CreateDynamicVector(objectId, id: 1, displayName: "B", direction: Input, shaderOutputName: "B");
        public SlotModel CreateDivideOut(string objectId) => CreateDynamicVector(objectId, id: 2, displayName: "Out", direction: Output, shaderOutputName: "Out");

        // --- Property node output slots ---
        public SlotModel CreatePropertyVector1Out(string objectId, string displayName)
        {
            // Your generator uses Vector1MaterialSlot for PixelCount property node out.
            var s = CreateVector1(objectId, id: 0, displayName: displayName, direction: Output, shaderOutputName: "Out");
            s.Labels = new List<string>(); // writer may output m_Labels from here
            return s;
        }

        public SlotModel CreatePropertyTexture2DOut(string objectId, string displayName = "MainTex")
        {
            // Matches your generator's Texture2DMaterialSlot for MainTex property node output
            var s = new SlotModel(S_Texture2DMaterial, objectId, id: 0, displayName: displayName, slotType: Output, shaderOutputName: "Out")
                .SetStageCapability(Stage_All);

            s.SetExtra("m_BareResource", false);
            return s;
        }

        // --- Block slots (Master Stack blocks) ---
        public SlotModel CreatePositionBlockSlot(string objectId)
        {
            var s = new SlotModel(S_Position, objectId, id: 0, displayName: "Position", slotType: Input, shaderOutputName: "Position")
                .SetStageCapability(Stage_Vertex)
                .SetValue(V3(0, 0, 0), V3(0, 0, 0));

            s.Labels = new List<string>();
            s.SetExtra("m_Space", 0);
            return s;
        }

        public SlotModel CreateNormalBlockSlot(string objectId)
        {
            var s = new SlotModel(S_Normal, objectId, id: 0, displayName: "Normal", slotType: Input, shaderOutputName: "Normal")
                .SetStageCapability(Stage_Vertex)
                .SetValue(V3(0, 0, 0), V3(0, 0, 0));

            s.Labels = new List<string>();
            s.SetExtra("m_Space", 0);
            return s;
        }

        public SlotModel CreateTangentBlockSlot(string objectId)
        {
            var s = new SlotModel(S_Tangent, objectId, id: 0, displayName: "Tangent", slotType: Input, shaderOutputName: "Tangent")
                .SetStageCapability(Stage_Vertex)
                .SetValue(V3(0, 0, 0), V3(0, 0, 0));

            s.Labels = new List<string>();
            s.SetExtra("m_Space", 0);
            return s;
        }

        public SlotModel CreateBaseColorBlockSlot(string objectId)
        {
            // Matches your generator: ColorRGBMaterialSlot uses x/y/z + default color
            var s = new SlotModel(S_ColorRGB, objectId, id: 0, displayName: "Base Color", slotType: Input, shaderOutputName: "BaseColor")
                .SetStageCapability(Stage_Fragment);

            s.SetValue(V3(0.5f, 0.5f, 0.5f), V3(0.5f, 0.5f, 0.5f));
            s.Labels = new List<string>();

            s.SetExtra("m_ColorMode", 0);
            s.SetExtra("m_DefaultColor", Color(0.5f, 0.5f, 0.5f, 1.0f));
            return s;
        }

        public SlotModel CreateAlphaBlockSlot(string objectId)
        {
            var s = CreateVector1(objectId, id: 0, displayName: "Alpha", direction: Input, shaderOutputName: "Alpha", stage: Stage_Fragment);
            s.SetValue(1.0f, 1.0f);
            return s;
        }

        // --- Split node slots ---
        public SlotModel CreateSplitIn(string objectId) => CreateDynamicVector(objectId, id: 0, displayName: "In", direction: Input, shaderOutputName: "In");
        public SlotModel CreateSplitOutR(string objectId) => CreateVector1(objectId, id: 1, displayName: "R", direction: Output, shaderOutputName: "R");
        public SlotModel CreateSplitOutG(string objectId) => CreateVector1(objectId, id: 2, displayName: "G", direction: Output, shaderOutputName: "G");
        public SlotModel CreateSplitOutB(string objectId) => CreateVector1(objectId, id: 3, displayName: "B", direction: Output, shaderOutputName: "B");
        public SlotModel CreateSplitOutA(string objectId) => CreateVector1(objectId, id: 4, displayName: "A", direction: Output, shaderOutputName: "A");

        // --- Vector3 node slots (your generator uses Vector1 ins with labels, and a Vector3 out) ---
        public SlotModel CreateVector3NodeOut(string objectId)
            => CreateVector3(objectId, id: 0, displayName: "Out", direction: Output, shaderOutputName: "Out");

        public SlotModel CreateVector3NodeInX(string objectId)
        {
            var s = CreateVector1(objectId, id: 1, displayName: "X", direction: Input, shaderOutputName: "X");
            s.Labels = new List<string> { "X" };
            return s;
        }

        public SlotModel CreateVector3NodeInY(string objectId)
        {
            var s = CreateVector1(objectId, id: 2, displayName: "Y", direction: Input, shaderOutputName: "Y");
            s.Labels = new List<string> { "Y" };
            return s;
        }

        public SlotModel CreateVector3NodeInZ(string objectId)
        {
            var s = CreateVector1(objectId, id: 3, displayName: "Z", direction: Input, shaderOutputName: "Z");
            s.Labels = new List<string> { "Z" };
            return s;
        }

        // =====================================================================
        //  Function parameter slot support (so later you can replace generator's AppendFunctionSlot)
        // =====================================================================

        /// <summary>
        /// Create a slot suitable for CustomFunction parameters (float/float2/float3/float4).
        /// Provide the exact ShaderGraph slot type string you want (e.g. Vector1MaterialSlot, Vector2MaterialSlot...)
        /// </summary>
        public SlotModel CreateFunctionParamSlot(
            string objectId,
            int slotId,
            string paramName,
            string materialSlotType,
            bool isOutput,
            string shaderOutputName = null)
        {
            int direction = isOutput ? Output : Input;
            shaderOutputName ??= paramName;

            var s = new SlotModel(materialSlotType, objectId, slotId, paramName, direction, shaderOutputName)
                .SetStageCapability(Stage_All);

            // Default values depend on type
            switch (materialSlotType)
            {
                case S_Vector1:
                    s.SetValue(0.0f, 0.0f);
                    s.Labels = new List<string>();
                    break;

                case S_Vector2:
                    s.SetValue(V2(0, 0), V2(0, 0));
                    s.Labels = new List<string>();
                    break;

                case S_Vector3:
                    s.SetValue(V3(0, 0, 0), V3(0, 0, 0));
                    s.Labels = new List<string>();
                    break;

                case S_Vector4:
                    s.SetValue(V4(0, 0, 0, 0), V4(0, 0, 0, 0));
                    s.Labels = new List<string>();
                    break;

                default:
                    // Safe fallback
                    s.SetValue(0.0f, 0.0f);
                    s.Labels = new List<string>();
                    break;
            }

            return s;
        }
    }
}
