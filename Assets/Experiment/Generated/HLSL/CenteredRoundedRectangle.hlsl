#ifndef PI
#define PI 3.14159265359
#endif

// Simple SDF for axis-aligned box centered at origin with half extents b
float sdBox(float2 p, float2 b)
{
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// Rounded box SDF built from box + radius offset
float sdRoundedBox(float2 p, float2 b, float r)
{
    return sdBox(p, b - r) - r;
}

void FunctionName_float(float2 UV, float Width, float Height, float CornerRadius, float4 FillColor, out float4 outColor)
{
    // User request: A rectangle with rounded corners, centered on the screen with adjustable width, height, color, and roundness.

    // PLAN:
    // 1) Recenter UV to [-0.5,0.5] around screen center.
    // 2) Use Width/Height as full extents in UV space and convert to half extents.
    // 3) Compute rounded-rectangle SDF using sdRoundedBox with adjustable CornerRadius.
    // 4) Apply smoothstep on the SDF for anti-aliased edge.
    // 5) Use the resulting mask to output FillColor with smooth alpha.

    // 1) Center UV coordinates around (0.5,0.5)
    float2 centered = UV - 0.5;

    // 2) Half extents in UV space (Width/Height are full size in 0..1 units)
    float2 halfSize = 0.5 * float2(max(Width, 0.0), max(Height, 0.0));

    // Clamp corner radius so it never exceeds the minimum half-size
    float maxRadius = min(halfSize.x, halfSize.y);
    float r = clamp(CornerRadius, 0.0, maxRadius);

    // 3) Rounded rectangle SDF (negative inside, zero on edge, positive outside)
    float dist = sdRoundedBox(centered, halfSize, r);

    // 4) Anti-aliased edge using smoothstep; 0.01 is a small fixed AA width
    float edge = smoothstep(0.01, -0.01, dist);

    // 5) Final color with smooth alpha
    outColor = float4(FillColor.rgb * edge, edge);
}
