#ifndef PI
#define PI 3.14159265359
#endif

float dot2_SimpleHeart(float2 v) {
    return dot(v, v);
}

float sdSimpleHeart(float2 p) {
    p.x = abs(p.x);
    if (p.y + p.x > 1.0) {
        return sqrt(dot2_SimpleHeart(p - float2(0.25, 0.75))) - 0.35355339;
    }
    return sqrt(min(dot2_SimpleHeart(p - float2(0.00, 1.00)), dot2_SimpleHeart(p - 0.5 * max(p.x + p.y, 0.0)))) * sign(p.x - p.y);
}

float4 over_SimpleHeart(float4 src, float4 dst) {
    float a = src.a + dst.a * (1.0 - src.a);
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-8);
    return float4(c, a);
}

void SimpleHeartShape_float(
    float2 UV,
    float2 Center,
    float Size,
    float Rotation,
    float4 Color,
    float4 StrokeColor,
    float StrokeWidth,
    out float4 outColor
) {
    float2 p = UV - Center;
    
    float cosR = cos(Rotation);
    float sinR = sin(Rotation);
    p = float2(cosR * p.x + sinR * p.y, -sinR * p.x + cosR * p.y);
    
    float validSize = max(Size, 1e-5);
    p /= validSize;
    
    p.y += 0.5;
    
    float d_unit = sdSimpleHeart(p);
    float d = d_unit * validSize;
    
    float aa = max(fwidth(d), 0.001);
    
    float fillAlpha = 1.0 - smoothstep(-aa, aa, d);
    float4 fillLayer = float4(Color.rgb, Color.a * fillAlpha);
    
    float halfStroke = max(StrokeWidth, 0.0) * 0.5;
    float strokeDist = abs(d) - halfStroke;
    float strokeAlpha = 1.0 - smoothstep(-aa, aa, strokeDist);
    float4 strokeLayer = float4(StrokeColor.rgb, StrokeColor.a * strokeAlpha);
    
    outColor = over_SimpleHeart(strokeLayer, fillLayer);
}