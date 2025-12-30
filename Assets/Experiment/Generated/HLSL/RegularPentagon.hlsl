#ifndef PI
#define PI 3.14159265359
#endif

// Signed distance to an origin-centered regular N-gon with circumradius r
// Based on polar coordinate wedge method (Inigo Quilez style)
float sdRegularNGon(float2 p, float r, float n)
{
    // Convert to polar
    float angle = atan2(p.y, p.x);
    float radius = length(p);

    // Sector half-angle
    float a = PI / n;

    // Wrap angle to one wedge [-a, a]
    float k = floor((angle + a) / (2.0 * a));
    float angleLocal = angle - k * 2.0 * a;

    // Distance from polygon edge in polar form
    float d = radius * cos(a) / cos(angleLocal) - r;
    return d;
}

void FunctionName_float(float2 UV, float Size, float Rotation, float4 Color, out float4 outColor)
{
    // USER REQUEST: A regular five-sided polygon centered on the screen with adjustable size and rotation.
    // PLAN:
    // 1) Remap UV to centered coords around (0.5,0.5).
    // 2) Normalize to -1..1 space so Size directly scales the polygon size.
    // 3) Apply rotation by -Rotation to the sampling point (shape appears rotated by +Rotation).
    // 4) Use sdRegularNGon with n = 5 to get SDF for a regular pentagon.
    // 5) Anti-alias edge with smoothstep and output color with alpha as coverage.

    // 1) Center UV coordinates (0.5,0.5 is screen center)
    float2 centered = UV - 0.5;

    // 2) Map to -1..1 for easier uniform sizing
    float2 p = centered * 2.0;

    // Apply overall size scaling (0.5 ~ half screen, etc.)
    float safeSize = max(Size, 1e-4);
    p /= safeSize;

    // 3) Rotate sampling point by -Rotation so shape appears rotated by +Rotation
    float c = cos(-Rotation);
    float s = sin(-Rotation);
    float2 pr = float2(c * p.x - s * p.y, s * p.x + c * p.y);

    // 4) Regular pentagon SDF (circumradius = 1 in this normalized space)
    float dist = sdRegularNGon(pr, 1.0, 5.0);

    // 5) Anti-aliased edge (fixed-width AA in SDF space)
    float edge = smoothstep(0.01, -0.01, dist);

    // Output with smooth alpha
    outColor = float4(Color.rgb * edge, edge);
}
