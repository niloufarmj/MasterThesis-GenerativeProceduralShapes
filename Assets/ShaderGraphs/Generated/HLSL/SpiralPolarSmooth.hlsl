#ifndef PI
#define PI 3.14159265359
#endif

// PLAN:
// 1) Center UV coordinates to (0,0).
// 2) Convert to polar coordinates (radius 'r', angle 'theta').
// 3) Compute spiral phase using theta and radius.
//    Formula: phase = theta * Arms - r * Twist + Rotation
// 4) Generate smooth sine wave pattern from the phase.
// 5) Calculate a radial mask for soft falloff at the edges.
// 6) Combine pattern, mask, and color for final output.

void SpiralPolarSmooth_float(float2 UV, float Twist, float Arms, float Rotation, float Size, float Falloff, float4 Color, out float4 outColor) {
    // 1) Center UVs
    float2 centered = UV - 0.5;

    // 2) Polar Coordinates
    float r = length(centered);
    float theta = atan2(centered.y, centered.x);

    // 3) Spiral Phase
    // 'Arms' determines how many spiral branches exist (e.g., 2 for a galaxy shape).
    // 'Twist' determines how tightly they wind as radius increases.
    // 'Rotation' spins the whole shape.
    float phase = (theta * Arms) - (r * Twist) + Rotation;

    // 4) Smooth Wave Pattern
    // cos(phase) oscillates between -1 and 1.
    // We remap it to 0..1 to create soft ribbons.
    float spiral = 0.5 + 0.5 * cos(phase);

    // 5) Radial Mask
    // We want the shape to be visible up to 'Size' and fade out by 'Falloff'.
    // smoothstep(inner, outer, x) is 0 when x < inner, 1 when x > outer.
    // We want the REVERSE: 1 at center, 0 at edge.
    // So we use: 1.0 - smoothstep(Size - Falloff, Size, r)
    float safeFalloff = max(Falloff, 0.001);
    float mask = 1.0 - smoothstep(max(0.0, Size - safeFalloff), Size, r);

    // 6) Final Composite
    // Combine the spiral pattern, the circular mask, and the input alpha.
    float finalAlpha = spiral * mask * Color.a;

    // Output premultiplied alpha (as requested by rules)
    outColor = float4(Color.rgb * finalAlpha, finalAlpha);
}