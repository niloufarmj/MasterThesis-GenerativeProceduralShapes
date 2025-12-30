#ifndef PI
#define PI 3.14159265359
#endif

// Simple SDF for a circle centered at origin
float sdCircle(float2 p, float radius)
{
    return length(p) - radius;
}

// Approximate signed distance to an ellipse using circle SDF with non-uniform scaling
float sdEllipseFromCircle(float2 p, float2 radii)
{
    // Avoid division by zero
    float2 invR = float2(1.0 / max(radii.x, 1e-6), 1.0 / max(radii.y, 1e-6));
    float2 scaled = p * invR;
    float distCircle = sdCircle(scaled, 1.0);
    // Rescale distance back roughly by average radius (simple approximation)
    float avgR = 0.5 * (radii.x + radii.y);
    return distCircle * avgR;
}

void FunctionName_float(
    float2 UV,
    float RadiusX,
    float RadiusY,
    float Morph,
    float4 Color,
    out float4 outColor)
{
    // USER REQUEST: An ellipse centered on the screen with adjustable horizontal and vertical radius, smoothly morphing between a circle and a stretched shape, single solid fill color.

    // PLAN:
    // 1) Center UV around (0.5, 0.5) to get local coordinates.
    // 2) Build a base radius from RadiusX/RadiusY so Morph = 0 is a pure circle.
    // 3) Lerp between circle radii (both = base) and separate ellipse radii (RadiusX, RadiusY) using Morph.
    // 4) Compute signed distance using an ellipse SDF built from a scaled circle SDF.
    // 5) Use smoothstep for anti-aliased edge and output solid color with alpha mask.

    // 1) Center UV coordinates (0.5,0.5) = screen center
    float2 centered = UV - 0.5;

    // 2) Base radius = average of provided radii (so Morph=0 forms a circle)
    float baseRadius = 0.5 * (RadiusX + RadiusY);

    // 3) Interpolate radii between circle and ellipse
    float2 circleRadii = float2(baseRadius, baseRadius);
    float2 targetRadii = float2(RadiusX, RadiusY);
    float t = saturate(Morph);
    float2 radii = lerp(circleRadii, targetRadii, t);

    // 4) Signed distance field for ellipse via scaled circle SDF
    float dist = sdEllipseFromCircle(centered, radii);

    // 5) Anti-aliased edge and output color
    float edge = smoothstep(0.01, -0.01, dist);
    float mask = edge;
    outColor = float4(Color.rgb * mask, mask);
}
