void CrescentMoonShape_float(float2 UV, float Radius, float Offset, float3 Color, out float4 outColor) {
    // PLAN:
    // 1) Center UV coordinates
    float2 centered = UV - 0.5;
    // 2) Apply scalar to resize the feature
    centered /= Radius;
    // 3) Outer circle SDF
    float outer = length(centered) - 0.5;
    // 4) Inner circle SDF
    float inner = length(centered - float2(0.5, 0) * Offset) - 0.4;
    // 5) Crescent moon shape using subtraction
    float crescent = max(outer, -inner);
    // 6) Anti-alias the edge
    float edge = smoothstep(0.01, -0.01, crescent);
    // 7) Output color
    outColor = float4(Color * edge, 1.0);
}