using System.Threading.Tasks;

namespace ShaderGraphExperiments.Providers
{
    public interface IEvalProvider
    {
        string Name { get; }
        Task<string> EvaluateImageAsync(string userPrompt, string hlslCode, string propertiesJson, string previewPngPath);
    }
}
