using System;
using System.Collections.Generic;
using UnityEngine;

namespace ShaderGraphGenerator.KnowledgeBase
{
    // ─── Animator entry (nested inside a ShapeMetadata) ─────────────────────

    /// <summary>
    /// A saved animation script linked to a specific shape in the knowledge base.
    /// Stored in ShapeMetadata.animators so each shape owns its proven animations.
    /// </summary>
    [Serializable]
    public class AnimatorEntry
    {
        public string id;                  // short unique id
        public string fileName;            // C# class name, e.g. "CartoonSnowmanPulse"
        public string scriptPath;          // asset path to the .cs file
        public string animationDescription;// original user request
        public string animationSummary;    // one-line LLM summary
        public string sourceMaterialName;  // material the animation was created for
        public List<string> propertiesUsed = new List<string>();
        public List<string> tags           = new List<string>();
        public string dateAdded;
        public int    humanScore;
        public float[] embedding;          // on animation summary, for future retrieval
    }

    // ─── Shape metadata ───────────────────────────────────────────────────────

    /// <summary>
    /// Metadata for a single SDF shape primitive
    /// </summary>
    [Serializable]
    public class ShapeMetadata
    {
        // Animations written for this specific shape
        public List<AnimatorEntry> animators = new List<AnimatorEntry>();
        public string id;
        public string fileName;
        public string filePath;
        public string functionName;
        
        // Original user prompt used to generate this shape
        public string originalPrompt;
        
        // Detailed visual description (from LLM analysis)
        public string visualDescription;
        
        public ShapeCategory category;
        public ComplexityLevel complexity;
        public SymmetryType symmetry;
        public List<string> tags = new List<string>();
        public List<ShapeParameter> parameters = new List<ShapeParameter>();
        
        // For embedding-based retrieval (added later)
        public float[] embedding;
        
        // Metadata about when this was created/verified
        public string dateAdded;
        public int verificationScore; // The VLM score when it was created
    }

    [Serializable]
    public class ShapeParameter
    {
        public string name;
        public string type; // float, float2, float3, float4
        public string defaultValue; // stored as string, parsed when needed
        
        public bool IsColorParameter()
        {
            return type == "float4" && name.ToLower().Contains("color");
        }
    }

    public enum ShapeCategory
    {
        Uncategorized,
        GeometricPrimitives,    // Circle, Square, Triangle, etc.
        OrganicShapes,          // Heart, Cloud, Flower, etc.
        SymbolsAndIcons,        // Star, Gear, Arrow, etc.
        CompositeShapes         // Already built from multiple primitives
    }

    public enum ComplexityLevel
    {
        Unknown,
        Primitive,      // Single basic shape
        Intermediate,   // 2-3 operations
        Complex         // 4+ operations or advanced math
    }

    public enum SymmetryType
    {
        Unknown,
        None,
        Bilateral,      // Mirror symmetry (one axis)
        Radial,         // Rotational symmetry
        Both            // Both bilateral and radial
    }

    /// <summary>
    /// Container for the entire knowledge base
    /// </summary>
    [Serializable]
    public class ShapeKnowledgeBase
    {
        public string version = "1.0";
        public string generatedDate;
        public int totalShapes;
        public List<ShapeMetadata> shapes = new List<ShapeMetadata>();
    }

    /// <summary>
    /// LLM response structure for shape analysis
    /// </summary>
    [Serializable]
    public class LLMShapeAnalysis
    {
        public string visual_description;
        public string category; // will be parsed to enum
        public string complexity; // will be parsed to enum
        public string symmetry; // will be parsed to enum
        public List<string> tags;
    }
}