using System.Collections.Generic;
using UnityEngine;

/// <summary>
/// Arranges all Quad objects in the scene into a static grid and animates ALL their material parameters
/// with random back-and-forth motion for showcase video recording.
/// NO camera movement - only shapes animate!
/// </summary>
public class ShapeShowcaseAnimator : MonoBehaviour
{
    [Header("Grid Settings")]
    [Tooltip("Number of columns in the grid")]
    public int columns = 8;
    
    [Tooltip("Spacing between shapes")]
    public float spacing = 1.5f;
    
    [Tooltip("Starting position of the grid (top-left corner)")]
    public Vector3 gridOrigin = new Vector3(-5f, 4f, 0f);
    
    [Header("Animation Settings")]
    [Tooltip("Enable/disable animation")]
    public bool animateParameters = true;
    
    [Tooltip("Global animation speed multiplier")]
    [Range(0.1f, 3f)]
    public float animationSpeed = 0.8f;
    
    [Tooltip("How much to vary float parameters (percentage of their range)")]
    [Range(0.05f, 0.5f)]
    public float floatVariationStrength = 0.25f;
    
    [Tooltip("How much to vary color hue (0 = no change, 0.5 = full rainbow)")]
    [Range(0f, 0.3f)]
    public float colorHueVariation = 0.08f;
    
    [Tooltip("How much to vary color saturation")]
    [Range(0f, 0.3f)]
    public float colorSaturationVariation = 0.1f;
    
    [Tooltip("How much to vary vector parameters (like Center)")]
    [Range(0f, 0.1f)]
    public float vectorVariation = 0.03f;
    
    [Header("Debug")]
    [Tooltip("Log found parameters to console")]
    public bool logParameters = true;
    
    // Internal data
    private List<QuadData> quadDataList = new List<QuadData>();
    private float globalTime = 0f;
    
    // Stores info about each animatable parameter
    private class AnimatedParameter
    {
        public string name;
        public enum ParamType { Float, Color, Vector }
        public ParamType type;
        
        // Original values (to animate around)
        public float originalFloat;
        public Color originalColor;
        public Vector4 originalVector;
        
        // Range limits for floats
        public float minValue;
        public float maxValue;
        
        // Randomized animation characteristics (different for each parameter!)
        public float speed;      // How fast this parameter oscillates
        public float phase;      // Starting phase offset
        public float amplitude;  // How strong the oscillation is
    }
    
    private class QuadData
    {
        public GameObject gameObject;
        public Material material;
        public int gridIndex;
        public List<AnimatedParameter> parameters = new List<AnimatedParameter>();
    }
    
    // Parameters to skip (internal Unity/ShaderGraph parameters that shouldn't be animated)
    private static readonly HashSet<string> SkipParameters = new HashSet<string>
    {
        "_MainTex", "_MainTex_ST", "_MainTex_TexelSize", "_MainTex_HDR",
        "_SrcBlend", "_DstBlend", "_ZWrite", "_Cull", "_ZTest",
        "_Surface", "_Blend", "_AlphaClip", "_QueueOffset", "_QueueControl",
        "_BUILTIN_Surface", "_BUILTIN_Blend", "_BUILTIN_AlphaClip", 
        "_BUILTIN_QueueOffset", "_BUILTIN_QueueControl",
        "_CastShadows", "_ReceiveShadows", "_AlphaToMask",
        "unity_Lightmaps", "unity_LightmapsInd", "unity_ShadowMasks"
    };
    
    void Start()
    {
        CollectAndArrangeQuads();
    }
    
    [ContextMenu("1. Auto-Calculate Grid Settings")]
    public void AutoCalculateGridSettings()
    {
        GameObject[] allObjects = FindObjectsOfType<GameObject>();
        int quadCount = 0;
        foreach (var obj in allObjects)
        {
            if (obj.name.Contains("Quad") && obj.GetComponent<Renderer>() != null)
                quadCount++;
        }
        
        if (quadCount == 0)
        {
            Debug.LogWarning("[ShapeShowcaseAnimator] No quads found!");
            return;
        }
        
        // Calculate optimal grid size (aim for roughly square)
        columns = Mathf.CeilToInt(Mathf.Sqrt(quadCount));
        int rows = Mathf.CeilToInt((float)quadCount / columns);
        
        // Calculate grid origin to center the grid in view
        float totalWidth = (columns - 1) * spacing;
        float totalHeight = (rows - 1) * spacing;
        
        gridOrigin = new Vector3(-totalWidth / 2f, totalHeight / 2f, 0f);
        
        Debug.Log($"[ShapeShowcaseAnimator] Auto-calculated: {columns} columns × {rows} rows for {quadCount} quads. Grid origin: {gridOrigin}");
    }
    
