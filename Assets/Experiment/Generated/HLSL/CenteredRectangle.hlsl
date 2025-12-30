#ifndef PI
#define PI 3.14159265359
#endif

// Axis-aligned box SDF centered at origin with half extents b
float sdBox(float2 p, float2 b)
{
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

void FunctionName_float(float2 UV, float2 RectSize, float4 Color, out float4 outColor)
{
    // User request: A simple rectangle centered on the screen with adjustable width/height and solid fill.

    // PLAN:
    // 1) Center UV to [-0.5,0.5] around the screen center.
    // 2) Use RectSize as full width/height in UV units and convert to half extents.
    // 3) Compute rectangle SDF using sdBox.
    // 4) Turn SDF into a sharp mask with smoothstep-based AA.
    // 5) Output solid Color modulated by the mask (RGB and A).

    // 1) Center UV coordinates so (0.5,0.5) is origin
    float2 centered = UV - 0.5;

    // 2) Half extents from full size (RectSize.x = width, RectSize.y = height)
    float2 halfSize = 0.5 * RectSize;

    // 3) Rectangle SDF (negative inside, positive outside)
    float dist = sdBox(centered, halfSize);

    // 4) Anti-aliased edge: small transition around 0 for clean edges
    float edge = smoothstep(0.01, -0.01, dist);

    // 5) Output with solid color and alpha mask
    float mask = edge;
    outColor = float4(Color.rgb * mask, Color.a * mask);
}
