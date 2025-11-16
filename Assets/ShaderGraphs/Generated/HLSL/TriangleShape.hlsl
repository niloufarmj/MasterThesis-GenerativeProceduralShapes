void TriangleShape_float(float2 UV, float Size, float4 Color, out float4 outColor) {
    // PLAN:
    // 1) Center UV coordinates
    // 2) Scale by size
    // 3) Calculate SDF for equilateral triangle
    // 4) Anti-alias with smoothstep
    // 5) Set formatted color output

    // Center and scale UV coordinates
    float2 centered = (UV - 0.5) * 2.0;
    centered /= Size;

    // Triangle SDF (normalized to Size)
    float k = 1.73205080757; // sqrt(3.0)
    centered.x = abs(centered.x) - 0.5;
    centered.y += 0.25 * k;
    float dist = max(centered.x, centered.y);
    if (centered.x + k * centered.y < 0.0) dist = length(centered);

    // Anti-alias
    float edge = smoothstep(0.01, -0.01, dist);

    // Output with smooth alpha
    outColor = float4(Color.rgb * edge, edge);
}