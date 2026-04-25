#ifndef PI
#define PI 3.14159265359
#endif

// User request: a 5-pointed star filled by default in yellow color, centered, with a clear inner radius

// Helper: perpendicular (right-hand)
inline float2 star_perpRight(float2 e)
{
    return float2(e.y, -e.x);
}

// Helper: distance from point p to segment [a,b]
inline float star_distToSegment(float2 p, float2 a, float2 b)
{
    float2 pa = p - a;
    float2 ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}

// SDF for a 5-pointed star
// outerRadius: tip-to-center distance
// innerRadius: inner notch distance from center
inline float sdStar5(float2 p, float outerRadius, float innerRadius)
{
    // Build the 10 vertices of the star polygon (alternating outer/inner tips)
    // Outer tips start at top (90 degrees), inner points are between them
    float2 verts[10];

    [unroll]
    for (int i = 0; i < 5; ++i)
    {
        // Outer vertex at angle = 90 + i*72 degrees
        float outerAng = 0.5 * PI + (2.0 * PI * i) / 5.0;
        verts[2 * i] = outerRadius * float2(cos(outerAng), sin(outerAng));

        // Inner vertex halfway between outer tips
        float innerAng = outerAng + PI / 5.0; // +36 degrees
        verts[2 * i + 1] = innerRadius * float2(cos(innerAng), sin(innerAng));
    }

    // Compute SDF using the 10-sided polygon
    float maxHalf = -1e9;
    float minEdge = 1e9;

    [unroll]
    for (int i = 0; i < 10; ++i)
    {
        int j = (i + 1) % 10;
        float2 a = verts[i];
        float2 b = verts[j];
        float2 e = b - a;
        float2 n = normalize(star_perpRight(e)); // outward normal (CCW)

        maxHalf = max(maxHalf, dot(p - a, n));
        minEdge = min(minEdge, star_distToSegment(p, a, b));
    }

    float sgn = (maxHalf <= 0.0) ? -1.0 : 1.0;
    return minEdge * sgn;
}

// Straight-alpha src over dst composite
inline float4 star_over(float4 src, float4 dst)
{
    float a = src.a + dst.a * (1.0 - src.a);
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-8);
    return float4(c, a);
}

void StarFivePointed_float(
    float2 UV,
    float OuterRadius,
    float InnerRadius,
    float AngleRad,
    float4 StarColor,
    out float4 outColor)
{
    // PLAN:
    // 1) Center UV to [-0.5, 0.5] around (0.5, 0.5).
    // 2) Rotate the sampling point by -AngleRad.
    // 3) Build 5-pointed star SDF using alternating outer/inner vertices.
    // 4) Anti-alias the edge using fwidth + smoothstep.
    // 5) Output star color with alpha mask.

    // Step 1: Center UV
    float2 centered = UV - float2(0.5, 0.5);

    // Step 2: Rotate sampling point by -angle so shape appears rotated by +angle
    float cosA = cos(AngleRad);
    float sinA = sin(AngleRad);
    float2 pr = float2(
        cosA * centered.x + sinA * centered.y,
        -sinA * centered.x + cosA * centered.y
    );

    // Step 3: Compute star SDF
    float outerR = max(OuterRadius, 0.001);
    float innerR = max(InnerRadius, 0.001);
    float d = sdStar5(pr, outerR, innerR);

    // Step 4: Anti-aliased edge
    float aa = fwidth(d);
    float mask = 1.0 - smoothstep(0.0, aa, d);

    // Step 5: Output
    outColor = float4(StarColor.rgb * mask, mask);
}