#ifndef PI
#define PI 3.14159265359
#endif

// Simple circle SDF: negative inside, positive outside
float sdCircle(float2 p, float radius)
{
    return length(p) - radius;
}

// PLAN:
// 1) Center UV around 0 using center at (0.5, 0.5).
// 2) Compute two circle SDFs for outer and inner radii.
// 3) Build a ring SDF by intersecting outer circle with the complement of inner circle.
// 4) Use smoothstep for anti-aliased mask.
// 5) Output single ring color with alpha equal to coverage.
//
// USER REQUEST: A hollow circle with adjustable inner and outer radius, single color ring.
void FunctionName_float(float2 UV, float InnerRadius, float OuterRadius, float4 RingColor, out float4 outColor)
{
    // Center UV coordinates (center fixed at 0.5, 0.5 as requested)
    float2 centered = UV - float2(0.5, 0.5);

    // Ensure radii are in a valid range
    float innerR = max(0.0, InnerRadius);
    float outerR = max(innerR + 1e-4, OuterRadius); // enforce outer > inner to keep ring valid

    // SDF for outer and inner circles
    float dOuter = sdCircle(centered, outerR);
    float dInner = sdCircle(centered, innerR);

    // Ring SDF using CSG: intersection of outer disk and complement of inner disk
    // Inside outer: dOuter <= 0, outside inner: dInner >= 0
    // Intersection: max(dOuter, -dInner)
    float dRing = max(dOuter, -dInner);

    // Anti-aliased edge for the ring shell
    float edge = smoothstep(0.01, -0.01, dRing);

    // Final color: single ring color with alpha = coverage mask
    float mask = edge;
    outColor = float4(RingColor.rgb * mask, mask);
}
