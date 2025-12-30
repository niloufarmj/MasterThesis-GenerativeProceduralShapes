#ifndef PI
#define PI 3.14159265359
#endif

// Helper: perpendicular vector (right-hand)
inline float2 nm_perpRight(float2 e)
{
    return float2(e.y, -e.x);
}

// Helper: Distance from point p to segment ab
inline float nm_distPointToSegment(float2 p, float2 a, float2 b)
{
    float2 e = b - a;
    float ee = max(dot(e, e), 1e-12);
    float t = clamp(dot(p - a, e) / ee, 0.0, 1.0);
    float2 q = a + t * e;
    return length(p - q);
}

// Helper: Signed distance to regular hexagon
// Uses 6 segments to compute exact distance and sign
inline float nm_sdHexagon(float2 p, float r)
{
    // 6 CCW vertices, starting at 30 degrees
    float2 v[6];
    [unroll]
    for (int i = 0; i < 6; ++i)
    {
        float ang = PI / 6.0 + (PI / 3.0) * i;
        v[i] = r * float2(cos(ang), sin(ang));
    }

    float maxHalf = -1e9;
    float minEdge = 1e9;

    [unroll]
    for (int i = 0; i < 6; ++i)
    {
        int j = (i + 1) % 6;
        float2 a = v[i], b = v[j];
        float2 e = b - a;
        float2 n = normalize(nm_perpRight(e));

        maxHalf = max(maxHalf, dot(p - a, n));
        minEdge = min(minEdge, nm_distPointToSegment(p, a, b));
    }

    float sgn = (maxHalf <= 0.0) ? -1.0 : 1.0;
    return minEdge * sgn;
}

void HexagonShape_float(float2 UV, float Size, float Rotation, float4 Color, out float4 outColor) {
    // PLAN:
    // 1) Center the UV coordinates at (0.5, 0.5).
    // 2) Rotate the coordinate space by Rotation (radians).
    // 3) Calculate signed distance to hexagon using helper function.
    // 4) Apply smoothstep for anti-aliasing based on fwidth.
    // 5) Output final color with transparency.
    // User Request: A regular hexagon centered on screen with size, rotation, solid fill, and crisp edges.

    float2 centered = UV - 0.5;
    
    // Rotate sampling point by -Rotation to rotate shape by +Rotation
    float c = cos(Rotation);
    float s = sin(Rotation);
    float2 rotated = float2(c * centered.x + s * centered.y, -s * centered.x + c * centered.y);

    // Calculate SDF
    float dist = nm_sdHexagon(rotated, max(Size, 0.0001));

    // Anti-aliasing using derivatives for crisp edges
    float aa = max(fwidth(dist), 1e-4);
    float mask = 1.0 - smoothstep(-aa, aa, dist);

    // Output final color (premultiplied alpha logic)
    outColor = float4(Color.rgb * mask, mask);
}