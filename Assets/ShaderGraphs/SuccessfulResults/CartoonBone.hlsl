#ifndef PI
#define PI 3.14159265359
#endif

// Helper: 2D Rotation
float2 rot2D(float2 p, float angle) {
    float c = cos(angle);
    float s = sin(angle);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

// Helper: Signed Distance to Segment
float sdSegment(float2 p, float2 a, float2 b) {
    float2 pa = p - a;
    float2 ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}

// Helper: Smooth Min (Polynomial) for organic joining
float smin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return lerp(b, a, h) - k * h * (1.0 - h);
}

// Main Function: Cartoon Bone Shape
// User Request: a cartoon bone shape that I can adjust in size and thickness
void CartoonBone_float(float2 UV, float Length, float Thickness, float KnobSize, float KnobOffset, float2 Center, float Rotation, float4 Color, out float4 outColor) {
    // PLAN:
    // 1) Translate UVs to centered coordinates.
    // 2) Rotate coordinates.
    // 3) Apply 4-way symmetry (abs(p)) to model one quadrant (top-right).
    // 4) Define Shaft as a horizontal segment on X-axis.
    // 5) Define Knob as a circle offset vertically from the shaft end.
    // 6) Smoothly blend Shaft and Knob to form the bone.
    // 7) Apply anti-aliasing and coloring.

    // 1) Centering
    float2 p = UV - Center;

    // 2) Rotation
    p = rot2D(p, -Rotation); // -Rotation for intuitive CCW spin

    // 3) Symmetry: Reflect X and Y
    // This folds the 4 quadrants into the top-right quadrant (+X, +Y)
    // This ensures we get a knob at Top-Right, Top-Left, Bottom-Right, Bottom-Left automatically.
    float2 q = abs(p);

    // 4) Shaft SDF
    // Segment from center (0,0) to (Length, 0).
    // Subtract Thickness to give it width.
    float dShaft = sdSegment(q, float2(0.0, 0.0), float2(Length, 0.0)) - Thickness;

    // 5) Knob SDF
    // We place a circle at x=Length.
    // y=KnobOffset moves it up/down relative to shaft center.
    // Because we used abs(p.y), this single circle mirrors to create the "heart-like" end of the bone.
    float2 knobPos = float2(Length, KnobOffset);
    float dKnob = length(q - knobPos) - KnobSize;

    // 6) Blend
    // k = 0.05 provides a cartilage-like smooth transition between shaft and knobs
    float dist = smin(dShaft, dKnob, 0.05);

    // 7) Output
    // Smoothstep for crisp but anti-aliased edges
    float edge = smoothstep(0.01, -0.01, dist);
    
    // Final composite (Color * alpha, alpha)
    outColor = float4(Color.rgb * edge, edge * Color.a);
}

// ------------------------------------------------------------------------
//  Visual Result (High-level, parameter-invariant description)
// ------------------------------------------------------------------------
//  This function generates a **stylized 2D cartoon bone-like primitive**
//  using Signed Distance Functions (SDFs).
//
//  The shape consists of a straight central shaft with rounded, bulb-like
//  ends on both sides, forming a classic bone silhouette. The overall
//  length, shaft thickness, end-knob size, end offset, rotation,
//  placement, and color are fully controlled by input parameters and are
//  not fixed by the function itself.
//
//  The output is an anti-aliased RGBA color suitable for playful icons,
//  game UI elements, decorative symbols, and expressive procedural
//  2D graphics.
// ------------------------------------------------------------------------
