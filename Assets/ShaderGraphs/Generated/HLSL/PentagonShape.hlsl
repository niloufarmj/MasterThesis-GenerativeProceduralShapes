void PentagonShape_float(float2 UV, float Size, float3 Color, out float4 outColor) {
    // Center UV coordinates
    float2 centered = UV - 0.5;
    
    // Pentagon SDF calculations
    float r = Size;
    float a = atan2(centered.x, centered.y);
    float pi = 3.14159265359;
    float angleInc = 2 * pi / 5; // Pentagon (5-sides)
    float da = fmod(abs(a) + angleInc/2, angleInc) - angleInc/2;
    float distanceEdge = r / cos(da);

    // SDF distance
    float dist = length(centered) - distanceEdge;
    
    // Anti-aliasing edge smoothing
    float edge = smoothstep(0.01, -0.01, dist);

    // Output with smooth alpha channel
    outColor = float4(Color * edge, edge);
}