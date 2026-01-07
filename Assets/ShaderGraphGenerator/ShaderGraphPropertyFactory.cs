using System;
using System.Collections.Generic;

namespace ShaderGraphGenerator
{
    /// <summary>
    /// Creates ShaderPropertyModel instances used by the graph.
    /// This factory does NOT serialize JSON. It only builds the in-memory model (ShaderPropertyModel).
    ///
    /// Writer mapping (later):
    /// - ShaderPropertyModel.Type -> "m_Type"
    /// - ShaderPropertyModel.ObjectId -> "m_ObjectId"
    /// - ShaderPropertyModel.GuidSerialized -> "m_Guid" { "m_GuidSerialized": "..." }
    /// - ShaderPropertyModel.Name -> "m_Name"
    /// - ShaderPropertyModel.DefaultReferenceName / OverrideReferenceName
    /// - ShaderPropertyModel.GeneratePropertyBlock, Hidden, Precision
    /// - ShaderPropertyModel.Value -> "m_Value"
    /// - ShaderPropertyModel.Extra -> additional fields on the property
    /// </summary>
    public sealed class ShaderGraphPropertyFactory
    {
        // -------- Property type strings (as used in ShaderGraph JSON) --------
        public const string P_Vector1 = "UnityEditor.ShaderGraph.Internal.Vector1ShaderProperty";
        public const string P_Vector2 = "UnityEditor.ShaderGraph.Internal.Vector2ShaderProperty";
        public const string P_Vector3 = "UnityEditor.ShaderGraph.Internal.Vector3ShaderProperty";
        public const string P_Vector4 = "UnityEditor.ShaderGraph.Internal.Vector4ShaderProperty";
        public const string P_Color = "UnityEditor.ShaderGraph.Internal.ColorShaderProperty";
        public const string P_Texture2D = "UnityEditor.ShaderGraph.Internal.Texture2DShaderProperty";

        // -------- Common helpers for JSON payload shapes --------

        public static Dictionary<string, object> V2(float x, float y) =>
            new() { { "x", x }, { "y", y } };

        public static Dictionary<string, object> V3(float x, float y, float z) =>
            new() { { "x", x }, { "y", y }, { "z", z } };

        public static Dictionary<string, object> V4(float x, float y, float z, float w) =>
            new() { { "x", x }, { "y", y }, { "z", z }, { "w", w } };

        public static Dictionary<string, object> RGBA(float r, float g, float b, float a) =>
            new() { { "r", r }, { "g", g }, { "b", b }, { "a", a } };

        /// <summary>
        /// Matches the Texture2D property value payload used by ShaderGraph JSON:
        /// { "m_SerializedTexture": "{\"texture\":{\"instanceID\":0}}", "m_Guid": "" }
        /// </summary>
        public static Dictionary<string, object> TextureValueDefault() =>
            new()
            {
                { "m_SerializedTexture", "{\"texture\":{\"instanceID\":0}}" },
                { "m_Guid", "" }
            };

        // =====================================================================
        //  Concrete creators
        // =====================================================================

        /// <summary>
        /// Create a Texture2D property like your MainTex property.
        /// </summary>
        public ShaderPropertyModel CreateTexture2D(
            string propertyObjectId,
            string displayName,
            string referenceName,
            bool useTilingAndOffset = false,
            bool isMainTexture = false,
            int defaultType = 0)
        {
            var p = new ShaderPropertyModel(
                type: P_Texture2D,
                objectId: propertyObjectId,
                name: displayName,
                defaultRefName: referenceName,
                sgVersion: 0);

            p.SetValue(TextureValueDefault());

            // Fields seen in your current JSON
            p.SetExtra("m_DefaultRefNameVersion", 1);
            p.SetExtra("m_RefNameGeneratedByDisplayName", displayName);

            p.SetExtra("m_UseCustomSlotLabel", false);
            p.SetExtra("m_CustomSlotLabel", "");
            p.SetExtra("overrideHLSLDeclaration", false);
            p.SetExtra("hlslDeclarationOverride", 0);

            p.SetExtra("isMainTexture", isMainTexture);
            p.SetExtra("useTilingAndOffset", useTilingAndOffset);
            p.SetExtra("m_Modifiable", true);
            p.SetExtra("m_DefaultType", defaultType);

            return p;
        }

        public ShaderPropertyModel CreateVector1(
            string propertyObjectId,
            string displayName,
            string referenceName,
            float defaultValue = 0.0f,
            int floatType = 0,
            float rangeMin = 0.0f,
            float rangeMax = 1.0f)
        {
            var p = new ShaderPropertyModel(P_Vector1, propertyObjectId, displayName, referenceName, sgVersion: 1)
                .SetValue(defaultValue);

            p.SetExtra("m_DefaultRefNameVersion", 1);
            p.SetExtra("m_RefNameGeneratedByDisplayName", displayName);

            p.SetExtra("m_UseCustomSlotLabel", false);
            p.SetExtra("m_CustomSlotLabel", "");
            p.SetExtra("overrideHLSLDeclaration", false);
            p.SetExtra("hlslDeclarationOverride", 0);

            p.SetExtra("m_FloatType", floatType);
            p.SetExtra("m_RangeValues", V2(rangeMin, rangeMax));

            return p;
        }

