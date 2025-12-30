void CircleFilled_float(float2 UV, float Radius, float4 Color, out float4 outColor) {
    // PLAN:
    // 1) Center UV coordinates at (0.5, 0.5).
    // 2) Compute Circle SDF: distance from center minus radius.
    // 3) Compute anti-aliasing factor using fwidth for sharp edges.
    // 4) Output final color with mask applied to alpha.

    float2 centered = UV - 0.5;
    
    // Signed distance: negative inside, positive outside
    float dist = length(centered) - Radius;
    
    // Analytic anti-aliasing width (approx 1 pixel)
    float aa = fwidth(dist);
    
    // Calculate opacity mask (1.0 inside, 0.0 outside)
    // smoothstep creates a smooth transition at the edge
    float mask = 1.0 - smoothstep(0.0, aa, dist);
    
    // Output color (Straight Alpha)
    // RGB is preserved, Alpha is masked
    outColor = float4(Color.rgb, Color.a * mask);
}