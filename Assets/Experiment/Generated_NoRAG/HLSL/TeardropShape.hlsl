#ifndef PI
#define PI 3.14159265359
#endif

// User request: a teardrop shape with a smooth round bottom and a tapering pointed top, filled by default with dark shade of colors

// Helper: circle SDF
inline float sdCircle(float2 p, float radius)
{
    return length(p) - radius;
}

// Helper: segment SDF
inline float sdSegment(float2 p, float2 a, float2 b)
{
    float2 pa = p - a;
    float2 ba = b - a;
    float h = saturate(dot(pa, ba) / dot(ba, ba));
    return length(pa - ba * h);
}

// Helper: smooth union (for blending)
inline float opSmoothUnion(float d1, float d2, float k)
{
    float h = saturate(0.5 + 0.5 * (d2 - d1) / k);
    return lerp(d2, d1, h) - k * h * (1.0 - h);
}

// Helper: triangle SDF (for the pointed top)
// p: sample point, a/b/c: triangle vertices
inline float sdTriangle(float2 p, float2 a, float2 b, float2 c)
{
    float2 e0 = b - a, e1 = c - b, e2 = a - c;
    float2 v0 = p - a, v1 = p - b, v2 = p - c;
    float2 pq0 = v0 - e0 * saturate(dot(v0, e0) / dot(e0, e0));
    float2 pq1 = v1 - e1 * saturate(dot(v1, e1) / dot(e1, e1));
    float2 pq2 = v2 - e2 * saturate(dot(v2, e2) / dot(e2, e2));
    float s = sign(e0.x * e2.y - e0.y * e2.x);
    float2 d2 = min(min(
        float2(dot(pq0, pq0), s * (v0.x * e0.y - v0.y * e0.x)),
        float2(dot(pq1, pq1), s * (v1.x * e1.y - v1.y * e1.x))),
        float2(dot(pq2, pq2), s * (v2.x * e2.y - v2.y * e2.x)));
    return -sqrt(d2.x) * sign(d2.y);
}

void TeardropShape_float(float2 UV, float Size, float4 Color, out float4 outColor)
{
    // PLAN:
    // 1) Center UV around (0.5, 0.5) and scale by Size.
    // 2) Build a circle SDF at the bottom (round part).
    // 3) Build a triangle SDF pointing upward (tapered top).
    // 4) Combine them with smooth union to form the teardrop.
    // 5) Anti-alias with smoothstep and output Color.

    // 1) Remap UV to centered, scaled coordinates
    float2 centered = (UV - float2(0.5, 0.5));
    // Scale so Size controls overall extent; aspect-correct
    float2 p = centered / max(Size, 0.001);

    // 2) The teardrop: round bottom (circle) + tapering pointed top (triangle)
    // Place circle at bottom (negative y in local space = screen bottom)
    float circleRadius = 0.5;
    // Circle center slightly below origin
    float2 circleCenter = float2(0.0, 0.18);
    float dCircle = sdCircle(p - circleCenter, circleRadius);

    // 3) Triangle for the pointed top portion
    // Wide base at same height as circle center-ish, narrows to a point above
    float baseY = 0.18;    // matches circle center y
    float baseHalfW = 0.38; // width at base of triangle
    float tipY = -0.72;    // pointed top (negative y = up in UV coords)

    float2 triA = float2(-baseHalfW, baseY);
    float2 triB = float2( baseHalfW, baseY);
    float2 triC = float2(0.0, tipY);
    float dTriangle = sdTriangle(p, triA, triB, triC);

    // 4) Combine with smooth union for seamless blending
    float blendK = 0.28;
    float dist = opSmoothUnion(dCircle, dTriangle, blendK);

    // 5) Anti-aliased edge mask
    float aa = fwidth(dist);
    float edge = smoothstep(aa, -aa, dist);

    // Output
    outColor = float4(Color.rgb * edge, edge);
}