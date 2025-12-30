#ifndef PI
#define PI 3.14159265359
#endif

// PLAN:
// 1) Center UVs to (0.5, 0.5) and convert to polar coordinates (r, ang).
// 2) Define the spiral field: phase = r * Turns - ang.
// 3) Calculate cyclic distance to the nearest integer in the phase field (distCyc).
// 4) Compute gradient magnitude of the field to normalize distance to Euclidean space (uniform thickness).
// 5) Apply smoothstep anti-aliasing based on Thickness and output final color.

void SpiralShape_float(float2 UV, float Turns, float Thickness, float4 Color, out float4 outColor)
{
    // 1) Center Coordinates
    float2 p = UV - 0.5;
    float r = length(p);
    // Angle normalized to [-0.5, 0.5]
    float ang = atan2(p.y, p.x) / (2.0 * PI);

    // 2) Spiral Field
    // The equation r * Turns = ang + k defines the spiral arms.
    // We compute the value relative to the nearest arm.
    float field = r * Turns - ang;

    // 3) Cyclic Distance
    // Calculate distance to the nearest integer value (the spiral line center)
    // Result is in range [0, 0.5]
    float f = frac(field);
    float distCyc = min(f, 1.0 - f);

    // 4) Gradient Correction
    // To keep the line thickness constant in screen space, we divide by the gradient magnitude.
    // Gradient squared = (d/dr)^2 + (1/r * d/dTheta)^2
    // d/dr(field) = Turns
    // d/dTheta(field) = -1/(2*PI)
    // We add a small epsilon to r to prevent division by zero at the center.
    float rSafe = max(r, 0.0001);
    float gradSq = Turns * Turns + 1.0 / (4.0 * PI * PI * rSafe * rSafe);
    float gradMag = sqrt(gradSq);

    // Approximate Euclidean distance to the spiral line
    float distEuclidean = distCyc / gradMag;

    // 5) Anti-aliasing and Masking
    // Determine pixel width in UV space for sharp yet smooth edges
    float aa = length(fwidth(p)) * 0.7;
    aa = max(aa, 0.0001);

    // Thickness is total width, so we compare against half width
    float halfWidth = max(Thickness, 0.0) * 0.5;
    
    // Generate smooth mask
    float mask = smoothstep(halfWidth + aa, halfWidth - aa, distEuclidean);

    // Output final color (premultiplied-alpha logic safe)
    outColor = float4(Color.rgb * mask, mask * Color.a);
}