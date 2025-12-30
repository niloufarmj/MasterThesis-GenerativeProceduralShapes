#ifndef PI
#define PI 3.14159265359
#endif

// Basic 2D rotation helper
float2 rotate2D(float2 p, float angle)
{
    float c = cos(angle);
    float s = sin(angle);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

// SDF for a regular hexagon centered at origin with circumradius = 1 (unit hexagon)
// Based on Inigo Quilez style polar-logic for regular polygons
float sdRegularHexagon(float2 p)
{
    // Transform to hexagonal coordinate system
    p = abs(p);
    float3 k = float3(-0.5, 0.86602540378, 0.0); // ( -1/2, sqrt(3)/2 )

    // Fold into a 60-degree wedge
    float2 q = float2(dot(float2(k.x, k.y), p), dot(float2(-k.y, k.x), p));

    // Hexagon SDF in this space (unit circumradius)
    // This form gives distance to a regular hexagon with circumradius 1
    q.x = abs(q.x);
    float h = clamp((-q.x + 1.0) / k.y, 0.0, 1.0);
    float2 a = float2(q.x - 1.0 + k.y * h, q.y - k.y * h);
    float2 b = float2(q.x - 1.0, q.y - k.y);
    float da = dot(a, a);
    float db = dot(b, b);
    float d = (q.y > k.y) ? sqrt(min(da, db)) : (q.x - 1.0);
    return d;
}

// PLAN:
// 1) Center UV to (0.5, 0.5) and scale by Size so Size controls visual radius.
// 2) Rotate the point by RotationRad around the center.
// 3) Compute SDF of a unit regular hexagon and scale distance by Size.
// 4) Use smoothstep for anti-aliasing and build a solid fill mask.
// 5) Output color with alpha using the mask for crisp edges.
// USER REQUEST: A regular hexagon centered on the screen with size and rotation controls, solid flat color and crisp edges.
void FunctionName_float(float2 UV, float Size, float RotationRad, float4 Color, out float4 outColor)
{
    // 1) Center UV coordinates and scale by Size
    float2 centered = UV - 0.5;

    // Avoid division by zero; clamp Size
    float safeSize = max(Size, 1e-4);

    // Normalize to a space where hexagon has circumradius = 1
    float2 p = centered / safeSize;

    // 2) Rotate the point by RotationRad (shape appears rotated)
    p = rotate2D(p, RotationRad);

    // 3) Hexagon SDF (unit hexagon, then scale distance back by Size)
    float distUnit = sdRegularHexagon(p);
    float dist = distUnit * safeSize;

    // 4) Anti-aliased edge using smoothstep
    float edge = smoothstep(0.01, -0.01, dist);

    // 5) Output flat color with alpha from mask
    outColor = float4(Color.rgb * edge, edge);
}
