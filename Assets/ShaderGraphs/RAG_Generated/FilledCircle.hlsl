void FilledCircle_float(
    float2 UV, 
    float Radius,
    float2 Center,
    float4 FillColor,
    out float4 outColor
) {
    // 1. Center the coordinate system
    float2 p = UV - Center;
    
    // 2. Calculate the Signed Distance Function (SDF) for a circle
    // The distance is length(p) - Radius. It's negative inside, zero on the edge, positive outside.
    float d = length(p) - Radius;
    
    // 3. Calculate anti-aliasing width using screen-space derivatives of the distance
    // fwidth(d) gives us an estimate of how much 'd' changes over a single pixel.
    float aa = fwidth(d);
    aa = max(aa, 0.0001); // Clamp to prevent division by zero on flat areas

    // 4. Use smoothstep to create a soft edge for anti-aliasing
    // We transition from 1 (inside) to 0 (outside) over the range defined by 'aa'.
    // smoothstep(edge1, edge0, value) gives a smooth transition.
    // Here, we transition from fully opaque (alpha=1) at d=-aa to fully transparent (alpha=0) at d=aa.
    float alpha = smoothstep(aa, -aa, d);
    
    // 5. Output the final color with pre-multiplied alpha
    // This is standard for alpha blending.
    outColor = float4(FillColor.rgb * alpha, alpha);
}