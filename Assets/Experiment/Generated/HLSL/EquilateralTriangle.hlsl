#ifndef PI
#define PI 3.14159265359
#endif

// Helper: Signed Distance to Equilateral Triangle (Centered, Upright)
// p: coordinates, r: circumradius (size)
float sdEquilateralTriangle(float2 p, float r) {
    const float k = 1.7320508; // sqrt(3.0)
    p.x = abs(p.x) - r;
    p.y = p.y + r / k;
    if (p.x + k * p.y > 0.0)
        p = float2(p.x - k * p.y, -k * p.x - p.y) * 0.5;
    p.x -= clamp(p.x, -2.0 * r, 0.0);
    return -length(p) * sign(p.y);
}

void EquilateralTriangle_float(float2 UV, float Size, float4 Color, out float4 outColor) {
    // PLAN:
    // 1) User request: Filled equilateral triangle pointing upwards.
    // 2) Center UV coordinates (0.5, 0.5 becomes 0,0).
    // 3) Calculate SDF for equilateral triangle using Size as circumradius.
    // 4) Compute anti-aliasing mask using smoothstep and fwidth.
    // 5) Output Color with alpha transparency.

    float2 centered = UV - 0.5;
    
    // Calculate Signed Distance Field
    // Size corresponds to the circumradius of the triangle
    float d = sdEquilateralTriangle(centered, max(Size, 0.0));
    
    // Anti-aliasing using fwidth for screen-space consistency
    float aa = fwidth(d);
    // SDF is negative inside, so we mask where d < 0
    float edge = 1.0 - smoothstep(0.0, max(aa, 0.0001), d);
    
    // Output Straight Alpha (RGB, A * Mask)
    // Shader Graph Master Node usually handles blending
    outColor = float4(Color.rgb, Color.a * edge);
}