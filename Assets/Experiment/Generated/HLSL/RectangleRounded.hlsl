void RectangleRounded_float(float2 UV, float Width, float Height, float CornerRadius, float4 Color, out float4 outColor) {
    // PLAN:
    // 1) Center UV coordinates.
    // 2) Define half-size based on Width/Height.
    // 3) Clamp corner radius to valid range.
    // 4) Calculate Signed Distance Field (SDF) for rounded box.
    // 5) Apply smoothstep for anti-aliasing.
    // 6) Output color with alpha.

    float2 centered = UV - 0.5;
    float2 halfSize = float2(Width, Height) * 0.5;
    
    // Prevent artifacts by ensuring radius is not larger than the shape itself
    float r = clamp(CornerRadius, 0.0, min(halfSize.x, halfSize.y));
    
    // SDF Calculation for Rounded Box
    // Logic: Calculate distance to inner box, then subtract radius to round the corners
    float2 d = abs(centered) - (halfSize - r);
    float dist = length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - r;
    
    // Anti-aliasing mask (1.0 inside, 0.0 outside)
    // SDF is negative inside, so 0.01 to -0.01 transitions from 0 to 1 as we go inside
    float edge = smoothstep(0.01, -0.01, dist);
    
    // Final Color composition
    // Apply mask to both RGB (premultiplied-ish) and Alpha
    outColor = float4(Color.rgb * edge, Color.a * edge);
}