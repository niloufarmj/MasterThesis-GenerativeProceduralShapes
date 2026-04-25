#ifndef PI
#define PI 3.14159265359
#endif

#ifndef SD_STAR5_HELPER
#define SD_STAR5_HELPER
inline float sdStar5(float2 p, float r, float rf)
{
    float2 k1 = float2(0.809016994375, -0.587785252292);
    float2 k2 = float2(-k1.x, k1.y);
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

void YellowStar5Point_float(
    float2 UV,
    float OuterRadius,
    float InnerRadius,
    float2 Center,
    float Rotation,
    float4 StarColor,
    out float4 outColor
)
{
    float2 p = UV - Center;

    float cosR = cos(Rotation);
    float sinR = sin(Rotation);
    p = float2(cosR * p.x + sinR * p.y, -sinR * p.x + cosR * p.y);

    float outerR = max(OuterRadius, 0.001);
    float innerR = clamp(InnerRadius, 0.001, outerR * 0.999);

    float d = sdStar5(p, outerR, innerR);

    float aa = fwidth(d);
    float mask = 1.0 - smoothstep(-aa * 0.5, aa * 0.5, d);

    outColor = float4(StarColor.rgb, StarColor.a * mask);
}