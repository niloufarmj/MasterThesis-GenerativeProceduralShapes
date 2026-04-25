void DarkCircle_float(float2 UV, float2 Center, float Radius, float4 CircleColor, out float4 outColor) {
    // Offset UV to the local center
    float2 p = UV - Center;
    
    // Calculate the signed distance field for a circle
    float d = length(p) - Radius;
    
    // Calculate anti-aliasing width based on screen derivatives for smooth edges
    float aa = fwidth(d);
    aa = max(aa, 0.001); // Safety clamp to prevent division by zero or overly sharp edges
    
    // Calculate alpha using smoothstep (1.0 inside, 0.0 outside)
    float alpha = smoothstep(aa, -aa, d);
    
    // Output final color with premultiplied alpha
    outColor = float4(CircleColor.rgb * alpha, CircleColor.a * alpha);
}
