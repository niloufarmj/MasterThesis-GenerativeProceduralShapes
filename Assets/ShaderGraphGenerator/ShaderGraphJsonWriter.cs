using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text;

namespace ShaderGraphGenerator
{
    /// <summary>
    /// Serializes an in-memory ShaderGraphDataModel into the "ShaderGraph JSON" format used by Unity:
    /// One root GraphData JSON object, followed by many additional JSON objects (nodes/slots/properties/targets/etc.).
    /// </summary>
    public static class ShaderGraphJsonWriter
    {
        /// <summary>
        /// Writes the complete ShaderGraph JSON file as text.
        /// </summary>
        /// <param name="model">Graph model (refs + definitions).</param>
        /// <param name="graphName">Optional name (used only for debugging; Unity's ShaderGraph uses m_Path field).</param>
        /// <param name="useTransparency">If true, writer includes Alpha block in fragment context if present.</param>
        /// <param name="activeTargetId">Optional explicit active target id; if null writer uses first TargetModel in model.Targets or model.Definitions.</param>
        /// <param name="categoryId">Optional explicit category id; if null writer uses first CategoryDataModel in model.Categories or model.Definitions.</param>
        public static string Write(
            ShaderGraphDataModel model,
            string graphName = "Shader Graph",
            bool useTransparency = false,
            string activeTargetId = null,
            string categoryId = null)
        {
            if (model == null) throw new ArgumentNullException(nameof(model));

            // Resolve category/target ids if not passed
            categoryId ??= ResolveFirstDefinitionId<CategoryDataModel>(model)
                         ?? model.Categories.FirstOrDefault()?.ObjectId
                         ?? "";

            activeTargetId ??= ResolveFirstDefinitionId<TargetModel>(model)
                           ?? model.Targets.FirstOrDefault()?.ObjectId
                           ?? "";

            // Build Vertex/Fragment contexts by scanning BlockNodes (optional; safe defaults if none found)
            var vertexBlockNodeIds = FindBlockNodeIds(model, prefix: "VertexDescription.");
            var fragmentBlockNodeIds = FindBlockNodeIds(model, prefix: "SurfaceDescription.");

            // If transparency is on, prefer including Alpha block if it exists
            if (useTransparency)
            {
                // keep fragment blocks order as discovered; Unity doesn't require strict ordering, but stable is nice.
            }

            var sb = new StringBuilder(64 * 1024);

            // 1) Root GraphData object
            WriteRootGraphData(sb, model, categoryId, activeTargetId, vertexBlockNodeIds, fragmentBlockNodeIds);

            // 2) Definitions appended as separate JSON objects (Unity's ShaderGraph file format)
            foreach (var def in model.Definitions)
            {
                sb.AppendLine(); // newline separator
                WriteGraphObject(sb, def);
            }

            // Also include strongly-typed convenience lists if user stored them separately
            // (Avoid duplicates by tracking already written object ids)
            var written = new HashSet<string>(model.Definitions.Select(d => d.ObjectId));

            foreach (var c in model.Categories)
            {
                if (c != null && written.Add(c.ObjectId))
                {
                    sb.AppendLine();
                    WriteGraphObject(sb, c);
                }
            }

            foreach (var t in model.Targets)
            {
                if (t != null && written.Add(t.ObjectId))
                {
                    sb.AppendLine();
                    WriteGraphObject(sb, t);
                }
            }

            return sb.ToString();
        }

