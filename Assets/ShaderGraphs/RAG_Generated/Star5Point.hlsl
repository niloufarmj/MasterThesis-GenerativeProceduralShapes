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
    float2 ba = rf * float2(-k1.y, k1.x) - float2(0.0, 1.0);
    float h = clamp(dot(p, ba) / dot(ba, ba), 0.0, r);
    return length(p - ba * h) * sign(p.y * ba.x - p.x * ba.y);
}
#endif

void Star5Point_float(
    float2 UV,
    float Size,
    float InnerRatio,
    float Rotation,
    float4 Color,
    out float4 outColor
)
{
    // Center UVs
    float2 p = UV - 0.5;
    
    // Rotate coordinate system
    float c = cos(Rotation);
    float s = sin(Rotation);
    p = float2(c * p.x + s * p.y, -s * p.x + c * p.y);
    
    // Calculate Signed Distance
    // InnerRatio acts as the proportion of inner radius to outer radius (Size)
    float d = sdStar5(p, max(Size, 0.0001), clamp(InnerRatio, 0.001, 0.999));
    
    // Procedural Anti-Aliasing
    float aa = max(fwidth(d), 1e-5);
    float alpha = 1.0 - smoothstep(0.0, aa, d);
    
    // Output final composited color
    outColor = float4(Color.rgb, saturate(Color.a) * alpha);
}
