void TriangleShape_float(float2 UV, float Size, float3 Color, out float4 outColor) {
    // PLAN:
    // 1) Center UV coordinates
    float2 centered = UV - 0.5;
    // 2) Scale UV by Size
    centered *= Size * 2.0;
    // 3) Define triangle SDF
    const float k = sqrt(3.0);
    float dist = max(abs(centered.x) - 1.0, centered.y);
    float2 p1 = abs(centered) - float2(1.0, 1.0/k);
    if (centered.x + k*centered.y > 0.0) dist = length(max(p1,0.0)) + min(max(p1.x,p1.y),0.0);
    // 4) Anti-aliasing
    float edge = smoothstep(0.01, -0.01, dist);
    // 5) Output color
    outColor = float4(Color * edge, edge);
}