        // ---------------------------------------------------------------------
        // Root GraphData (matches the structure your old generator produced)
        // ---------------------------------------------------------------------
        private static void WriteRootGraphData(
            StringBuilder sb,
            ShaderGraphDataModel model,
            string categoryId,
            string activeTargetId,
            List<string> vertexBlockNodeIds,
            List<string> fragmentBlockNodeIds)
        {
            // Root must be the first JSON object.
            var root = new Dictionary<string, object>
            {
                ["m_SGVersion"] = 3,
                ["m_Type"] = "UnityEditor.ShaderGraph.GraphData",
                ["m_ObjectId"] = model.GraphObjectId,

                ["m_Properties"] = model.PropertyRefs.Select(p => (object)new Dictionary<string, object> { ["m_Id"] = p.Id }).ToList(),
                ["m_Keywords"] = new List<object>(),
                ["m_Dropdowns"] = new List<object>(),

                ["m_CategoryData"] = new List<object>
                {
                    new Dictionary<string, object> { ["m_Id"] = categoryId ?? "" }
                },

                ["m_Nodes"] = model.NodeRefs.Select(n => (object)new Dictionary<string, object> { ["m_Id"] = n.Id }).ToList(),

                ["m_GroupDatas"] = new List<object>(),
                ["m_StickyNoteDatas"] = new List<object>(),

                ["m_Edges"] = model.Edges.Select(e => (object)EdgeToJson(e)).ToList(),

                ["m_VertexContext"] = BuildContextJson(y: 0.0, blockNodeIds: vertexBlockNodeIds),
                ["m_FragmentContext"] = BuildContextJson(y: 200.0, blockNodeIds: fragmentBlockNodeIds),

                ["m_PreviewData"] = new Dictionary<string, object>
                {
                    ["serializedMesh"] = new Dictionary<string, object>
                    {
                        ["m_SerializedMesh"] = "{\"mesh\":{\"instanceID\":0}}",  // <-- CORRECT: raw string, WriteString will escape it
                        ["m_Guid"] = ""
                    },
                    ["preventRotation"] = false
                },

                ["m_Path"] = "Shader Graphs",
                ["m_GraphPrecision"] = 1,
                ["m_PreviewMode"] = 2,
                ["m_OutputNode"] = new Dictionary<string, object> { ["m_Id"] = "" },
                ["m_SubDatas"] = new List<object>(),

                ["m_ActiveTargets"] = new List<object>
                {
                    new Dictionary<string, object> { ["m_Id"] = activeTargetId ?? "" }
                }
            };

            WriteAnyJsonObject(sb, root);
        }

        private static Dictionary<string, object> BuildContextJson(double y, List<string> blockNodeIds)
        {
            return new Dictionary<string, object>
            {
                ["m_Position"] = new Dictionary<string, object>
                {
                    ["x"] = 0.0,
                    ["y"] = y
                },
                ["m_Blocks"] = blockNodeIds.Select(id => (object)new Dictionary<string, object> { ["m_Id"] = id }).ToList()
            };
        }

        private static Dictionary<string, object> EdgeToJson(EdgeModel e)
        {
            return new Dictionary<string, object>
            {
                ["m_OutputSlot"] = new Dictionary<string, object>
                {
                    ["m_Node"] = new Dictionary<string, object> { ["m_Id"] = e.OutputSlot.Node.Id },
                    ["m_SlotId"] = e.OutputSlot.SlotId
                },
                ["m_InputSlot"] = new Dictionary<string, object>
                {
                    ["m_Node"] = new Dictionary<string, object> { ["m_Id"] = e.InputSlot.Node.Id },
                    ["m_SlotId"] = e.InputSlot.SlotId
                }
            };
        }

        // ---------------------------------------------------------------------
        // Definitions serialization (GraphObject -> JSON)
        // ---------------------------------------------------------------------
        private static void WriteGraphObject(StringBuilder sb, GraphObject obj)
        {
            if (obj == null) return;

            // Base fields
            var dict = new Dictionary<string, object>
            {
                ["m_SGVersion"] = obj.SGVersion,
                ["m_Type"] = obj.Type,
                ["m_ObjectId"] = obj.ObjectId
            };

            switch (obj)
            {
                case NodeModel node:
                    Merge(dict, NodeToJson(node));
                    break;

                case SlotModel slot:
                    Merge(dict, SlotToJson(slot));
                    break;

                case ShaderPropertyModel prop:
                    Merge(dict, PropertyToJson(prop));
                    break;

                case CategoryDataModel cat:
                    Merge(dict, CategoryToJson(cat));
                    break;

                case TargetModel tgt:
                    Merge(dict, TargetToJson(tgt));
                    break;

                default:
                    // If you introduce new GraphObject types later, you can either:
                    // - handle them here, or
                    // - store everything in Extra dictionaries and fall through
                    break;
            }

            WriteAnyJsonObject(sb, dict);
        }

