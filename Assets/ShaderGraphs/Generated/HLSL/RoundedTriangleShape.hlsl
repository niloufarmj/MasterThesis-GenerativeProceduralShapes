void RoundedTriangleShape_float(float2 UV, float Size, float RotationAngle, float EdgeSmooth, float3 Color, out float4 outColor) {
    // Center and rotate UV coordinates
    float2 centered = UV - 0.5;
    float c = cos(RotationAngle);
    float s = sin(RotationAngle);
    float2 rotated = float2(c * centered.x + s * centered.y, -s * centered.x + c * centered.y);

    // Scale by size
    rotated /= Size;

    // Triangle SDF
    const float k = sqrt(3.0);
    rotated.x = abs(rotated.x) - 1.0;
    rotated.y = rotated.y + 1.0/k;
    if(rotated.x + k * rotated.y > 0.0)
        rotated = float2(rotated.x - k * rotated.y, -k * rotated.x - rotated.y) * 0.5;
    rotated.x -= clamp(rotated.x, -2.0, 0.0);
    float dist = -length(rotated) * sign(rotated.y);

    // Anti-aliasing edge
    float edge = smoothstep(EdgeSmooth, -EdgeSmooth, dist);

    // Output with smooth alpha
    outColor = float4(Color * edge, edge);
}