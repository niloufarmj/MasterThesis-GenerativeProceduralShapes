#ifndef PI
#define PI 3.14159265359
#endif

// Simple 2D rotation helper
float2 rotate2D(float2 p, float angle)
{
    float c = cos(angle);
    float s = sin(angle);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

// Signed distance to a regular hexagon centered at origin using polar coords
// Negative inside, positive outside
float sdRegularHexagon(float2 p, float radius)
{
    // Inigo Quilez style hexagon SDF via projection onto 60-degree wedge
    const float k = 1.7320508075688772; // sqrt(3)

    p = abs(p);
    float dotkp = dot(p, float2(0.5, k * 0.5));
    if (dotkp > p.x)
    {
        p = float2(dotkp, (k * 0.5) * p.y);
    }
    p.x -= radius;
    p.y -= radius / k;
    return length(max(p, 0.0)) * sign(p.y);
}

void FunctionName_float(float2 UV, float Size, float Rotation, float4 Color, out float4 outColor)
{
    // PLAN:
    // 1) Center UV to get coordinates around (0,0) and scale by Size.
    // 2) Rotate the local position by Rotation (radians).
    // 3) Evaluate SDF of a regular hexagon with given radius.
    // 4) Use smoothstep-based anti-aliasing on the SDF.
    // 5) Output flat solid color with alpha = coverage mask.
    // USER REQUEST: A regular hexagon centered on the screen with controllable size and rotation, flat solid color and crisp edges.

    // 1) Center UV: UV range is [0,1], so subtract 0.5 to center at origin
    float2 centered = UV - 0.5;

    // Make size parameter control visual size: 0.5 ≈ half screen
    // Scale space so that radius = Size
    float radius = max(Size, 1e-4);
    float2 p = centered / radius;

    // 2) Rotate local coordinates by Rotation (radians)
    p = rotate2D(p, Rotation);

    // 3) Hexagon SDF in scaled space, then rescale distance back by radius
    float distLocal = sdRegularHexagon(p, 1.0);
    float dist = distLocal * radius;

    // 4) Anti-aliased edge using fixed-width transition in UV space
    float edge = smoothstep(0.01, -0.01, dist);

    // 5) Output flat color with smooth alpha mask
    outColor = float4(Color.rgb * edge, edge);
}
