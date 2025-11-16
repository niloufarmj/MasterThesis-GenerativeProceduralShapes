void StarShape_float(float2 UV, float Radius, float4 Color, out float4 outColor) {
    // Center UV coordinates and scale
    float2 centered = (UV - 0.5) * 2.0;
    float angle = atan2(centered.y, centered.x) + 3.14159;
    float r = length(centered);
    // 5-point star shape calculation using sine wave modulation
    float n = 5.0; // Number of star points
    float starInnerRadius = 0.4; // Inner radius ratio
    float density = 0.5; // Controls the sharpness of corners
    // Modulate radius with sine waves (5 waves for 5 points)
    float starRadius = (sin(n * angle) + 1.0) / 2.0 * (starInnerRadius - 1.0) + 1.0;
    // Star's SDF
    float dist = (r / Radius - starRadius) * density;
    // Anti-aliasing using smoothstep
    float edge = smoothstep(0.01, -0.01, dist);
    // Set output color with transparency
    outColor = float4(Color.rgb * edge, edge);
}