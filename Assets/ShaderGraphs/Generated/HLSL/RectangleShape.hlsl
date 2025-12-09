void RectangleShape_float(float2 UV, float Width, float Height, float4 Color, out float4 outColor) {
    // Center and scale the UV coordinates
    float2 centered = UV - 0.5;
    centered.x *= Width;
    centered.y *= Height;

    // Rectangle SDF (axis-aligned, centered at origin)
    float2 halfSize = float2(Width, Height) * 0.5;
    float2 dist = abs(centered) - halfSize;
    float rectSDF = length(max(dist, 0.0)) + min(max(dist.x, dist.y), 0.0);

    // Anti-aliasing edge
    float edge = smoothstep(0.01, -0.01, rectSDF);

    // Calculate color and alpha based on edge
    outColor = float4(Color.rgb * edge, edge);
}