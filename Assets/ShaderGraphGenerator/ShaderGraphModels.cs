using System;
using System.Collections.Generic;
using UnityEngine;

namespace ShaderGraphGenerator
{
    /// <summary>
    /// Lightweight in-memory representation of a ShaderGraph.
    /// Build this model first, then serialize it with ShaderGraphJsonWriter later.
    /// </summary>
    [Serializable]
    public sealed class ShaderGraphDataModel
    {
        public string GraphObjectId; // root GraphData m_ObjectId (guid as string)

        public readonly List<PropertyRef> PropertyRefs = new();
        public readonly List<NodeRef> NodeRefs = new();
        public readonly List<EdgeModel> Edges = new();

        // "Definitions" are the actual objects written after the root GraphData block:
        // nodes, slots, properties, targets, categories, etc.
        public readonly List<GraphObject> Definitions = new();

        // Optional convenience: store categories / targets as strongly-typed references too
        public readonly List<CategoryDataModel> Categories = new();
        public readonly List<TargetModel> Targets = new();

        public ShaderGraphDataModel(string graphObjectId)
        {
            GraphObjectId = graphObjectId;
        }
    }

    #region Core References

    [Serializable]
    public readonly struct NodeRef
    {
        public readonly string Id;
        public NodeRef(string id) { Id = id; }
        public override string ToString() => Id;
    }

    [Serializable]
    public readonly struct SlotRef
    {
        public readonly NodeRef Node;
        public readonly int SlotId;

        public SlotRef(NodeRef node, int slotId)
        {
            Node = node;
            SlotId = slotId;
        }

        public override string ToString() => $"{Node.Id}:{SlotId}";
    }

    [Serializable]
    public readonly struct PropertyRef
    {
        public readonly string Id;
        public PropertyRef(string id) { Id = id; }
        public override string ToString() => Id;
    }

    #endregion

    #region Edges

    [Serializable]
    public sealed class EdgeModel
    {
        public SlotRef OutputSlot; // from
        public SlotRef InputSlot;  // to

        public EdgeModel(SlotRef outputSlot, SlotRef inputSlot)
        {
            OutputSlot = outputSlot;
            InputSlot = inputSlot;
        }
    }

    #endregion

    #region Base Graph Objects (Definitions)

    /// <summary>
    /// Every object that later becomes a JSON block (node, slot, property, target, category...)
    /// has a type string and object id.
    /// </summary>
    [Serializable]
    public abstract class GraphObject
    {
        public int SGVersion = 0;
        public string Type;      // UnityEditor.ShaderGraph.XYZ
        public string ObjectId;  // m_ObjectId

        protected GraphObject(string type, string objectId, int sgVersion = 0)
        {
            Type = type;
            ObjectId = objectId;
            SGVersion = sgVersion;
        }
    }

    #endregion

    #region Nodes (Common)

    [Serializable]
    public sealed class DrawStateModel
    {
        public bool Expanded = true;
        public RectPositionModel Position = new();
    }

    [Serializable]
    public sealed class RectPositionModel
    {
        public string SerializedVersion = "2";
        public float X;
        public float Y;
        public float Width = 208f;
        public float Height = 300f;
    }

    /// <summary>
    /// Generic node definition. Concrete nodes can subclass this if you want strict typing,
    /// or you can just use this + a dictionary of extra fields.
    /// </summary>
    [Serializable]
    public class NodeModel : GraphObject
    {
        public string Name; // m_Name (node title)
        public DrawStateModel DrawState = new();
        public List<string> SlotObjectIds = new(); // list of slot m_ObjectId referenced by node

        // For later serialization: additional node-specific fields.
        // This keeps models compact and avoids exploding the class count.
        public readonly Dictionary<string, object> Extra = new();

        public NodeModel(string type, string objectId, string name, int sgVersion = 0)
            : base(type, objectId, sgVersion)
        {
            Name = name;
        }

        public NodeRef AsRef() => new(ObjectId);

        public NodeModel SetPosition(float x, float y, float width = 208f, float height = 300f, bool expanded = true)
        {
            DrawState.Expanded = expanded;
            DrawState.Position.X = x;
            DrawState.Position.Y = y;
            DrawState.Position.Width = width;
            DrawState.Position.Height = height;
            return this;
        }

        public NodeModel AddSlot(string slotObjectId)
        {
            SlotObjectIds.Add(slotObjectId);
            return this;
        }

