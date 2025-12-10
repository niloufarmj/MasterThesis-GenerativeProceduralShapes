#ifndef PI
#define PI 3.14159265359
#endif

void DonutShape_float(float2 UV, float2 Center, float Radius, float Thickness, float4 Color, out float4 outColor) {
    // PLAN:
    // 1) Center the UV coordinates.
    // 2) Calculate the SDF for an annulus (donut 2D).
    //    Formula: abs(length(p) - Radius) - HalfThickness
    // 3) Use fwidth and smoothstep for analytic anti-aliasing.
    // 4) Output the final color with alpha.

    // 1. Center coordinates
    float2 p = UV - Center;

    // 2. SDF Calculation
    // Radius = distance from center to the middle of the ring
    // Thickness = total width of the solid ring
    float halfWidth = Thickness * 0.5;
    // Dist is negative inside the ring, positive outside
    float dist = abs(length(p) - Radius) - halfWidth;

    // 3. Anti-aliasing
    // Use fwidth for screen-space derivative to get sharp but smooth edges
    float delta = fwidth(dist);
    // Create alpha mask: 1.0 inside, 0.0 outside, interpolated at edge
    float alpha = 1.0 - smoothstep(-delta, delta, dist);

    // 4. Output
    // Premultiply RGB by alpha, and output alpha in alpha channel
    outColor = float4(Color.rgb * alpha, Color.a * alpha);
}