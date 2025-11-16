void RectangleShape_float(float2 UV, float Width, float Height, float4 Color, out float4 outColor) {
    // Center UV coordinates with respect to (0.5, 0.5)
    float2 centered = UV - float2(0.5, 0.5);
    
    // Scale centered coordinates according to Width and Height
    float2 size = float2(Width * 0.5, Height * 0.5);
    centered = centered / size;
    
    // Rectangle SDF
    float2 d = abs(centered) - 1.0;
    float dist = length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
    
    // Anti-aliased edge using smoothstep
    float edge = smoothstep(0.01, -0.01, dist);
    
    // Define output color with smoothed edge
    outColor = float4(Color.rgb * edge, edge);
}