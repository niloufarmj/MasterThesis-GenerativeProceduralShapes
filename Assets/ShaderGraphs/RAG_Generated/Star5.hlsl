#ifndef PI
#define PI 3.14159265359
#endif

// Helper: Signed Distance Function for a 5-point Star
// p: centered point
// r: outer radius
// rf: inner radius ratio
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
    float h = clamp(dot(p, ba) / dot(ba, ba), 0.0, r);
    return length(p - ba * h) * sign(p.y * ba.x - p.x * ba.y);
}
#endif

void Star5_float(
    float2 UV,
    float2 Center,
    float Size,
    float InnerRadiusRatio,
    float Rotation,
    float4 Color,
    out float4 outColor
) {
    float2 p = UV - Center;

    // Apply rotation
    float c = cos(Rotation);
    float s = sin(Rotation);
    p = float2(c * p.x + s * p.y, -s * p.x + c * p.y);

    // Calculate SDF
    float r = max(Size, 0.001);
    float rf = max(InnerRadiusRatio, 0.001);
    float d = sdStar5(p, r, rf);

    // Anti-aliasing
    float aa = fwidth(d);
    
    // Fill Mask (d < 0 is inside the shape)
    float mask = 1.0 - smoothstep(0.0, aa, d);

    // Final color composite
    outColor = float4(Color.rgb, saturate(Color.a) * mask);
}
