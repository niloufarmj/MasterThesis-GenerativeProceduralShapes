#ifndef PI
#define PI 3.14159265359
#endif

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

void YellowStar5_float(
    float2 UV,
    float Radius,
    float InnerRadius,
    float2 Center,
    float Rotation,
    float4 FillColor,
    out float4 outColor
)
{
    // Recenter UV space
    float2 p = UV - Center;

    // Rotate coordinates
    float c = cos(Rotation);
    float s = sin(Rotation);
    p = float2(c * p.x + s * p.y, -s * p.x + c * p.y);

    // Calculate inner radius ratio
    float r = max(Radius, 0.0001);
    float ratio = clamp(InnerRadius / r, 0.01, 0.99);

    // Calculate Signed Distance
    float d = sdStar5(p, r, ratio);

    // Anti-Aliasing
    float aa = max(fwidth(d), 0.0001);
    float mask = 1.0 - smoothstep(0.0, aa, d);

    // Output final color
    outColor = float4(FillColor.rgb, saturate(FillColor.a) * mask);
}
