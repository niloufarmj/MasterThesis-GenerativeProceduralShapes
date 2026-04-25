// PLAN:
// 1) Remap UV to centered coordinates (0.5, 0.5 center).
// 2) Protect against division by zero by clamping OuterRadius.
// 3) Calculate inner/outer ratio 'rf' for the star SDF.
// 4) Compute distance using Inigo Quilez's exact 5-pointed star SDF (folds space with k1, k2).
// 5) Anti-alias the edge using fwidth and smoothstep.
// 6) Output straight alpha composite.

#ifndef PI
#define PI 3.14159265359
#endif

// Signed distance to an upright 5-pointed star.
// p: local point, r: outer radius, rf: ratio of inner/outer radius
inline float sdStar5(float2 p, float r, float rf)
{
    // Magic constants for a 5-pointed star (cos(PI/5), -sin(PI/5))
    const float2 k1 = float2(0.809016994375, -0.587785252292);
    const float2 k2 = float2(-k1.x, k1.y);
    
    // Fold space to map all 5 points into a single sector
    p.x = abs(p.x);
    p -= 2.0 * max(dot(k1, p), 0.0) * k1;
    p -= 2.0 * max(dot(k2, p), 0.0) * k2;
    p.x = abs(p.x);
    
    // Shift tip to origin
    p.y -= r;
    
    // Line segment representing the star edge in the folded sector
    float2 ba = rf * float2(-k1.y, k1.x) - float2(0.0, 1.0);
    
    // Project point onto the segment
    float h = clamp(dot(p, ba) / dot(ba, ba), 0.0, r);
    
    // Distance to segment, with sign depending on which side of the line the point is
    return length(p - ba * h) * sign(p.y * ba.x - p.x * ba.y);
}

void Star5Shape_float(float2 UV, float OuterRadius, float InnerRadius, float4 FillColor, out float4 outColor)
{
    // 1) Center UV coordinates
    float2 centered = UV - 0.5;
    
    // 2) Ensure outer radius is valid to prevent div by zero
    float r = max(OuterRadius, 0.0001);
    
    // 3) Calculate ratio of inner to outer radius
    float rf = clamp(InnerRadius / r, 0.01, 0.99);
    
    // 4) Compute exact signed distance field
    float dist = sdStar5(centered, r, rf);
    
    // 5) Analytic anti-aliasing
    float aa = fwidth(dist);
    float edge = 1.0 - smoothstep(0.0, aa, dist);
    
    // 6) Output with straight alpha blending mask
    outColor = float4(FillColor.rgb * edge, FillColor.a * edge);
}