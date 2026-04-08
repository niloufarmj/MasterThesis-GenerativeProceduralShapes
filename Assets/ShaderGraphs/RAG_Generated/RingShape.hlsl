void RingShape_float(
    float2 UV,
    float2 Center,
    float Radius,
    float Thickness,
    float4 Color,
    out float4 outColor
) {
    // Offset UV by Center to get local coordinates
    float2 p = UV - Center;
    
    // Calculate signed distance field (SDF) for a ring (annulus)
    // The distance to the circle's perimeter is abs(length(p) - Radius)
    // We subtract Thickness to give the ring width
    float d = abs(length(p) - Radius) - Thickness;
    
    // Calculate anti-aliasing softness based on screen derivatives
    float aa = fwidth(d);
    aa = max(aa, 0.0001); // Safety clamp to prevent zero width
    
    // Smoothstep for AA: 1.0 inside (negative dist), 0.0 outside (positive dist)
    float alpha = smoothstep(aa, -aa, d) * Color.a;
    
    // Output final color with premultiplied alpha
    outColor = float4(Color.rgb * alpha, alpha);
}