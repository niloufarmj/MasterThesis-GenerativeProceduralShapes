#ifndef PI
#define PI 3.14159265359
#endif

// Helper: Square of dot product
float dot2(float2 v) { return dot(v, v); }

// SDF for a Heart shape
// Origin (0,0) is at the bottom tip. Lobes top out around y=1.0
float sdHeart(float2 p)
{
    p.x = abs(p.x);

    if (p.y + p.x > 1.0)
        return sqrt(dot2(p - float2(0.25, 0.75))) - 0.35355339; // sqrt(2)/4

    return sqrt(min(dot2(p - float2(0.00, 1.00)),
                    dot2(p - 0.5 * max(p.x + p.y, 0.0)))) * sign(p.x - p.y);
}

// Straight-alpha blending (Source Over Destination)
float4 over(float4 src, float4 dst)
{
    float a = src.a + dst.a * (1.0 - src.a);
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-8);
    return float4(c, a);
}

void ParametricHeart_float(
    float2 UV,
    float2 Center,
    float Size,
    float2 ShapeProportions,
    float CornerRadius,
    float OutlineWidth,
    float4 FillColor,
    float4 OutlineColor,
    out float4 outColor)
{
    // Recenter UVs to user-defined Center
    float2 p = UV - Center;

    // Handle scaling and proportion stretching
    float validSize = max(Size, 1e-5);
    float2 s = max(ShapeProportions, 1e-4);
    
    // Transform to SDF unit space
    float2 p_sdf = p / (validSize * s);

    // Visual Centering (Heart SDF originates at bottom tip)
    p_sdf.y += 0.5;

    // Calculate raw distance
    float d_unit = sdHeart(p_sdf);
    
    // Convert distance back to true UV space dimensions for consistent stroke/AA.
    // We use min(s.x, s.y) to safely under-approximate the distorted distance field.
    float d = d_unit * validSize * min(s.x, s.y);

    // Apply corner radius for rounding the sharp edges
    d -= CornerRadius;

    // Anti-Aliasing
    float aa = fwidth(d);

    // Fill Layer (d < 0 is inside)
    float fillAlpha = 1.0 - smoothstep(0.0, aa, d);
    float4 fillLayer = float4(FillColor.rgb, FillColor.a * fillAlpha);

    // Outline Layer (band centered on the edge boundary)
    float halfStroke = max(OutlineWidth, 0.0) * 0.5;
    float strokeDist = abs(d) - halfStroke;
    float strokeAlpha = 1.0 - smoothstep(0.0, aa, strokeDist);
    float4 strokeLayer = float4(OutlineColor.rgb, OutlineColor.a * strokeAlpha);

    // Composite final color: Outline OVER Fill
    outColor = over(strokeLayer, fillLayer);
}