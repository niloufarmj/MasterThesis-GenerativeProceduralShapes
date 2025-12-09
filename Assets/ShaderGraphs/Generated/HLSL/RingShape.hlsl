void RingShape_float(float2 UV, float InnerRadius, float OuterRadius, float4 Color, out float4 outColor) {
    // Normalize and center UV coordinates
    float2 centered = UV - float2(0.5, 0.5);
    
    // Calculate distance from center
    float dist = length(centered);
    
    // Create ring using two circle SDFs
    float innerDist = dist - InnerRadius;
    float outerDist = OuterRadius - dist;
    float ringDist = max(innerDist, -outerDist);
    
    // Apply smoothstep for anti-aliasing at the edges of the ring
    float edge = smoothstep(0.01, -0.01, ringDist);
    
    // Set the output color
    outColor = float4(Color.rgb * edge, edge);
}