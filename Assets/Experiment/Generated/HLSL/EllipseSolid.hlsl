#ifndef PI
#define PI 3.14159265359
#endif

// Helper: Signed pseudo-distance to an axis-aligned ellipse
// Uses gradient normalization for better AA properties than algebraic distance
inline float sdEllipseApprox(float2 p, float2 halfAxes)
{
    // Avoid division by zero
    float a = max(halfAxes.x, 1e-8);
    float b = max(halfAxes.y, 1e-8);
    
    float x = p.x;
    float y = p.y;
    
    // Implicit equation F(x,y) = x^2/a^2 + y^2/b^2 - 1
    // Distance approx = F / |grad F|
    
    float F = (x * x) / (a * a) + (y * y) / (b * b) - 1.0;
    float gradLen = 2.0 * sqrt( (x * x) / (a * a * a * a) + (y * y) / (b * b * b * b) );
    
    // Robustness check for center to avoid divide by zero
    return (gradLen > 1e-6) ? (F / gradLen) : -min(a, b);
}

void EllipseSolid_float(float2 UV, float Width, float Height, float2 Center, float4 Color, out float4 outColor)
{
    // PLAN:
    // 1) Recenter UV to Center.
    // 2) Define half-axes (radii) from Width and Height.
    // 3) Compute signed distance field (SDF) for the ellipse.
    // 4) Compute smooth mask using fwidth for anti-aliasing.
    // 5) Output color with alpha.

    // 1) Recenter
    float2 p = UV - Center;

    // 2) Dimensions (Convert diameter to radius)
    float2 radii = float2(max(Width, 0.0), max(Height, 0.0)) * 0.5;

    // 3) Calculate SDF (Negative inside, positive outside)
    float dist = sdEllipseApprox(p, radii);

    // 4) Anti-aliasing
    // fwidth allows pixel-perfect smoothing regardless of shape scale
    float aa = fwidth(dist);
    float mask = 1.0 - smoothstep(-aa, aa, dist);

    // 5) Output
    // Apply mask to both RGB and Alpha for correct compositing
    outColor = float4(Color.rgb * mask, Color.a * mask);
}