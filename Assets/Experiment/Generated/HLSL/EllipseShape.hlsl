// Helper: Signed distance approximation for an ellipse
// Uses gradient normalization to fix distortion from non-uniform scaling
inline float sdEllipseApprox(float2 p, float2 r)
{
    // Avoid division by zero
    float a = max(r.x, 1e-6);
    float b = max(r.y, 1e-6);
    
    // Implicit equation F(x,y) = x^2/a^2 + y^2/b^2 - 1
    float F = (p.x * p.x) / (a * a) + (p.y * p.y) / (b * b) - 1.0;
    
    // Gradient magnitude |grad(F)| = 2 * sqrt(x^2/a^4 + y^2/b^4)
    float g2 = (p.x * p.x) / (a * a * a * a) + (p.y * p.y) / (b * b * b * b);
    float gradLen = 2.0 * sqrt(g2);
    
    // Distance approx = F / |grad(F)|
    return (gradLen > 1e-6) ? (F / gradLen) : -min(a, b);
}

void Ellipse_float(float2 UV, float RadiusX, float RadiusY, float4 Color, out float4 outColor)
{
    // PLAN:
    // 1) Center UV coordinates at (0.5, 0.5).
    // 2) Compute approximate signed distance to ellipse.
    // 3) Use fwidth() for automatic anti-aliasing width.
    // 4) Compute mask and output premultiplied color.
    
    // 1. Center UV
    float2 centered = UV - 0.5;
    
    // 2. Compute SDF (Negative inside, Positive outside)
    float dist = sdEllipseApprox(centered, float2(RadiusX, RadiusY));
    
    // 3. Anti-aliasing
    // fwidth(dist) gives the rate of change of distance per pixel
    float aa = fwidth(dist);
    aa = max(aa, 0.0001); // Safety clamp
    
    // 4. Compute Mask (1.0 inside, 0.0 outside)
    float mask = 1.0 - smoothstep(-aa, aa, dist);
    
    // 5. Output Color
    // Applying mask to RGB and Alpha for premultiplied-like behavior
    outColor = float4(Color.rgb * mask, mask);
}