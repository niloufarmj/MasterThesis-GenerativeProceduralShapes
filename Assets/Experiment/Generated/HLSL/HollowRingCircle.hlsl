#ifndef PI
#define PI 3.14159265359
#endif

// Signed distance to a circle centered at origin with radius r
inline float sdCircle(float2 p, float r)
{
    return length(p) - r;
}

// PLAN:
// 1) Center UV around (0.5,0.5) and scale to -1..1 space for uniform sizing.
// 2) Compute SDF for outer circle (radius = OuterRadius).
// 3) Compute SDF for inner circle (radius = InnerRadius).
// 4) Build a ring by subtracting inner from outer: ringSDF = max(dOuter, -dInner).
// 5) Use fwidth-based smoothstep for anti-aliased edges.
// 6) Output single ring color with alpha = coverage mask.
// USER REQUEST: A hollow circle with adjustable inner and outer radii, solid single color ring.
void FunctionName_float(float2 UV, float InnerRadius, float OuterRadius, float4 RingColor, out float4 outColor)
{
    // Ensure radii are non-negative and InnerRadius <= OuterRadius
    float innerR = max(InnerRadius, 0.0);
    float outerR = max(OuterRadius, 0.0);
    innerR = min(innerR, outerR);

    // 1) Center UV to origin and scale to -1..1 space
    float2 centered = (UV - 0.5) * 2.0;

    // 2) Outer circle SDF (negative inside outer circle)
    float dOuter = sdCircle(centered, outerR);

    // 3) Inner circle SDF (negative inside inner circle)
    float dInner = sdCircle(centered, innerR);

    // 4) Ring SDF: inside ring where inside outer AND outside inner
    float ringSDF = max(dOuter, -dInner);

    // 5) Anti-aliased edge using analytic derivatives
    float aa = fwidth(ringSDF);
    float mask = 1.0 - smoothstep(0.0, aa, ringSDF);

    // 6) Output color with straight alpha based on coverage
    outColor = float4(RingColor.rgb * mask, mask);
}
