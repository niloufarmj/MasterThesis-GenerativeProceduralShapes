#ifndef PI
#define PI 3.14159265359
#endif

// Signed distance to an axis-aligned box centered at origin with half extents b
float sdBox(float2 p, float2 b)
{
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// Rounded rectangle via SDF offset: d_round = sdBox(p, halfSize - r) - r
float sdRoundedBox(float2 p, float2 halfSize, float radius)
{
    float2 innerSize = halfSize - radius;
    innerSize = max(innerSize, 0.0);
    float d = sdBox(p, innerSize) - radius;
    return d;
}

// PLAN:
// 1) Center UV to (0.5,0.5) and scale by Width/Height to get local coordinates.
// 2) Build rounded-rectangle SDF using sdRoundedBox with adjustable CornerRadius.
// 3) Clamp CornerRadius so it smoothly transitions from sharp to very round corners.
// 4) Use smoothstep for anti-aliased edge.
// 5) Output FillColor modulated by the coverage mask, with alpha = mask.

// User request: A rectangle with rounded corners, centered on the screen. The corner roundness should be adjustable.

void FunctionName_float(float2 UV, float Width, float Height, float CornerRadius, float4 FillColor, out float4 outColor)
{
    // Ensure positive sizes
    Width = max(Width, 0.0);
    Height = max(Height, 0.0);

    // 1) Center UV coordinates around (0.5,0.5)
    float2 centered = UV - float2(0.5, 0.5);

    // Local space: rectangle centered at origin with given Width/Height in UV units
    float2 halfSize = 0.5 * float2(Width, Height);

    // 3) Clamp corner radius so it smoothly goes from 0 to max half-size
    float maxRadius = min(halfSize.x, halfSize.y);
    float radius = clamp(CornerRadius, 0.0, maxRadius);

    // 2) Rounded rectangle SDF
    float dist = sdRoundedBox(centered, halfSize, radius);

    // 4) Anti-aliased edge using a small fixed AA width in UV space
    float aa = 0.01;
    float edge = smoothstep(aa, -aa, dist);

    // 5) Output with smooth alpha
    float mask = edge;
    outColor = float4(FillColor.rgb * mask, mask);
}
