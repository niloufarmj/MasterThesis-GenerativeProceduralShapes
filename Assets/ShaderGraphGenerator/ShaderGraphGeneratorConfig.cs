using UnityEngine;

[CreateAssetMenu(
    fileName = "ShaderGraphGeneratorConfig",
    menuName = "ShaderGraphGenerator/Config",
    order = 1)]
public class ShaderGraphGeneratorConfig : ScriptableObject
{
    public string openAIKey;
    public string claudeKey;
    public string geminiKey;
}
