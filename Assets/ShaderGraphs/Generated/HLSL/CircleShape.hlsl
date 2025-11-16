void CircleShape_float(float2 UV, float Size, float3 Color, out float4 outColor) {
    // Center UV coordinates
    float2 centered = UV - 0.5;
    
    // Circle SDF
    float dist = length(centered) - Size;
    
    // Anti-aliased edge
    float edge = smoothstep(0.01, -0.01, dist);
    
    // Output with smooth alpha
    outColor = float4(Color * edge, edge);
}