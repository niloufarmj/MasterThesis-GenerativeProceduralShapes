#ifndef PI
#define PI 3.14159265359
#endif

// Distance to a line segment AB (Euclidean)
inline float sdSegment(float2 p, float2 a, float2 b)
{
    float2 pa = p - a;
    float2 ba = b - a;
    float h = saturate(dot(pa, ba) / max(dot(ba, ba), 1e-12));
    return length(pa - ba * h);
}

// Exact SDF for a filled convex triangle with CCW vertices.
// Returns negative inside, positive outside.
inline float sdTriangle(float2 p, float2 v0, float2 v1, float2 v2)
{
    float d2 = 1e20;
    float s = -1e20;

    float2 e0 = v1 - v0;
    float2 n0 = float2(e0.y, -e0.x);
    n0 = (dot(n0, n0) > 1e-12) ? normalize(n0) : float2(0.0, 0.0);
    s = max(s, dot(p - v0, n0));
    d2 = min(d2, sdSegment(p, v0, v1) * sdSegment(p, v0, v1));

    float2 e1 = v2 - v1;
    float2 n1 = float2(e1.y, -e1.x);
    n1 = (dot(n1, n1) > 1e-12) ? normalize(n1) : float2(0.0, 0.0);
    s = max(s, dot(p - v1, n1));
    d2 = min(d2, sdSegment(p, v1, v2) * sdSegment(p, v1, v2));

    float2 e2 = v0 - v2;
    float2 n2 = float2(e2.y, -e2.x);
    n2 = (dot(n2, n2) > 1e-12) ? normalize(n2) : float2(0.0, 0.0);
    s = max(s, dot(p - v2, n2));
    d2 = min(d2, sdSegment(p, v2, v0) * sdSegment(p, v2, v0));

    return (s > 0.0) ? sqrt(d2) : -sqrt(d2);
}

// 5-pointed star filled by default in yellow color, centered, with a clear inner radius
void Star5_float(float2 UV, float OuterRadius, float InnerRadius, float2 Center, float Rotation, float4 Color, out float4 outColor)
{
    // PLAN:
    // 1) Center UV and rotate the sampling point by -Rotation.
    // 2) Precompute 5 outer and 5 inner vertex positions in UV space.
    // 3) Form the star as the boolean union (min) of 5 convex triangles.
    //    Each triangle spans one outer tip and its two neighboring inner vertices.
    // 4) Evaluate exact SDF per triangle using segment distances and half-space tests.
    // 5) Apply fwidth anti-aliasing and output yellow fill with straight alpha.

    // 1) Recenter and rotate sampling point
    float2 p = UV - Center;
    float c = cos(Rotation);
    float s = sin(Rotation);
    float2 pr = float2(c * p.x + s * p.y, -s * p.x + c * p.y);

    // 2) Precompute star vertices in local UV units
    float2 outer[5];
    float2 inner[5];

    [unroll]
    for (int i = 0; i < 5; ++i)
    {
        float aOut = 0.5 * PI + (2.0 * PI * i) / 5.0;
        float aIn  = aOut + PI / 5.0;
        outer[i] = float2(cos(aOut), sin(aOut)) * max(OuterRadius, 0.0);
        inner[i] = float2(cos(aIn),  sin(aIn))  * max(InnerRadius, 0.0);
    }

    // 3) Union of 5 triangular spikes
    float d = 1e20;

    [unroll]
    for (int k = 0; k < 5; ++k)
    {
        int prev = (k + 4) % 5;
        d = min(d, sdTriangle(pr, inner[prev], outer[k], inner[k]));
    }

    // 4) Anti-alias
    float aa = fwidth(d);
    float mask = 1.0 - smoothstep(0.0, aa, d);

    // 5) Straight-alpha output
    outColor = float4(Color.rgb * mask, saturate(Color.a) * mask);
}