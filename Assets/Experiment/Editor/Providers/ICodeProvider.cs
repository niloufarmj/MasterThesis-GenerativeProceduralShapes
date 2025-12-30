using System.Threading.Tasks;

namespace ShaderGraphExperiments.Providers
{
    public interface ICodeProvider
    {
        string Name { get; }
        Task<string> GenerateShaderJsonAsync(string prompt);
        Task<string> RefineShaderJsonAsync(string refinementPrompt);
    }
}
