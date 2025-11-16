void PlusShape_float(float2 UV, float Size, float3 Color, out float4 outColor) {
    // PLAN:
    // 1) Remap UV to centered coordinates and scale by Size.
    // 2) Create vertical and horizontal bar shapes using SDF box.
    // 3) Combine bars to form a plus shape.
    // 4) Apply smoothstep for anti-aliasing and set output color.

    float2 centered = UV - 0.5;
    float barWidth = Size * 0.2;

    // Vertical and horizontal bars
    float2 verticalBar = abs(centered) - float2(barWidth, Size);
    float verticalDist = length(max(verticalBar, 0.0)) + min(max(verticalBar.x, verticalBar.y), 0.0);
    float2 horizontalBar = abs(centered) - float2(Size, barWidth);
    float horizontalDist = length(max(horizontalBar, 0.0)) + min(max(horizontalBar.x, horizontalBar.y), 0.0);

    // Combine bars to form plus shape
    float dist = min(verticalDist, horizontalDist);
    float edge = smoothstep(0.01, -0.01, dist);
    outColor = float4(Color * edge, edge);
}