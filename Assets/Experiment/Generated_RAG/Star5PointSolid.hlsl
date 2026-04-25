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
    float2 ba = rf * float2(-k1.y, k1.x) - float2(0.0, 1.0);
    float h = clamp( dot(p,ba)/dot(ba,ba), 0.0, r );
    return length(p-ba*h) * sign(p.y*ba.x-p.x*ba.y);
}
#endif

void Star5PointSolid_float(
    float2 UV,
    float2 Center,
    float Radius,
    float InnerRadius,
    float4 FillColor,
    out float4 outColor
)
{
    float2 p = UV - Center;
    float d = sdStar5(p, max(Radius, 0.001), max(InnerRadius, 0.0));
    
    float aa = fwidth(d);
    float alpha = 1.0 - smoothstep(0.0, aa, d);
    
    outColor = float4(FillColor.rgb, saturate(FillColor.a) * alpha);
}
