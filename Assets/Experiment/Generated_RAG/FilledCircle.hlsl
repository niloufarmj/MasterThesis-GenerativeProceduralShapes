void FilledCircle_float(
    float2 UV,
    float Radius,
    float2 Center,
    float4 Color,
    out float4 outColor
) {
    // Offset UV by Center to get local coordinates
    float2 p = UV - Center;
    
    // Calculate signed distance field (SDF) for a circle
    float d = length(p) - Radius;
    
    // Calculate anti-aliasing width using screen derivatives
    float aa = fwidth(d);
    aa = max(aa, 0.0001); // Safety clamp to prevent division by zero
    
    // Smoothstep for anti-aliasing: 1.0 inside, 0.0 outside
    float edge = smoothstep(aa, -aa, d);
    
    // Output final color with premultiplied alpha
    outColor = float4(Color.rgb * edge * Color.a, edge * Color.a);
}