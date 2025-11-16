void DynamicPentagon_float(float2 UV, float Size, float StrokeWidth, float Rotation, float CornerRadius, float3 Color, out float4 outColor) {
    // Center UV coordinates
    float2 centered = UV - 0.5;
    
    // Correct for aspect ratio
    centered.x *= 2.0;
    
    // Rotate coordinates
    float rad = Rotation * 3.14159265;
    float cr = cos(rad);
    float sr = sin(rad);
    float2 rotated = float2(centered.x * cr - centered.y * sr, centered.x * sr + centered.y * cr);
    
    // Compute pentagon SDF
    float iAngle = 0.6283185307; // 2*PI/5
    float d = length(rotated) - Size;
    rotated = abs(rotated);
    float inRadius = CornerRadius * (1.0 + cos(iAngle));
    
    rotated = max(rotated, rotated.yx);
    float pX = cos(iAngle) * rotated.x - sin(iAngle) * rotated.y;
    float pY = sin(iAngle) * rotated.x + cos(iAngle) * rotated.y;
    d = max(d, pY - rotated.x * tan(iAngle / 2.0) + inRadius);
    
    // Apply stroke
    float edge = smoothstep(-StrokeWidth, StrokeWidth, d);
    
    // Set output color
    outColor = float4(Color * edge, 1.0);
}