#ifndef PI
#define PI 3.14159265359
#endif

// Signed distance for a circle centered at origin with radius r
float sdCircle(float2 p, float r)
{
    return length(p) - r;
}

// Signed distance for an axis-aligned ellipse using normalized circle method
float sdEllipseNorm(float2 p, float2 radii)
{
    // Avoid division by zero by clamping radii
    float2 safeR = float2(max(radii.x, 1e-5), max(radii.y, 1e-5));
    // Normalize point by radii so ellipse becomes a unit circle
    float2 q = p / safeR;
    // Circle SDF in normalized space, then scale back by average radius
    float dCircle = sdCircle(q, 1.0);
    float avgR = 0.5 * (safeR.x + safeR.y);
    return dCircle * avgR;
}

void FunctionName_float(
    float2 UV,
    float2 Radii,
    float Morph,
    float4 Color,
    out float4 outColor)
{
    // PLAN:
    // 1) Center UV to [-0.5,0.5] space around screen center.
    // 2) Build a circle SDF with radius = average of Radii.
    // 3) Build an ellipse SDF using independent Radii.x and Radii.y.
    // 4) Lerp between circle and ellipse SDFs using Morph to smoothly morph shape.
    // 5) Apply smoothstep for anti-aliasing and output solid color with alpha from mask.

    // User request: An ellipse centered on the screen that smoothly morphs between a circle and a stretched shape with a solid fill color.

    // 1) Center UV
    float2 centered = UV - 0.5;

    // Ensure radii are non-negative
    float2 r = float2(max(Radii.x, 0.0), max(Radii.y, 0.0));

    // 2) Circle SDF using average radius so circle matches area roughly
    float avgRadius = 0.5 * (r.x + r.y);
    float distCircle = sdCircle(centered, avgRadius);

    // 3) Ellipse SDF with separate radii
    float distEllipse = sdEllipseNorm(centered, r);

    // 4) Morph between circle (Morph=0) and ellipse (Morph=1)
    float t = saturate(Morph);
    float dist = lerp(distCircle, distEllipse, t);

    // 5) Anti-aliased edge using fixed AA width
    float edge = smoothstep(0.01, -0.01, dist);

    // Final color with alpha = coverage
    outColor = float4(Color.rgb * edge, edge);
}
