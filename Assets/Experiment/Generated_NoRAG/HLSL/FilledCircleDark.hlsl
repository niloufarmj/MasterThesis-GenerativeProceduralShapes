void FilledCircle_float(float2 UV, float Size, float4 Color, out float4 outColor) {
    // PLAN:
    // 1) Center UV coordinates at (0.5, 0.5).
    // 2) Compute circle SDF: dist = length(centered) - Size.
    // 3) Anti-alias the edge with smoothstep.
    // 4) Multiply dark color by mask and output as straight alpha.

    // Center UV coordinates
    float2 centered = UV - 0.5;
    
    // Circle SDF: negative inside, positive outside
    float dist = length(centered) - Size;
    
    // Anti-aliased edge mask
    float mask = smoothstep(0.01, -0.01, dist);
    
    // Output with smooth alpha (straight alpha)
    outColor = float4(Color.rgb * mask, mask);
}