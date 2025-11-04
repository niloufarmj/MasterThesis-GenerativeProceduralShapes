using System.Collections.Generic;
using System.Linq;

namespace ShaderGraphGenerator
{
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
}