// Request: A clean filled circle centered on the screen with smooth, sharp edges, resizeable radius and fill color.
// PLAN:
// 1) Center UV coordinates at (0.5, 0.5).
// 2) Calculate Signed Distance Field (SDF) for the circle: distance(p, center) - radius.
// 3) Use fwidth() to determine the screen-space derivative for pixel-perfect anti-aliasing.
// 4) Apply smoothstep based on the SDF and AA width to create a sharp yet smooth mask.
// 5) Output final color, modulating alpha by the calculated mask.

void CircleCenteredSmooth_float(float2 UV, float Radius, float4 Color, out float4 outColor) {
    // 1. Center UV coordinates (0.5, 0.5 is the origin)
    float2 p = UV - 0.5;

    // 2. Calculate SDF (Signed Distance Field)
    // Negative values are inside the circle, positive are outside
    float dist = length(p) - Radius;

    // 3. Compute Anti-Aliasing width
    // fwidth gives the rate of change of the distance field relative to screen pixels.
    // This ensures the edge looks sharp (approx 1-2 pixels wide) at any zoom level.
    float aa = fwidth(dist);
    // Safety max to prevent division by zero or weird artifacts in constant regions
    aa = max(aa, 0.0001);

    // 4. Calculate Alpha Mask
    // smoothstep from (aa/2) down to (-aa/2) creates a smooth transition centered at dist=0
    float mask = smoothstep(aa * 0.5, -aa * 0.5, dist);

    // 5. Final Output
    // Using straight alpha: RGB is preserved, Alpha is modulated by the shape mask.
    outColor = float4(Color.rgb, Color.a * mask);
}