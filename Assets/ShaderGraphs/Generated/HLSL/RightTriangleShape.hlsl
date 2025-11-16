void RightTriangleShape_float(float2 UV, float Height, float Base, float3 Color, out float4 outColor) {
    // Recenter and scale UV
    float2 centered = (UV - float2(0.5, 0.5)) * 2.0;
    // Calculate the signed distance from the point to the line forming the triangle
    float d = (centered.x * Height + centered.y * Base);
    // Calculate the signed distance from the point to the hypotenuse
    float hypotenuse = sqrt(Height * Height + Base * Base);
    float edge1 = step(0.0, -centered.x);
    float edge2 = step(0.0, -centered.y);
    float edge3 = step(0.0, d - 0.5 * hypotenuse);
    float insideTriangle = edge1 * edge2 * edge3;
    // Use smoothstep for anti-aliasing the edges
    float aa = fwidth(d);
    float edge = smoothstep(0.01, -0.01, insideTriangle);
    // Output color with smoothed edges and full alpha
    outColor = float4(Color * edge, 1.0);
}