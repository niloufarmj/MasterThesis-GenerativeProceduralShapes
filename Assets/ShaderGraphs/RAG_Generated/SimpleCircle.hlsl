void SimpleCircle_float(float2 UV, float Radius, float2 Center, float4 FillColor, out float4 outColor) {
    // Offset UV to shape center
    float2 p = UV - Center;
    
    // Calculate Signed Distance Field for a circle
    float d = length(p) - Radius;
    
    // Calculate anti-aliasing factor based on screen space derivatives
    float aa = fwidth(d);
    aa = max(aa, 0.0001); // Prevent division by zero
    
    // Smoothstep for anti-aliased edges (1.0 inside, 0.0 outside)
    float mask = smoothstep(aa, -aa, d);
    
    // Output premultiplied color
    outColor = float4(FillColor.rgb * mask, FillColor.a * mask);
}