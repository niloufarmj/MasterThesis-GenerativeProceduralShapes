#ifndef PI
#define PI 3.14159265359
#endif

// Helper: Signed distance to a box
// p: point relative to center
// b: half-extents (width/2, height/2)
float sdBox(float2 p, float2 b)
{
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

void RectangleSimple_float(float2 UV, float Width, float Height, float4 Color, out float4 outColor)
{
    // PLAN:
    // 1) Center UV coordinates to (0.5, 0.5).
    // 2) Define half-size vector from Width and Height inputs.
    // 3) Calculate SDF using sdBox for the rectangle shape.
    // 4) Compute analytic anti-aliasing using fwidth.
    // 5) Output final color with mask applied to alpha.

    // 1. Center UV
    float2 centered = UV - 0.5;

    // 2. Scale (SDF box expects half-extents)
    float2 halfSize = float2(Width, Height) * 0.5;

    // 3. Calculate SDF
    float d = sdBox(centered, halfSize);

    // 4. Anti-Aliasing
    // fwidth gives the change in value across one pixel, perfect for SDF edges
    float aa = fwidth(d);
    // Clamp aa to a safe minimum to avoid glitches if fwidth is zero
    aa = max(aa, 1e-4);
    
    // Smoothstep creates the anti-aliased edge mask
    // d < 0 is inside, d > 0 is outside
    float mask = 1.0 - smoothstep(0.0, aa, d);

    // 5. Output
    // Apply mask to the alpha channel of the input color
    outColor = float4(Color.rgb, Color.a * mask);
}