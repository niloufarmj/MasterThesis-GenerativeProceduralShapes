#ifndef PI
#define PI 3.14159265359
#endif

// SDF for an axis-aligned box
// p: point relative to center
// b: half-extents (width/2, height/2)
float sdBox(float2 p, float2 b) {
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

void PlusShape_float(float2 UV, float Length, float Thickness, float4 Color, out float4 outColor) {
    // User Request: A plus-shaped cross made from two rectangles.
    
    // PLAN:
    // 1) Center UV coordinates at (0.5, 0.5).
    // 2) Compute half-extents for the vertical and horizontal arms.
    // 3) Calculate SDF for both boxes.
    // 4) Combine SDFs using min() (Union).
    // 5) Apply anti-aliasing using fwidth.
    // 6) Output final color with alpha.

    float2 centered = UV - 0.5;

    // Convert total dimensions to half-extents
    // Vertical arm: width = Thickness, height = Length
    float2 sizeV = float2(Thickness, Length) * 0.5;
    
    // Horizontal arm: width = Length, height = Thickness
    float2 sizeH = float2(Length, Thickness) * 0.5;

    // Calculate signed distances
    float distV = sdBox(centered, sizeV);
    float distH = sdBox(centered, sizeH);

    // Union of the two shapes (min distance)
    // Negative distance is inside, so min() preserves the deepest interior
    float dist = min(distV, distH);

    // Anti-aliasing
    // Using derivatives for screen-space constant edge softness
    float aa = fwidth(dist);
    // Safety clamp for AA width to prevent aliasing if derivatives are tiny
    aa = max(aa, 0.001);

    // Smoothstep for alpha mask: 1.0 inside (negative dist), 0.0 outside (positive dist)
    float mask = smoothstep(aa, -aa, dist);

    // Apply color and mask to output
    outColor = float4(Color.rgb * mask, mask);
}