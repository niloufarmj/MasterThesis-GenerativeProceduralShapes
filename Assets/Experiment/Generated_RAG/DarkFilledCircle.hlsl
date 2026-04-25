void DarkFilledCircle_float(float2 UV, float2 Center, float Radius, float4 DarkColor, out float4 outColor) {
    // Offset UV by Center to get local coordinates
    float2 p = UV - Center;
    
    // Calculate Signed Distance Field (SDF) for a circle
    float d = length(p) - Radius;
    
    // Calculate anti-aliasing width using screen space derivatives
    float aa = fwidth(d);
    aa = max(aa, 0.0001); // Prevent division by zero or overly hard edges
    
    // Compute alpha mask: 1.0 inside the circle (negative dist), 0.0 outside (positive dist)
    float mask = smoothstep(aa, -aa, d);
    
    // Output final color with premultiplied alpha for transparency blending
    outColor = float4(DarkColor.rgb * mask, DarkColor.a * mask);
}