#ifndef PI
#define PI 3.14159265359
#endif

// SDF for upright equilateral triangle centered at origin, parameterized by circumradius r. d<0 inside.
float sdEquilateralTriangle_Centered(float2 p, float r)
{
    float k = 1.7320508; // sqrt(3)
    p.x = abs(p.x) - r;
    p.y = p.y + r / k;
    if (p.x + k * p.y > 0.0)
    {
        p = float2(p.x - k * p.y, -k * p.x - p.y) * 0.5;
    }
    p.x -= clamp(p.x, -2.0 * r, 0.0);
    return -length(p) * sign(p.y);
}

// User request: A filled equilateral triangle pointing upwards and centered on the screen with adjustable size and smooth edges.
void FunctionName_float(float2 UV, float Size, float4 Color, out float4 outColor)
{
    // PLAN:
    // 1) Center UV to (0.5,0.5) and scale by Size so 0.5 ≈ half screen.
    // 2) Use an upright equilateral triangle SDF (centered at origin, circumradius = 1).
    // 3) Multiply local coordinates by Size to scale the triangle proportionally.
    // 4) Apply smoothstep on the SDF for anti-aliased edges.
    // 5) Output a solid fill color with alpha = coverage mask.

    // 1) Center UV coordinates around (0.5, 0.5)
    float2 centered = UV - float2(0.5, 0.5);

    // 2) Scale space by Size to control visual size (0.5 ≈ half screen)
    float safeSize = max(Size, 1e-4);
    float2 p = centered / safeSize;

    // 3) Equilateral triangle SDF with circumradius 1 (upright, centered)
    float dist = sdEquilateralTriangle_Centered(p, 1.0);

    // 4) Anti-aliased edge using fixed-width smoothstep in SDF space
    float edge = smoothstep(0.01, -0.01, dist);

    // 5) Output fill color with smooth alpha mask
    float mask = edge;
    outColor = float4(Color.rgb * mask, mask);
}
