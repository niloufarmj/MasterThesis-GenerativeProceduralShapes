void FilledCircleDark_float(
    float2 UV,
    float Radius,
    float2 Center,
    float4 Color,
    out float4 outColor
) {
    float2 p = UV - Center;
    float d = length(p) - Radius;
    float aa = max(fwidth(d), 0.001);
    float edge = smoothstep(aa, -aa, d);
    outColor = float4(Color.rgb * edge, edge);
}