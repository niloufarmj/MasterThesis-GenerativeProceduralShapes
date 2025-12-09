void TriangleShape_float(float2 UV, float Size, float4 Color, out float4 outColor) {
    // Plan:
    // 1) Center and scale the UV coordinates
    // 2) Calculate the SDF of an equilateral triangle
    // 3) Apply anti-aliasing
    // 4) Calculate the output color with the SDF and the input color

    // 1) Center UV coordinates
    float2 centered = UV - 0.5;

    // 2) Triangle SDF
    // Height of the equilateral triangle from its base to the tip
    float height = sqrt(0.75);
    float3 coords = float3(centered.x, centered.y - Size * height * 0.5 + Size / height, Size);
    float3 axis = float3(-0.8660254, 0.5, 0);
    float dist = dot(abs(coords), axis) - 1.0;

    // 3) Anti-aliased edge
    float edge = smoothstep(0.01, -0.01, dist);

    // 4) Output with smooth alpha
    outColor = float4(Color.rgb * edge, edge);
}