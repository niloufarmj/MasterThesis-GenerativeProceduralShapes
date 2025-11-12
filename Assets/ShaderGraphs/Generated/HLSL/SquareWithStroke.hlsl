float sdf_box(float2 p, float2 b)
{
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

void SquareWithStroke_float(float2 UV, float StrokeWidth, out float4 outColor) {
    float2 p = UV - 0.5;
    float size = 0.4;
    float sd = sdf_box(p, float2(size, size));
    float aa = max(fwidth(sd), 1e-5);
    float fill = 1.0 - smoothstep(0.0, aa, sd);
    float stroke = smoothstep(StrokeWidth - aa, StrokeWidth, abs(sd));
    outColor = float4(fill * stroke, fill * stroke, fill * stroke, 1.0);
}