    [ContextMenu("2. Collect and Arrange Quads")]
    public void CollectAndArrangeQuads()
    {
        quadDataList.Clear();
        
        // Find all GameObjects with "Quad" in their name
        GameObject[] allObjects = FindObjectsOfType<GameObject>();
        List<GameObject> quads = new List<GameObject>();
        
        foreach (var obj in allObjects)
        {
            if (obj.name.Contains("Quad") && obj.GetComponent<Renderer>() != null)
            {
                quads.Add(obj);
            }
        }
        
        // Sort alphabetically for consistent ordering
        quads.Sort((a, b) => a.name.CompareTo(b.name));
        
        Debug.Log($"[ShapeShowcaseAnimator] Found {quads.Count} quads to arrange");
        
        int totalParameters = 0;
        
        // Arrange in grid and collect data
        for (int i = 0; i < quads.Count; i++)
        {
            int row = i / columns;
            int col = i % columns;
            
            Vector3 position = gridOrigin + new Vector3(col * spacing, -row * spacing, 0f);
            
            GameObject quad = quads[i];
            quad.transform.position = position;
            quad.transform.rotation = Quaternion.identity;
            quad.transform.localScale = Vector3.one;
            
            // Get material and store data
            Renderer renderer = quad.GetComponent<Renderer>();
            if (renderer != null && renderer.sharedMaterial != null)
            {
                // Create instance of material to avoid modifying shared materials
                Material matInstance = new Material(renderer.sharedMaterial);
                renderer.material = matInstance;
                
                QuadData data = new QuadData
                {
                    gameObject = quad,
                    material = matInstance,
                    gridIndex = i
                };
                
                // Discover ALL animatable parameters from this material
                DiscoverParameters(data, matInstance);
                totalParameters += data.parameters.Count;
                
                quadDataList.Add(data);
                
                if (logParameters && data.parameters.Count > 0)
                {
                    string paramNames = string.Join(", ", data.parameters.ConvertAll(p => p.name));
                    Debug.Log($"[{quad.name}] {data.parameters.Count} params: {paramNames}");
                }
            }
        }
        
        Debug.Log($"[ShapeShowcaseAnimator] Arranged {quadDataList.Count} quads with {totalParameters} total animatable parameters");
    }
    
    private void DiscoverParameters(QuadData data, Material mat)
    {
        Shader shader = mat.shader;
        int propertyCount = shader.GetPropertyCount();
        
        for (int i = 0; i < propertyCount; i++)
        {
            string propName = shader.GetPropertyName(i);
            
            // Skip internal/system parameters
            if (SkipParameters.Contains(propName)) continue;
            if (propName.StartsWith("unity_")) continue;
            if (propName.StartsWith("_BUILTIN_")) continue;
            
            var propType = shader.GetPropertyType(i);
            
            // Create parameter with RANDOM animation characteristics
            AnimatedParameter param = new AnimatedParameter
            {
                name = propName,
                speed = Random.Range(0.4f, 1.8f),           // Random speed
                phase = Random.Range(0f, Mathf.PI * 2f),    // Random starting phase
                amplitude = Random.Range(0.6f, 1.0f)        // Random amplitude
            };
            
            switch (propType)
            {
                case UnityEngine.Rendering.ShaderPropertyType.Range:
                    // Range type - we can get the limits
                    param.type = AnimatedParameter.ParamType.Float;
                    param.originalFloat = mat.GetFloat(propName);
                    
                    // Get range limits from shader (only valid for Range type!)
                    Vector2 range = shader.GetPropertyRangeLimits(i);
                    param.minValue = range.x;
                    param.maxValue = range.y;
                    
                    data.parameters.Add(param);
                    break;
                    
                case UnityEngine.Rendering.ShaderPropertyType.Float:
                    // Regular float - use default range based on current value
                    param.type = AnimatedParameter.ParamType.Float;
                    param.originalFloat = mat.GetFloat(propName);
                    
                    // Estimate reasonable range based on current value
                    float currentVal = param.originalFloat;
                    if (currentVal >= 0f && currentVal <= 1f)
                    {
                        param.minValue = 0f;
                        param.maxValue = 1f;
                    }
                    else if (currentVal > 1f)
                    {
                        param.minValue = 0f;
                        param.maxValue = currentVal * 2f;
                    }
                    else
                    {
                        param.minValue = currentVal * 2f;
                        param.maxValue = Mathf.Abs(currentVal) * 2f;
                    }
                    
                    data.parameters.Add(param);
                    break;
                    
                case UnityEngine.Rendering.ShaderPropertyType.Color:
                    param.type = AnimatedParameter.ParamType.Color;
                    param.originalColor = mat.GetColor(propName);
                    data.parameters.Add(param);
                    break;
                    
                case UnityEngine.Rendering.ShaderPropertyType.Vector:
                    param.type = AnimatedParameter.ParamType.Vector;
                    param.originalVector = mat.GetVector(propName);
                    // Only animate vectors that look like coordinates/offsets
                    if (IsAnimatableVector(param.originalVector))
                    {
                        data.parameters.Add(param);
                    }
                    break;
            }
        }
    }
    
    private bool IsAnimatableVector(Vector4 v)
    {
        // Only animate vectors with reasonable coordinate-like values
        return Mathf.Abs(v.x) < 10f && Mathf.Abs(v.y) < 10f && 
               Mathf.Abs(v.z) < 10f && Mathf.Abs(v.w) < 10f;
    }
    
