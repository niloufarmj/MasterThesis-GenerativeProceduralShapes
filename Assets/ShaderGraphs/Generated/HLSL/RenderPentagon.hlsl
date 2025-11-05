void RenderPentagon_float(float2 UV, float size, float stroke, float rotation, float cornerRadius, out float4 outColor) {
    float2 center = float2(0.5, 0.5);
    float angleOffset = 6.28318530718 / 5.0; // 360 degrees / 5 corners
    UV = UV - center;
    float currentAngle = atan2(UV.y, UV.x) - rotation;
    currentAngle = fmod(currentAngle, angleOffset);
    currentAngle = abs(currentAngle - angleOffset / 2.0);
    float r = cornerRadius + stroke * (1.0 - smoothstep(0.0, cornerRadius, currentAngle));
    float distanceFromCenter = length(UV);
    float alpha = smoothstep(size - stroke, size, distanceFromCenter) - smoothstep(size, size + stroke, distanceFromCenter);
    outColor = float4(1.0, 1.0, 1.0, alpha);
}