        public NodeModel SetExtra(string key, object value)
        {
            Extra[key] = value;
            return this;
        }
    }

    #endregion

    #region Slots

    [Serializable]
    public class SlotModel : GraphObject
    {
        public int Id;                 // m_Id (slot id integer used in edges)
        public string DisplayName;     // m_DisplayName
        public int SlotType;           // 0=input, 1=output
        public bool Hidden;
        public string ShaderOutputName;
        public int StageCapability = 3;

        // Common payload shapes (keep as object so different slot types can store different value types)
        public object Value;
        public object DefaultValue;

        // Some slots have labels
        public List<string> Labels = new();

        // Extra per-slot fields (UV channel, space, etc.)
        public readonly Dictionary<string, object> Extra = new();

        public SlotModel(string type, string objectId, int id, string displayName, int slotType, string shaderOutputName, int sgVersion = 0)
            : base(type, objectId, sgVersion)
        {
            Id = id;
            DisplayName = displayName;
            SlotType = slotType;
            ShaderOutputName = shaderOutputName;
        }

        public SlotModel SetValue(object value, object defaultValue)
        {
            Value = value;
            DefaultValue = defaultValue;
            return this;
        }

        public SlotModel SetStageCapability(int stageCapability)
        {
            StageCapability = stageCapability;
            return this;
        }

        public SlotModel SetExtra(string key, object value)
        {
            Extra[key] = value;
            return this;
        }
    }

    #endregion

    #region Properties

    [Serializable]
    public class ShaderPropertyModel : GraphObject
    {
        public string Name;                  // m_Name
        public string DefaultReferenceName;  // m_DefaultReferenceName
        public string OverrideReferenceName; // m_OverrideReferenceName
        public bool GeneratePropertyBlock = true;
        public bool Hidden;
        public int Precision = 0;

        // Property GUID inside the shadergraph (NOT the m_ObjectId)
        public string GuidSerialized;

        // Property value payload (varies per type)
        public object Value;

        // Extra fields (range, color mode, texture settings, etc.)
        public readonly Dictionary<string, object> Extra = new();

        public ShaderPropertyModel(string type, string objectId, string name, string defaultRefName, int sgVersion = 1)
            : base(type, objectId, sgVersion)
        {
            Name = name;
            DefaultReferenceName = defaultRefName;
            OverrideReferenceName = defaultRefName;
            GuidSerialized = System.Guid.NewGuid().ToString();
        }

        public PropertyRef AsRef() => new(ObjectId);

        public ShaderPropertyModel SetValue(object value)
        {
            Value = value;
            return this;
        }

        public ShaderPropertyModel SetExtra(string key, object value)
        {
            Extra[key] = value;
            return this;
        }
    }

    #endregion

    #region Categories / Targets (minimal typed models)

    [Serializable]
    public sealed class CategoryDataModel : GraphObject
    {
        public string Name;
        public readonly List<string> ChildPropertyObjectIds = new();

        public CategoryDataModel(string objectId, string name = "", int sgVersion = 0)
            : base("UnityEditor.ShaderGraph.CategoryData", objectId, sgVersion)
        {
            Name = name;
        }

        public CategoryDataModel AddProperty(PropertyRef propertyRef)
        {
            ChildPropertyObjectIds.Add(propertyRef.Id);
            return this;
        }
    }

    [Serializable]
    public sealed class TargetModel : GraphObject
    {
        public readonly Dictionary<string, object> Extra = new();

        public TargetModel(string type, string objectId, int sgVersion = 1)
            : base(type, objectId, sgVersion) { }

        public TargetModel SetExtra(string key, object value)
        {
            Extra[key] = value;
            return this;
        }
    }

    #endregion

    #region Utility Value Types (to keep JSON shapes consistent later)

    [Serializable]
    public struct Float2
    {
        public float x, y;
        public Float2(float x, float y) { this.x = x; this.y = y; }
    }

    [Serializable]
    public struct Float3
    {
        public float x, y, z;
        public Float3(float x, float y, float z) { this.x = x; this.y = y; this.z = z; }
    }

    [Serializable]
    public struct Float4
    {
        public float x, y, z, w;
        public Float4(float x, float y, float z, float w) { this.x = x; this.y = y; this.z = z; this.w = w; }
    }

    [Serializable]
    public struct ColorRGBA
    {
        public float r, g, b, a;
        public ColorRGBA(float r, float g, float b, float a) { this.r = r; this.g = g; this.b = b; this.a = a; }
    }

    #endregion
}