    void Update()
    {
        if (!animateParameters || quadDataList.Count == 0) return;
        
        globalTime += Time.deltaTime * animationSpeed;
        
        // Animate each quad's parameters
        foreach (var data in quadDataList)
        {
            if (data.material == null) continue;
            
            foreach (var param in data.parameters)
            {
                // Calculate unique sine wave for this parameter
                // Each parameter has its own speed, phase, and amplitude!
                float wave = Mathf.Sin(globalTime * param.speed + param.phase) * param.amplitude;
                
                switch (param.type)
                {
                    case AnimatedParameter.ParamType.Float:
                        AnimateFloat(data.material, param, wave);
                        break;
                        
                    case AnimatedParameter.ParamType.Color:
                        AnimateColor(data.material, param, wave);
                        break;
                        
                    case AnimatedParameter.ParamType.Vector:
                        AnimateVector(data.material, param, wave);
                        break;
                }
            }
        }
    }
    
    private void AnimateFloat(Material mat, AnimatedParameter param, float wave)
    {
        float rangeSize = param.maxValue - param.minValue;
        float variation = rangeSize * floatVariationStrength * wave;
        
        float newValue = param.originalFloat + variation;
        newValue = Mathf.Clamp(newValue, param.minValue, param.maxValue);
        
        mat.SetFloat(param.name, newValue);
    }
    
    private void AnimateColor(Material mat, AnimatedParameter param, float wave)
    {
        Color.RGBToHSV(param.originalColor, out float h, out float s, out float v);
        
        // Shift hue
        float newH = Mathf.Repeat(h + wave * colorHueVariation, 1f);
        
        // Shift saturation
        float newS = Mathf.Clamp01(s + wave * colorSaturationVariation);
        
        // Keep brightness mostly stable
        float newV = Mathf.Clamp01(v + wave * 0.03f);
        
        Color newColor = Color.HSVToRGB(newH, newS, newV);
        newColor.a = param.originalColor.a; // Preserve original alpha
        
        mat.SetColor(param.name, newColor);
    }
    
    private void AnimateVector(Material mat, AnimatedParameter param, float wave)
    {
        Vector4 original = param.originalVector;
        
        // Use slightly different wave for each component to create organic movement
        float waveX = wave;
        float waveY = Mathf.Sin(globalTime * param.speed * 0.8f + param.phase + 0.5f) * param.amplitude;
        
        Vector4 newVector = new Vector4(
            original.x + waveX * vectorVariation,
            original.y + waveY * vectorVariation,
            original.z,  // Keep z and w stable
            original.w
        );
        
        mat.SetVector(param.name, newVector);
    }
    
    [ContextMenu("3. Randomize Animation Timing")]
    public void RandomizeAnimationPhases()
    {
        foreach (var data in quadDataList)
        {
            foreach (var param in data.parameters)
            {
                param.speed = Random.Range(0.4f, 1.8f);
                param.phase = Random.Range(0f, Mathf.PI * 2f);
                param.amplitude = Random.Range(0.6f, 1.0f);
            }
        }
        Debug.Log("[ShapeShowcaseAnimator] Randomized all animation timing - each parameter now has unique speed/phase!");
    }
    
    [ContextMenu("Reset All Parameters to Original")]
    public void ResetAllParameters()
    {
        foreach (var data in quadDataList)
        {
            if (data.material == null) continue;
            
            foreach (var param in data.parameters)
            {
                switch (param.type)
                {
                    case AnimatedParameter.ParamType.Float:
                        data.material.SetFloat(param.name, param.originalFloat);
                        break;
                    case AnimatedParameter.ParamType.Color:
                        data.material.SetColor(param.name, param.originalColor);
                        break;
                    case AnimatedParameter.ParamType.Vector:
                        data.material.SetVector(param.name, param.originalVector);
                        break;
                }
            }
        }
        Debug.Log("[ShapeShowcaseAnimator] Reset all parameters to original values");
    }
    
    [ContextMenu("Log All Discovered Parameters")]
    public void LogAllParameterNames()
    {
        Debug.Log("=== ALL DISCOVERED PARAMETERS ===");
        foreach (var data in quadDataList)
        {
            string paramList = "";
            foreach (var param in data.parameters)
            {
                string extra = param.type == AnimatedParameter.ParamType.Float 
                    ? $" [{param.minValue:F2}-{param.maxValue:F2}]" 
                    : "";
                paramList += $"\n  • {param.name} ({param.type}){extra}";
            }
            Debug.Log($"[{data.gameObject.name}]{paramList}");
        }
    }
    
    void OnDrawGizmosSelected()
    {
        Gizmos.color = new Color(1f, 1f, 0f, 0.3f);
        
        // Draw grid preview
        int previewCount = columns * 10;
        for (int i = 0; i < previewCount; i++)
        {
            int row = i / columns;
            int col = i % columns;
            Vector3 pos = gridOrigin + new Vector3(col * spacing, -row * spacing, 0f);
            Gizmos.DrawWireCube(pos, Vector3.one * (spacing * 0.9f));
        }
    }
}