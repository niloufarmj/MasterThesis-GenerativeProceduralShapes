void DynamicSquareWithRoundedCorners_float(float2 UV, float Width, float CornerRadius, float3 Color, out float4 outColor) {
    // Center UV coordinates
    float2 centered = UV - 0.5;
    
    // Scale centered by width
    centered /= Width;
    
    // Rounded box SDF calculation
    float2 d = abs(centered) - 0.5;
    float dist = length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - CornerRadius;
    
    // Anti-aliased edge
    float edge = smoothstep(0.01, -0.01, dist);
    
    // Shape color incorporating edge for AA
    outColor = float4(Color * edge, edge);
}