        private static Dictionary<string, object> NodeToJson(NodeModel node)
        {
            var d = new Dictionary<string, object>
            {
                ["m_Name"] = node.Name ?? "",
                ["m_DrawState"] = new Dictionary<string, object>
                {
                    ["m_Expanded"] = node.DrawState?.Expanded ?? true,
                    ["m_Position"] = new Dictionary<string, object>
                    {
                        ["serializedVersion"] = node.DrawState?.Position?.SerializedVersion ?? "2",
                        ["x"] = node.DrawState?.Position?.X ?? 0f,
                        ["y"] = node.DrawState?.Position?.Y ?? 0f,
                        ["width"] = node.DrawState?.Position?.Width ?? 0f,
                        ["height"] = node.DrawState?.Position?.Height ?? 0f
                    }
                },
                ["m_Slots"] = (node.SlotObjectIds ?? new List<string>())
                    .Select(id => (object)new Dictionary<string, object> { ["m_Id"] = id })
                    .ToList()
            };

            // Extra node fields (already shaped as dictionaries/lists/primitives)
            Merge(d, node.Extra);
            return d;
        }

        private static Dictionary<string, object> SlotToJson(SlotModel slot)
        {
            var d = new Dictionary<string, object>
            {
                ["m_Id"] = slot.Id,
                ["m_DisplayName"] = slot.DisplayName ?? "",
                ["m_SlotType"] = slot.SlotType,
                ["m_Hidden"] = slot.Hidden,
                ["m_ShaderOutputName"] = slot.ShaderOutputName ?? "",
                ["m_StageCapability"] = slot.StageCapability,
                ["m_Value"] = slot.Value,
                ["m_DefaultValue"] = slot.DefaultValue
            };

            // ShaderGraph expects m_Labels array present on many slots (safe to always include)
            var labels = slot.Labels ?? new List<string>();
            d["m_Labels"] = labels.Select(l => (object)l).ToList();

            Merge(d, slot.Extra);
            return d;
        }

        private static Dictionary<string, object> PropertyToJson(ShaderPropertyModel prop)
        {
            var d = new Dictionary<string, object>
            {
                ["m_Guid"] = new Dictionary<string, object>
                {
                    ["m_GuidSerialized"] = prop.GuidSerialized ?? Guid.NewGuid().ToString()
                },
                ["m_Name"] = prop.Name ?? "",
                ["m_DefaultReferenceName"] = prop.DefaultReferenceName ?? "",
                ["m_OverrideReferenceName"] = prop.OverrideReferenceName ?? prop.DefaultReferenceName ?? "",
                ["m_GeneratePropertyBlock"] = prop.GeneratePropertyBlock,
                ["m_Precision"] = prop.Precision,
                ["m_Hidden"] = prop.Hidden,

                // Property value goes here; exact shape depends on property type
                ["m_Value"] = prop.Value
            };

            Merge(d, prop.Extra);
            return d;
        }

        private static Dictionary<string, object> CategoryToJson(CategoryDataModel cat)
        {
            return new Dictionary<string, object>
            {
                ["m_Name"] = cat.Name ?? "",
                ["m_ChildObjectList"] = (cat.ChildPropertyObjectIds ?? new List<string>())
                    .Select(id => (object)new Dictionary<string, object> { ["m_Id"] = id })
                    .ToList()
            };
        }

        private static Dictionary<string, object> TargetToJson(TargetModel tgt)
        {
            // TargetModel is intentionally loose; everything is in Extra
            var d = new Dictionary<string, object>();
            Merge(d, tgt.Extra);
            return d;
        }

        // ---------------------------------------------------------------------
        // Finding blocks for contexts (optional convenience)
        // ---------------------------------------------------------------------
        private static List<string> FindBlockNodeIds(ShaderGraphDataModel model, string prefix)
        {
            var results = new List<string>();

            foreach (var def in model.Definitions)
            {
                if (def is not NodeModel n) continue;
                if (!string.Equals(n.Type, "UnityEditor.ShaderGraph.BlockNode", StringComparison.Ordinal)) continue;

                if (n.Extra != null && n.Extra.TryGetValue("m_SerializedDescriptor", out var descObj))
                {
                    var desc = descObj as string ?? "";
                    if (desc.StartsWith(prefix, StringComparison.Ordinal))
                        results.Add(n.ObjectId);
                }
                else
                {
                    // Fallback: sometimes node.Name is the descriptor
                    if (!string.IsNullOrEmpty(n.Name) && n.Name.StartsWith(prefix, StringComparison.Ordinal))
                        results.Add(n.ObjectId);
                }
            }

            return results;
        }

