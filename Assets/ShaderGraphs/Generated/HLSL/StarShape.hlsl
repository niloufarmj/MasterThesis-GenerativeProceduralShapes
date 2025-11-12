float starSDF(float2 p, float size) {
    float angle = atan2(p.y, p.x);
    float radius = size * 0.5 * (1.0 + 0.4 * cos(5.0 * angle));
    return length(p) - radius;
}

void StarShape_float(float2 UV, float size, float3 baseColor, out float4 outColor) {
    float2 p = UV - 0.5;
    float sd = starSDF(p, size);
    float aa = max(fwidth(sd), 1e-5);
    float fill = 1 - smoothstep(0.0, aa, sd);
    outColor = float4(baseColor * fill, 1.0);
}