void MoonShape_float(float2 UV, float Radius, float Thickness, float3 Color, out float4 outColor) {
    // PLAN:
    // 1) Center UV coordinates
    // 2) Use two circle SDFs to form a crescent moon
    // 3) Use boolean operations to subtract one circle from the other
    // 4) Anti-alias the final shape
    // 5) Colorize and output the result
    
    // Center UV coordinates
    float2 centered = UV - 0.5;

    // Moon SDF creation using two circles
    float circle1 = length(centered) - Radius;
    float circle2 = length(centered - float2(Thickness, 0)) - Radius;

    // Constructing the crescent shape by subtracting one circle from the other
    float sdf = max(-circle1, circle2);

    // Anti-aliasing edge
    float edge = smoothstep(0.01, -0.01, sdf);

    // Final color output
    outColor = float4(Color * edge, edge);
}