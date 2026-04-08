void DrawCircle_float(float2 UV, float2 Center, float Radius, float4 CircleColor, out float4 outColor) {
    // Offset UV to the requested center position
    float2 p = UV - Center;
    
    // Calculate Signed Distance Field (SDF) for the circle
    float d = length(p) - Radius;
    
    // Calculate anti-aliasing width using fwidth to ensure smooth edges at any scale/resolution
    float aa = fwidth(d);
    aa = max(aa, 0.001); // Prevent completely hard edges or division by zero
    
    // Smoothstep creates the anti-aliased edge mask. 
    // 1.0 inside (negative distance), 0.0 outside (positive distance)
    float mask = smoothstep(aa, -aa, d);
    
    // Output the final color, pre-multiplied by the alpha mask for clean blending
    outColor = float4(CircleColor.rgb * mask, CircleColor.a * mask);
}
