void CircleShape_float(float2 UV, float Radius, float4 Color, out float4 outColor) {
    // Center UV coordinates
    float2 centered = UV - 0.5;
    
    // Circle SDF
    float dist = length(centered) - Radius;
    
    // Anti-aliasing edge
    float edge = smoothstep(0.01, -0.01, dist);
    
    // Output with smooth alpha
    outColor = float4(Color.rgb * edge, edge);
}