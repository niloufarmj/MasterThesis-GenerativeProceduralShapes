void FilledDarkCircle_float(
    float2 UV,
    float2 Center,
    float Radius,
    float4 DarkColor,
    out float4 outColor
) {
    // Offset UV by center to get local coordinates
    float2 p = UV - Center;
    
    // Calculate the signed distance field for a circle
    float d = length(p) - Radius;
    
    // Calculate anti-aliasing width using screen space derivatives
    float aa = fwidth(d);
    aa = max(aa, 0.0001); // Safety clamp to prevent zero division
    
    // Compute the shape mask using smoothstep for soft anti-aliased edges
    float mask = smoothstep(aa, -aa, d);
    
    // Output final premultiplied color
    outColor = float4(DarkColor.rgb * mask, DarkColor.a * mask);
}