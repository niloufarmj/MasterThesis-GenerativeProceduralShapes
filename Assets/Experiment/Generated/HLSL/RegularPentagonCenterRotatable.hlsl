#ifndef PI
#define PI 3.14159265359
#endif

// Exact user request: A regular five-sided polygon centered on the screen. The overall size should be adjustable. Rotation should be controllable. The shape should stay symmetric and clean.

// Signed distance to an origin-centered **upright** regular pentagon (circumradius = r)
float sdRegularPentagon(float2 p, float r)
{
    // Precompute 5 vertices in CCW order, starting at the top (angle = PI/2)
    float2 v[5];
    [unroll]
    for (int i = 0; i < 5; ++i)
    {
        float ang = 0.5 * PI + (2.0 * PI * (float)i) / 5.0;
        float ca = cos(ang);
        float sa = sin(ang);
        v[i] = r * float2(ca, sa);
    }

    float maxHalfSpace = -1e9; // tracks max signed distance to edge lines
    float minEdgeDist = 1e9;   // tracks min unsigned distance to edge segments

    [unroll]
    for (int i = 0; i < 5; ++i)
    {
        int j = (i + 1) % 5;
        float2 a = v[i];
        float2 b = v[j];
        float2 e = b - a;

        // Outward normal for CCW polygon: right-hand perpendicular
        float2 n = normalize(float2(e.y, -e.x));

        // Signed distance to infinite line (positive = outside)
        float halfSpace = dot(p - a, n);
        maxHalfSpace = max(maxHalfSpace, halfSpace);

        // Distance to edge segment
        float2 pa = p - a;
        float ee = max(dot(e, e), 1e-8);
        float t = clamp(dot(pa, e) / ee, 0.0, 1.0);
        float2 q = a + t * e;
        float edgeDist = length(p - q);
        minEdgeDist = min(minEdgeDist, edgeDist);
    }

    // Inside if all half-spaces <= 0
    float signVal = (maxHalfSpace <= 0.0) ? -1.0 : 1.0;
    return minEdgeDist * signVal; // negative inside, positive outside
}

void FunctionName_float(float2 UV, float Size, float Rotation, float4 Color, out float4 outColor)
{
    // PLAN:
    // 1) Center UV to [-0.5,0.5] around (0.5,0.5) and scale by Size.
    // 2) Apply 2D rotation by -Rotation so the pentagon appears rotated by +Rotation.
    // 3) Evaluate a regular pentagon SDF with circumradius = 1.0 in this local space.
    // 4) Use smoothstep on the SDF for a clean anti-aliased edge.
    // 5) Output Color.rgb multiplied by the mask with alpha = mask.

    // 1) Center UV coordinates around screen center
    float2 centered = UV - 0.5;

    // Guard Size to avoid division by zero, then map Size so 0.5 ~ half-screen
    float safeSize = max(Size, 1e-4);
    float scale = safeSize * 2.0; // empirical mapping: 0.5 → pretty large, but within view
    float2 p = centered / scale;

    // 2) Apply rotation (rotate point by -Rotation to rotate shape by +Rotation)
    float c = cos(Rotation);
    float s = sin(Rotation);
    float2 pr = float2(c * p.x + s * p.y,
                       -s * p.x + c * p.y);

    // 3) Regular pentagon SDF with radius = 0.5 (fits nicely in unit square after scaling)
    float radius = 0.5;
    float dist = sdRegularPentagon(pr, radius);

    // 4) Anti-aliased edge using a small fixed width in SDF space
    float edge = smoothstep(0.01, -0.01, dist);

    // 5) Final color with alpha = coverage mask
    outColor = float4(Color.rgb * edge, edge);
}
