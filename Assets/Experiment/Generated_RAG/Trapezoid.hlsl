#ifndef PI
#define PI 3.14159265359
#endif

// SDF for a trapezoid centered at origin
// r1 = half-width of bottom edge, r2 = half-width of top edge, he = half-height
float sdTrapezoid_Helper(float2 p, float r1, float r2, float he)
{
    float2 k1 = float2(r2, he);
    float2 k2 = float2(r2 - r1, 2.0 * he);
    p.x = abs(p.x);
    float2 ca = float2(p.x - min(p.x, (p.y < 0.0) ? r1 : r2), abs(p.y) - he);
    float2 cb = p - k1 + k2 * clamp(dot(k1 - p, k2) / dot(k2, k2), 0.0, 1.0);
    float s = (cb.x < 0.0 && ca.y < 0.0) ? -1.0 : 1.0;
    return s * sqrt(min(dot(ca, ca), dot(cb, cb)));
}

// Helper: Alpha Blending (Source Over Destination)
float4 blendTrap_Helper(float4 src, float4 dst)
{
    float a = src.a + dst.a * (1.0 - src.a);
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-8);
    return float4(c, a);
}

void Trapezoid_float(
    float2 UV,
    float BottomWidth,
    float TopWidth,
    float Height,
    float2 Center,
    float Rotation,
    float4 FillColor,
    float4 StrokeColor,
    float StrokeWidth,
    out float4 outColor
)
{
    // 1. Translate UV to center and apply rotation
    float2 p = UV - Center;
    float cosR = cos(Rotation);
    float sinR = sin(Rotation);
    p = float2(cosR * p.x + sinR * p.y, -sinR * p.x + cosR * p.y);

    // 2. Compute half extents
    float r1 = max(BottomWidth, 0.001) * 0.5; // half bottom width
    float r2 = max(TopWidth, 0.001) * 0.5;    // half top width
    float he = max(Height, 0.001) * 0.5;       // half height

    // 3. SDF evaluation
    float dist = sdTrapezoid_Helper(p, r1, r2, he);

    // 4. Anti-aliasing
    float aa = fwidth(dist);

    // Fill mask
    float fillMask = 1.0 - smoothstep(-aa * 0.5, aa * 0.5, dist);

    // Stroke mask
    float halfStroke = max(StrokeWidth, 0.0) * 0.5;
    float strokeDist = abs(dist) - halfStroke;
    float strokeMask = 1.0 - smoothstep(-aa * 0.5, aa * 0.5, strokeDist);

    // 5. Apply colors
    float4 fill = float4(FillColor.rgb, saturate(FillColor.a) * fillMask);
    float4 stroke = float4(StrokeColor.rgb, saturate(StrokeColor.a) * strokeMask);

    // 6. Composite stroke over fill
    outColor = blendTrap_Helper(stroke, fill);
}
