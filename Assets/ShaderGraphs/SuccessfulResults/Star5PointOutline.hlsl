/*
  PLAN:
  1. Define constants and helpers (PI, blending, Star SDF).
  2. Main Function (Star5PointOutline_float):
     a. Recenter UV coordinates based on Center input.
     b. Rotate the coordinate system by Rotation input.
     c. Calculate Signed Distance Field (SDF) for a 5-point star.
     d. Compute anti-aliasing width using fwidth.
     e. Generate Fill Mask (d < 0) and Stroke Mask (abs(d) < width).
     f. Composite Stroke over Fill for final output.
*/

#ifndef PI
#define PI 3.14159265359
#endif

// Helper: Straight-alpha "src over dst" blending
#ifndef NM_OVER_HELPER
#define NM_OVER_HELPER
inline float4 nm_over(float4 src, float4 dst)
{
    float a = src.a + dst.a * (1.0 - src.a);
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-8);
    return float4(c, a);
}
#endif

// Helper: Signed Distance Function for a 5-point Star
// p: centered point
// r: outer radius
// rf: inner radius
#ifndef SD_STAR5_HELPER
#define SD_STAR5_HELPER
inline float sdStar5(float2 p, float r, float rf)
{
    const float2 k1 = float2(0.809016994375, -0.587785252292);
    const float2 k2 = float2(-k1.x, k1.y);
    p.x = abs(p.x);
    p -= 2.0 * max(dot(k1, p), 0.0) * k1;
    p -= 2.0 * max(dot(k2, p), 0.0) * k2;
    p.x = abs(p.x);
    p.y -= r;
    float2 ba = rf * float2(-k1.y, k1.x) - float2(0, 1);
    float h = clamp( dot(p,ba)/dot(ba,ba), 0.0, r );
    return length(p-ba*h) * sign(p.y*ba.x-p.x*ba.y);
}
#endif

void Star5PointOutline_float(float2 UV, float Radius, float InnerRadius, float2 Center, float Rotation, float4 FillColor, float4 StrokeColor, float StrokeWidth, out float4 outColor)
{
    // 1) Recenter UV space
    float2 p = UV - Center;

    // 2) Rotate sampling point by -Rotation (result: shape rotates by +Rotation)
    float c = cos(Rotation);
    float s = sin(Rotation);
    p = float2(c * p.x + s * p.y, -s * p.x + c * p.y);

    // 3) Calculate Signed Distance
    // Clamp radii to ensure stability (InnerRadius shouldn't exceed Radius for a star)
    float d = sdStar5(p, max(Radius, 0.001), max(InnerRadius, 0.0));

    // 4) Analytic Anti-Aliasing
    float aa = fwidth(d);

    // 5) Fill Coverage
    // Star interior is where d < 0
    float fillMask = 1.0 - smoothstep(0.0, aa, d);
    float4 fillOut = float4(FillColor.rgb, saturate(FillColor.a) * fillMask);

    // 6) Stroke Coverage
    // Stroke is a band of width 'StrokeWidth' centered on the edge (d=0)
    float halfW = 0.5 * max(StrokeWidth, 0.0);
    float edgeDist = abs(d) - halfW;
    float strokeMask = 1.0 - smoothstep(0.0, aa, edgeDist);
    float4 strokeOut = float4(StrokeColor.rgb, saturate(StrokeColor.a) * strokeMask);

    // 7) Composite Stroke over Fill
    outColor = nm_over(strokeOut, fillOut);
}

// ------------------------------------------------------------------------
//  Visual Result (High-level, parameter-invariant description)
// ------------------------------------------------------------------------
//  This function generates a **2D five-pointed star primitive with optional
//  outline (stroke)** using Signed Distance Functions (SDFs).
//
//  The shape forms a classic five-point star silhouette with alternating
//  outer and inner vertices. It supports both a filled interior and a
//  surrounding outline, creating either a solid or outlined star appearance.
//  The radii, rotation, placement, fill color, outline color, and outline
//  thickness are fully controlled by input parameters and are not fixed by
//  the function itself.
//
//  The output is an anti-aliased RGBA color suitable for icons, ratings,
//  decorative UI elements, badges, and analytic procedural 2D graphics.
// ------------------------------------------------------------------------