        public ShaderPropertyModel CreateVector2(
            string propertyObjectId,
            string displayName,
            string referenceName,
            float x = 0f,
            float y = 0f)
        {
            var p = new ShaderPropertyModel(P_Vector2, propertyObjectId, displayName, referenceName, sgVersion: 1)
                .SetValue(V2(x, y));

            p.SetExtra("m_DefaultRefNameVersion", 1);
            p.SetExtra("m_RefNameGeneratedByDisplayName", displayName);

            p.SetExtra("m_UseCustomSlotLabel", false);
            p.SetExtra("m_CustomSlotLabel", "");
            p.SetExtra("overrideHLSLDeclaration", false);
            p.SetExtra("hlslDeclarationOverride", 0);

            return p;
        }

        public ShaderPropertyModel CreateVector3(
            string propertyObjectId,
            string displayName,
            string referenceName,
            float x = 0f,
            float y = 0f,
            float z = 0f)
        {
            var p = new ShaderPropertyModel(P_Vector3, propertyObjectId, displayName, referenceName, sgVersion: 1)
                .SetValue(V3(x, y, z));

            p.SetExtra("m_DefaultRefNameVersion", 1);
            p.SetExtra("m_RefNameGeneratedByDisplayName", displayName);

            p.SetExtra("m_UseCustomSlotLabel", false);
            p.SetExtra("m_CustomSlotLabel", "");
            p.SetExtra("overrideHLSLDeclaration", false);
            p.SetExtra("hlslDeclarationOverride", 0);

            return p;
        }

        public ShaderPropertyModel CreateVector4(
            string propertyObjectId,
            string displayName,
            string referenceName,
            float x = 0f,
            float y = 0f,
            float z = 0f,
            float w = 0f)
        {
            var p = new ShaderPropertyModel(P_Vector4, propertyObjectId, displayName, referenceName, sgVersion: 1)
                .SetValue(V4(x, y, z, w));

            p.SetExtra("m_DefaultRefNameVersion", 1);
            p.SetExtra("m_RefNameGeneratedByDisplayName", displayName);

            p.SetExtra("m_UseCustomSlotLabel", false);
            p.SetExtra("m_CustomSlotLabel", "");
            p.SetExtra("overrideHLSLDeclaration", false);
            p.SetExtra("hlslDeclarationOverride", 0);

            return p;
        }

        public ShaderPropertyModel CreateColor(
            string propertyObjectId,
            string displayName,
            string referenceName,
            float r = 0f,
            float g = 0f,
            float b = 0f,
            float a = 1f,
            int colorMode = 0,
            bool isMainColor = false)
        {
            var p = new ShaderPropertyModel(P_Color, propertyObjectId, displayName, referenceName, sgVersion: 1)
                .SetValue(RGBA(r, g, b, a));

            p.SetExtra("m_DefaultRefNameVersion", 1);
            p.SetExtra("m_RefNameGeneratedByDisplayName", displayName);

            p.SetExtra("m_UseCustomSlotLabel", false);
            p.SetExtra("m_CustomSlotLabel", "");
            p.SetExtra("overrideHLSLDeclaration", false);
            p.SetExtra("hlslDeclarationOverride", 0);

            p.SetExtra("isMainColor", isMainColor);
            p.SetExtra("m_ColorMode", colorMode);

            return p;
        }

        // =====================================================================
        //  Convenience creators that match your current generator defaults
        // =====================================================================

        /// <summary>
        /// Mirrors your existing generator's MainTex defaults:
        /// Name: MainTex, Ref: _MainTex, tiling/offset disabled.
        /// </summary>
        public ShaderPropertyModel CreateMainTex(string propertyObjectId)
            => CreateTexture2D(
                propertyObjectId: propertyObjectId,
                displayName: "MainTex",
                referenceName: "_MainTex",
                useTilingAndOffset: false,
                isMainTexture: false,
                defaultType: 0);

        /// <summary>
        /// Mirrors your pixelation default:
        /// PixelCount default 50 with range [1..256] (as in your JSON).
        /// </summary>
        public ShaderPropertyModel CreatePixelCount(string propertyObjectId, float defaultValue = 50.0f, float rangeMin = 1.0f, float rangeMax = 256.0f)
            => CreateVector1(
                propertyObjectId: propertyObjectId,
                displayName: "PixelCount",
                referenceName: "_PixelCount",
                defaultValue: defaultValue,
                floatType: 0,
                rangeMin: rangeMin,
                rangeMax: rangeMax);
    }
}
