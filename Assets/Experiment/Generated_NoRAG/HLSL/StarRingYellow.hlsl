#ifndef PI
#define PI 3.14159265359
#endif

inline float sdCircle(float2 p, float r)
{
    return length(p) - r;
}

inline float opUnion(float d1, float d2)
{
    return min(d1, d2);
}

inline float opIntersection(float d1, float d2)
{
    return max(d1, d2);
}

inline float opSubtract(float d1, float d2)
{
    return max(d1, -d2);
}

inline float2 rotate2D(float2 p, float angle)
{
    float c = cos(angle);
    float s = sin(angle);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

inline float sdSegment(float2 p, float2 a, float2 b)
{
    float2 pa = p - a;
    float2 ba = b - a;
    float h = clamp(dot(pa, ba) / max(dot(ba, ba), 0.000001), 0.0, 1.0);
    return length(pa - ba * h);
}

inline float sdStarArmCapsule(float2 p, float outerRadius, float innerRadius, float armWidth)
{
    float2 a = float2(0.0, innerRadius);
    float2 b = float2(0.0, outerRadius);
    return sdSegment(p, a, b) - armWidth;
}

void StarRingYellow_float(float2 UV, float Size, float InnerRadius, float ArmWidth, float4 Color, out float4 outColor)
{
    // a 5-pointed star filled by default in yellow color, centered, with a clear inner radius
    // PLAN:
    // 1) Center UV around 0.5,0.5 so the shape is centered by default.
    // 2) Build one star arm from a segment capsule running from inner radius to outer radius.
    // 3) Rotate that arm 5 times and union them to form a 5-pointed star silhouette.
    // 4) Subtract a center circle to create a clear inner radius hole.
    // 5) Apply smoothstep anti-aliasing and output the requested color with alpha.

    float2 centered = UV - 0.5;

    float outerRadius = max(Size, 0.0001);
    float holeRadius = clamp(InnerRadius, 0.0, outerRadius * 0.9);
    float armHalfWidth = clamp(ArmWidth, 0.0001, outerRadius * 0.5);

    float2 local0 = centered;
    float2 local1 = rotate2D(centered, -2.0 * PI / 5.0);
    float2 local2 = rotate2D(centered, -4.0 * PI / 5.0);
    float2 local3 = rotate2D(centered, -6.0 * PI / 5.0);
    float2 local4 = rotate2D(centered, -8.0 * PI / 5.0);

    float d0 = sdStarArmCapsule(local0, outerRadius, holeRadius, armHalfWidth);
    float d1 = sdStarArmCapsule(local1, outerRadius, holeRadius, armHalfWidth);
    float d2 = sdStarArmCapsule(local2, outerRadius, holeRadius, armHalfWidth);
    float d3 = sdStarArmCapsule(local3, outerRadius, holeRadius, armHalfWidth);
    float d4 = sdStarArmCapsule(local4, outerRadius, holeRadius, armHalfWidth);

    float starDist = opUnion(opUnion(d0, d1), opUnion(opUnion(d2, d3), d4));

    float holeDist = sdCircle(centered, holeRadius);
    float finalDist = opSubtract(starDist, holeDist);

    float aa = max(fwidth(finalDist), 0.0001);
    float edge = 1.0 - smoothstep(0.0, aa, finalDist);

    outColor = float4(Color.rgb * edge, edge);
}