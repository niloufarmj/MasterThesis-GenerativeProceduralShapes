#ifndef PI
#define PI 3.14159265359
#endif

// PLAN:
// 1) Center UV coordinates to (0,0) range.
// 2) Convert to polar coordinates (radius 'r', angle 'theta').
// 3) Calculate spiral phase using Archimedean formula: Phase = r * Density - theta.
// 4) Generate smooth wave pattern using sine of the phase.
// 5) Create a radial mask to limit the shape to 'Size' with 'Falloff'.
// 6) Combine pattern and mask for final alpha.

void SpiralPolar_float(float2 UV, float Density, float Rotation, float Size, float Falloff, float4 Color, out float4 outColor) {
    // 1) Center UVs
    float2 centered = UV - 0.5;

    // 2) Polar Coordinates
    float r = length(centered);
    float theta = atan2(centered.y, centered.x);

    // 3) Spiral Phase Calculation
    // Archimedean spiral: r = a + b*theta -> constant separation distance
    // We invert this for the field: val = r * k - theta
    // Density controls the number of windings
    // Rotation adds an offset to the angle (spinning the spiral)
    float phase = (r * Density) - theta + Rotation;

    // 4) Smooth Wave Pattern
    // sin() gives -1 to 1. Remap to 0 to 1 for opacity.
    // This creates the "smooth falloff" of the spiral arms themselves.
    float spiralWave = 0.5 + 0.5 * sin(phase);

    // 5) Circular Boundary Mask
    // Limits the spiral to a circle of radius 'Size'.
    // Smoothly fades out over 'Falloff' distance.
    // smoothstep(outer, inner, x) creates a 1->0 gradient as x goes from inner->outer.
    float safeFalloff = max(Falloff, 0.001);
    float circleMask = smoothstep(Size, max(Size - safeFalloff, 0.0), r);

    // 6) Final Composite
    float finalAlpha = spiralWave * circleMask * Color.a;

    // Output
    outColor = float4(Color.rgb * finalAlpha, finalAlpha);
}