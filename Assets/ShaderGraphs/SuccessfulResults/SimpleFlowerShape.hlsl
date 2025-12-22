#ifndef PI
#define PI 3.14159265359
#endif

// Helper: Straight-alpha "src over dst" composition
float4 nm_over(float4 src, float4 dst)
{
    float a = src.a + dst.a * (1.0 - src.a);
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-8);
    return float4(c, a);
}

void SimpleFlowerShape_float(float2 UV, float PetalCount, float PetalSize, float CenterRadius, float Rotation, float4 PetalColor, float4 CenterColor, out float4 outColor)
{
    // PLAN:
    // 1) Center UVs and apply rotation.
    // 2) Convert to polar coordinates (radius 'r', angle 'a').
    // 3) Define Petal shape function using cosine wave on angle.
    // 4) Compute SDFs for Petals and Center circle.
    // 5) Apply anti-aliasing via fwidth.
    // 6) Composite Center layer OVER Petal layer.

    // 1) Center and Rotate
    float2 p = UV - 0.5;
    float c = cos(Rotation);
    float s = sin(Rotation);
    p = float2(c * p.x - s * p.y, s * p.x + c * p.y);

    // 2) Polar Coordinates
    float r = length(p);
    float a = atan2(p.y, p.x);

    // 3) Petal Shape Definition
    // The petal radius varies with angle. We use a cosine wave.
    // Base offset ensures petals attach to the center.
    float wave = 0.5 + 0.5 * cos(a * PetalCount);
    float petalLimit = CenterRadius * 0.6 + PetalSize * wave;

    // 4) SDF Calculation (Approximated)
    // Distance positive outside, negative inside
    float dPetal = r - petalLimit;
    float dCenter = r - CenterRadius;

    // 5) Anti-aliasing
    // Use fwidth to get a sharp but anti-aliased edge regardless of scale
    float aaPetal = fwidth(dPetal);
    float aaCenter = fwidth(dCenter);

    float maskPetal = 1.0 - smoothstep(0.0, aaPetal, dPetal);
    float maskCenter = 1.0 - smoothstep(0.0, aaCenter, dCenter);

    // 6) Composition
    float4 layerPetal = float4(PetalColor.rgb, PetalColor.a * maskPetal);
    float4 layerCenter = float4(CenterColor.rgb, CenterColor.a * maskCenter);

    // Draw Center OVER Petals
    outColor = nm_over(layerCenter, layerPetal);
}

// ------------------------------------------------------------------------
//  Visual Result (High-level, parameter-invariant description)
// ------------------------------------------------------------------------
//  This function generates a **simple stylized 2D flower-like primitive**
//  using Signed Distance Functions (SDFs).
//
//  The shape consists of multiple elongated petal forms arranged radially
//  around a central circular region, creating a symbolic floral silhouette.
//  The number of petals, their size, the center size, rotation, and color
//  composition are fully controlled by input parameters and are not fixed
//  by the function itself.
//
//  The output is an anti-aliased RGBA color suitable for decorative icons,
//  playful UI elements, symbolic graphics, and expressive procedural
//  2D visuals.
// ------------------------------------------------------------------------
