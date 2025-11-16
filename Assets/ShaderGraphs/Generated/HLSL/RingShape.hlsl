void RingShape_float(float2 UV, float InnerRadius, float OuterRadius, float3 Color, out float4 outColor) {
    // Center UV coordinates
    float2 centered = UV - 0.5;
    
    // Calculate SDF for the outer circle
    float distOuter = length(centered) - OuterRadius;
    
    // Calculate SDF for the inner circle
    float distInner = length(centered) - InnerRadius;
    
    // Combine SDFs using subtraction (inner cut-out)
    float ringSDF = max(-distInner, distOuter);
    
    // Anti-aliased edge calculation
    float edge = smoothstep(0.01, -0.01, ringSDF);
    
    // Output final color with masked regions
    outColor = float4(Color * edge, edge);
}