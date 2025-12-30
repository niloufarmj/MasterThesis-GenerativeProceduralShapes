#ifndef PI
#define PI 3.14159265359
#endif

// Helper for circle SDF
float sdCircle(float2 p, float r) {
    return length(p) - r;
}

// Main Function: Crescent Moon Shape
// A crescent moon created by subtracting an offset circle from a base circle.
void CrescentMoonShape_float(float2 UV, float Radius, float Thickness, float2 Center, float Rotation, float4 Color, out float4 outColor) {
    // PLAN:
    // 1) Center the UV coordinates relative to the shape center.
    // 2) Apply 2D rotation to the coordinates.
    // 3) Calculate SDF for the outer circle (the main body of the moon).
    // 4) Calculate SDF for the inner/cutting circle, shifted to the right by 'Thickness'.
    // 5) Combine SDFs using subtraction (max(outer, -inner)).
    // 6) Apply smoothstep anti-aliasing to the edge.
    // 7) Output final color with calculated alpha mask.

    // 1. Recenter UVs
    float2 p = UV - Center;

    // 2. Rotate sampling point
    float c = cos(Rotation);
    float s = sin(Rotation);
    p = float2(c * p.x + s * p.y, -s * p.x + c * p.y);

    // 3. Outer Circle SDF (The moon body)
    float dOuter = sdCircle(p, Radius);

    // 4. Inner Circle SDF (The cutter)
    // Shifting the cutter to the right (positive x) creates a crescent on the left.
    // The 'Thickness' parameter effectively controls the shift amount.
    // Thickness = 0 -> Circles coincide (Invisible)
    // Thickness = Radius -> Half moon (approx)
    // Thickness = 2*Radius -> Full circle (Touching at edge)
    float dInner = sdCircle(p - float2(Thickness, 0.0), Radius);

    // 5. Create Crescent: Outer AND NOT Inner
    // Use standard SDF subtraction: max(target, -cutter)
    float dist = max(dOuter, -dInner);

    // 6. Anti-aliased edge
    // fwidth gives the rate of change of the distance field per pixel
    float aa = fwidth(dist);
    // Clamp to a small minimum to ensure visibility even at low scales/zoom
    aa = max(aa, 0.001);
    
    // Compute alpha mask (0.0 outside, 1.0 inside)
    // dist < 0 inside the shape
    float mask = 1.0 - smoothstep(-aa, aa, dist);

    // 7. Final Output
    // Premultiplied alpha for clean blending
    outColor = float4(Color.rgb * mask, mask);
}