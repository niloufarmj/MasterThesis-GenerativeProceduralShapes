void StraightLine_float(float2 UV, float Thickness, float3 Color, out float4 outColor) {
    // PLAN:
    // 1) Center UV coordinates and adjust for Thickness
    // 2) Calculate distance from the Y-axis as our SDF
    // 3) Apply anti-aliasing with smoothstep and then set the output color

    // Centering and scaling UV coordinates around (0.5, 0.5)
    float2 centered = UV - float2(0.5, 0.5);
    centered.x /= Thickness;

    // SDF for vertical line (distance from Y-axis)
    float dist = abs(centered.x);

    // Anti-aliasing the edge
    float edge = smoothstep(Thickness, -Thickness, dist);

    // Calculate color
    outColor = float4(Color * edge, edge);
}