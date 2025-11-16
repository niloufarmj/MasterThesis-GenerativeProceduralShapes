void SquareShape_float(float2 UV, float Size, float4 Color, out float4 outColor) {
    // Center UV coordinates
    float2 centered = UV - float2(0.5, 0.5);
    // Normalize and scale by size
    centered /= Size;
    // SDF for square
    float2 d = abs(centered) - 1.0;
    float dist = length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
    // Anti-alias with smoothstep
    float edge = smoothstep(0.01, -0.01, dist);
    // Output color
    outColor = float4(Color.rgb * edge, edge);
}