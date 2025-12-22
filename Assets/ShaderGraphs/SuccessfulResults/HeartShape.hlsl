#ifndef PI
#define PI 3.14159265359
#endif

// Helper: Square of dot product
float dot2(float2 v) { return dot(v, v); }

// SDF for a Heart shape
// Origin (0,0) is at the bottom tip. Lobes top out around y=1.0
// Formula adapted from Inigo Quilez
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

void HeartShape_float(float2 UV, float2 Center, float Size, float Rotation, float4 Color, float4 StrokeColor, float StrokeWidth, out float4 outColor)
{
    // PLAN:
    // 1) Recenter UVs to user-defined Center.
    // 2) Rotate the coordinate system.
    // 3) Scale coordinates to handle Size.
    // 4) Apply Y-offset to center the visual mass of the heart on the pivot.
    // 5) Calculate SDF.
    // 6) Apply Anti-Aliasing (AA) for Fill and Stroke.
    // 7) Composite final color.

    // 1) Recenter
    float2 p = UV - Center;

    // 2) Rotate
    float cosR = cos(Rotation);
    float sinR = sin(Rotation);
    p = float2(cosR * p.x + sinR * p.y, -sinR * p.x + cosR * p.y);

    // 3) Scale
    // Transform p into "unit shape" space. Protect against div by zero.
    float validSize = max(Size, 1e-5);
    float2 p_sdf = p / validSize;

    // 4) Visual Centering
    // The raw heart SDF has its tip at (0,0) and lobes around y=1.0.
    // To center it visually, we shift the local Y coordinate up by 0.5.
    p_sdf.y += 0.5;

    // 5) SDF Calculation
    float d_unit = sdHeart(p_sdf);
    
    // Convert distance back to UV space dimensions for consistent stroke/AA
    float d = d_unit * validSize;

    // 6) Anti-Aliasing & Masks
    float aa = fwidth(d);

    // Fill Mask (d < 0 is inside)
    float fillAlpha = 1.0 - smoothstep(0.0, aa, d);
    float4 fillLayer = float4(Color.rgb, Color.a * fillAlpha);

    // Stroke Mask (band centered on edge)
    float halfStroke = max(StrokeWidth, 0.0) * 0.5;
    float strokeDist = abs(d) - halfStroke;
    float strokeAlpha = 1.0 - smoothstep(0.0, aa, strokeDist);
    float4 strokeLayer = float4(StrokeColor.rgb, StrokeColor.a * strokeAlpha);

    // 7) Composite: Stroke OVER Fill
    outColor = over(strokeLayer, fillLayer);
}

// ------------------------------------------------------------------------
//  Visual Result (High-level, parameter-invariant description)
// ------------------------------------------------------------------------
//  This function generates a **stylized 2D heart-shaped primitive** using
//  a Signed Distance Function (SDF).
//
//  The shape forms a smooth, symmetric heart-like silhouette composed of
//  curved lobes and a pointed lower region. Its proportions, orientation,
//  placement, fill, and outline appearance are fully controlled by input
//  parameters and are not fixed by the function itself.
//
//  The output is an anti-aliased RGBA color suitable for icons,
//  symbolic UI elements, decorative graphics, and expressive procedural
//  2D visuals.
// ------------------------------------------------------------------------
