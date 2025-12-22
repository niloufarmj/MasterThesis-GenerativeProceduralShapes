#ifndef PI
#define PI 3.14159265359
#endif

// Helper: Signed Distance Function for a Rhombus (Diamond)
// p: Point coordinate relative to center
// b: Half-diagonals (half-width, half-height)
float sdRhombus(float2 p, float2 b) {
    p = abs(p);
    // Calculate intersection with the edge line
    float h = clamp(dot(b - 2.0 * p, b) / dot(b, b), -1.0, 1.0);
    // Euclidean distance to the edge
    float d = length(p - 0.5 * b * float2(1.0 - h, 1.0 + h));
    // Sign determination (negative inside)
    return d * sign(p.x * b.y + p.y * b.x - b.x * b.y);
}

void DiamondShape_float(float2 UV, float Width, float Height, float Rotation, float4 Color, out float4 outColor) {
    // PLAN:
    // 1) Center UV coordinates (0.5, 0.5 becomes 0,0).
    // 2) Rotate the coordinates by the Rotation angle.
    // 3) Calculate Signed Distance Field (SDF) for a rhombus using Width/Height.
    // 4) Apply smoothstep for anti-aliasing.
    // 5) Output final color.

    // 1. Center UV
    float2 p = UV - 0.5;

    // 2. Rotate
    // We rotate the sampling point in the opposite direction (-Rotation)
    // to make the shape appear rotated by +Rotation.
    float c = cos(Rotation);
    float s = sin(Rotation);
    p = float2(c * p.x + s * p.y, -s * p.x + c * p.y);

    // 3. SDF Calculation
    // Width and Height correspond to total diagonal lengths.
    // The SDF function expects half-extents.
    float2 halfSize = float2(Width, Height) * 0.5;
    
    // Safety: Prevent division by zero in SDF if size is 0
    halfSize = max(halfSize, 0.001);

    float dist = sdRhombus(p, halfSize);

    // 4. Anti-aliasing
    // Smoothstep creates a soft edge around 0.0 distance
    float edge = smoothstep(0.01, -0.01, dist);

    // 5. Output
    // Color * Alpha for premultiplied-like blending logic (or just masking)
    // Using edge as alpha mask
    outColor = float4(Color.rgb * edge, edge);
}