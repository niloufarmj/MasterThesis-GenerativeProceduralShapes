void HeartShape_float(float2 UV, float Size, float3 Color, out float4 outColor) {
    // Center UV and scale
    float2 centered = (UV - float2(0.5, 0.5)) / Size;
    
    // Define the heart shape using circles and a triangle
    float2 p = float2(centered.x, -centered.y); // flip y for easier math
    p.x = abs(p.x); // heart is symmetrical along y-axis
    float d1 = length(p - float2(0.5, 0.4)); // circle right
    float d2 = length(p - float2(-0.5, 0.4)); // circle left
    float dTriangleBase = (p.y - 0.4) + 0.6 * abs(p.x); // triangle shape
    float d = min(min(d1, d2), dTriangleBase);
    
    // Compute smooth edge
    float edge = smoothstep(0.01, -0.01, d);
    
    // Set output color
    outColor = float4(Color * edge, edge);
}