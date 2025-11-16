void DynamicCircle_float(float2 UV, float Radius, float3 Color, out float4 outColor) {
    // Center UV coordinates to middle of screen
    float2 centered = UV - float2(0.5, 0.5);
    
    // Calculate circle SDF
    float dist = length(centered) - Radius;
    
    // Anti-alias the edge of the circle
    float edge = smoothstep(0.01, -0.01, dist);
    
    // Set the output color with anti-aliased edge
    outColor = float4(Color * edge, 1.0);
}