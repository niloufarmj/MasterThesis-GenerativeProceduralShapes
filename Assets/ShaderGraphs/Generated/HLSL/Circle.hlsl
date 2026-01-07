void Circle_float(float2 UV, float Radius, float2 Center, float4 Color, out float4 outColor) {
    // User Request: a circle
    // PLAN:
    // 1) Offset UV by Center to get local coordinates p.
    // 2) Calculate signed distance field (SDF) for a circle: length(p) - radius.
    // 3) Calculate anti-aliasing width using fwidth for sharp edges.
    // 4) Compute alpha mask using smoothstep centered on the edge.
    // 5) Output final color with premultiplied alpha.

    float2 p = UV - Center;
    float d = length(p) - Radius;
    
    // Calculate anti-aliasing softness based on screen derivatives
    float aa = fwidth(d);
    aa = max(aa, 0.001); // Safety clamp to prevent division by zero or extremely hard edges
    
    // Smoothstep for AA: 1.0 inside (negative dist), 0.0 outside (positive dist)
    // Centered at 0: range [aa, -aa]
    float edge = smoothstep(aa, -aa, d);
    
    outColor = float4(Color.rgb * edge, edge);
}