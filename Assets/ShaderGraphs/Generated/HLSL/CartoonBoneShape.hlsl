#ifndef PI
#define PI 3.14159265359
#endif

// Helper: Rotate a 2D vector by an angle in radians
float2 rotate(float2 p, float angle) {
    float c = cos(angle);
    float s = sin(angle);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

// Helper: Signed Distance to a 2D segment
// p: point, a: start, b: end
float sdSegment(float2 p, float2 a, float2 b) {
    float2 pa = p - a;
    float2 ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}

// Helper: Smooth Minimum (polynomial) for organic blending
// a: dist1, b: dist2, k: smoothing factor
float smin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return lerp(b, a, h) - k * h * (1.0 - h);
}

// Helper: Signed Distance to a Circle
float sdCircle(float2 p, float r) {
    return length(p) - r;
}

// Main Function: Cartoon Bone Shape
// User Request: "a cartoon bone shape that I can adjust in size and thickness"
void CartoonBoneShape_float(float2 UV, float Length, float Thickness, float KnobSize, float2 Center, float Rotation, float4 Color, out float4 outColor) {
    // PLAN:
    // 1) Center and rotate UV coordinates.
    // 2) Apply absolute symmetry to work in the first quadrant (bones are symmetric X and Y).
    // 3) Create the shaft using a line segment on the X-axis.
    // 4) Create the knobs using a circle offset from the end of the shaft.
    // 5) Blend shaft and knobs using smooth minimum (smin) for the cartoon look.
    // 6) Apply smoothstep for anti-aliasing and output color.

    // 1) Coordinates
    float2 p = UV - Center;
    p = rotate(p, -Rotation); // Negative for standard CCW rotation behavior

    // 2) Symmetry
    // Reflect x and y to handle all 4 corners and both ends of the bone identical
    p = abs(p);

    // 3) Shaft SDF
    // Segment from center (0,0) to end (Length, 0)
    // We subtract Thickness to give it volume
    float dShaft = sdSegment(p, float2(0.0, 0.0), float2(Length, 0.0)) - Thickness;

    // 4) Knob SDF
    // Position the knob circle at the end of the shaft
    // Shift it slightly outward (Length) and upward (KnobSize * 0.8) for the heart-like end shape
    // The p.y reflection above handles both top and bottom knobs
    float2 knobPos = float2(Length, Thickness + KnobSize * 0.5);
    float dKnob = sdCircle(p - knobPos, KnobSize);

    // 5) Combine with Smooth Union
    // k = 0.05 gives a nice organic join between shaft and knobs
    float dist = smin(dShaft, dKnob, 0.05);

    // 6) Anti-aliasing and Output
    float aa = fwidth(dist);
    float mask = 1.0 - smoothstep(-aa, aa, dist);

    // Final color with alpha transparency
    outColor = float4(Color.rgb * mask, mask * Color.a);
}