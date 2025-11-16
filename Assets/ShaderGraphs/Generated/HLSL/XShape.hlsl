void XShape_float(float2 UV, float Width, float Fuzziness, float3 Color, out float4 outColor) {
    // PLAN:
    // 1) Center UV coordinates
    float2 centered = UV - 0.5;
    
    // 2) Calculate each line of the 'X'
    float line1 = abs(centered.x + centered.y);
    float line2 = abs(centered.x - centered.y);
    
    // 3) Combine the two lines using minimum distance (intersection)
    float dist = min(line1, line2) - Width;
    
    // 4) Anti-alias the edge
    float edge = smoothstep(Fuzziness, -Fuzziness, dist);
    
    // 5) Output color
    outColor = float4(Color * edge, edge);
}