        private static string ResolveFirstDefinitionId<T>(ShaderGraphDataModel model) where T : GraphObject
        {
            foreach (var d in model.Definitions)
            {
                if (d is T typed) return typed.ObjectId;
            }
            return null;
        }

        // ---------------------------------------------------------------------
        // Minimal JSON serializer (no external libs)
        // ---------------------------------------------------------------------
        private static void WriteAnyJsonObject(StringBuilder sb, Dictionary<string, object> obj)
        {
            var jw = new MiniJsonWriter(sb);
            jw.WriteObject(obj);
        }

        private static void Merge(Dictionary<string, object> into, Dictionary<string, object> add)
        {
            if (add == null) return;
            foreach (var kv in add)
                into[kv.Key] = kv.Value;
        }

        private sealed class MiniJsonWriter
        {
            private readonly StringBuilder _sb;
            private int _indent;

            public MiniJsonWriter(StringBuilder sb) => _sb = sb;

            public void WriteObject(Dictionary<string, object> obj)
            {
                _indent = 0;
                WriteValue(obj);
                _sb.AppendLine();
            }

            private void WriteValue(object value)
            {
                switch (value)
                {
                    case null:
                        _sb.Append("null");
                        return;

                    case bool b:
                        _sb.Append(b ? "true" : "false");
                        return;

                    case int or long or short or byte:
                        _sb.Append(Convert.ToString(value, CultureInfo.InvariantCulture));
                        return;

                    case float f:
                        _sb.Append(f.ToString("0.0###############", CultureInfo.InvariantCulture));
                        return;

                    case double d:
                        _sb.Append(d.ToString("0.0###############", CultureInfo.InvariantCulture));
                        return;

                    case string s:
                        WriteString(s);
                        return;

                    case Dictionary<string, object> dict:
                        WriteDict(dict);
                        return;

                    case IDictionary genericDict:
                        // For rare cases where a non-generic IDictionary slips through
                        WriteDict(ToStringObjectDict(genericDict));
                        return;

                    case IEnumerable enumerable when value is not string:
                        WriteArray(enumerable);
                        return;

                    default:
                        // If a plain POCO slips through, try to reflect into a dictionary
                        WriteString(value.ToString());
                        return;
                }
            }

            private Dictionary<string, object> ToStringObjectDict(IDictionary dict)
            {
                var res = new Dictionary<string, object>();
                foreach (DictionaryEntry de in dict)
                {
                    var k = de.Key?.ToString() ?? "";
                    res[k] = de.Value;
                }
                return res;
            }

            private void WriteDict(Dictionary<string, object> dict)
            {
                _sb.AppendLine("{");
                _indent++;

                bool first = true;
                foreach (var kv in dict)
                {
                    if (!first) _sb.AppendLine(",");
                    first = false;

                    Indent();
                    WriteString(kv.Key);
                    _sb.Append(": ");
                    WriteValue(kv.Value);
                }

                _sb.AppendLine();
                _indent--;
                Indent();
                _sb.Append("}");
            }

             private void WriteArray(IEnumerable items)
            {
                // Check if array is empty first
                var itemList = items.Cast<object>().ToList();
                
                if (itemList.Count == 0)
                {
                    _sb.Append("[]");
                    return;
                }
                
                _sb.AppendLine("[");
                _indent++;

                bool first = true;
                foreach (var it in itemList)
                {
                    if (!first) _sb.AppendLine(",");
                    first = false;

                    Indent();
                    WriteValue(it);
                }

                _sb.AppendLine();
                _indent--;
                Indent();
                _sb.Append("]");
            }
            
            private void WriteString(string s)
            {
                _sb.Append('"');
                if (!string.IsNullOrEmpty(s))
                {
                    foreach (var ch in s)
                    {
                        switch (ch)
                        {
                            case '\\': _sb.Append("\\\\"); break;
                            case '"': _sb.Append("\\\""); break;
                            case '\n': _sb.Append("\\n"); break;
                            case '\r': _sb.Append("\\r"); break;
                            case '\t': _sb.Append("\\t"); break;
                            default:
                                if (ch < 32) _sb.AppendFormat("\\u{0:X4}", (int)ch);
                                else _sb.Append(ch);
                                break;
                        }
                    }
                }
                _sb.Append('"');
            }

            private void Indent()
            {
                for (int i = 0; i < _indent; i++)
                    _sb.Append("    ");
            }
        }
    }
}
