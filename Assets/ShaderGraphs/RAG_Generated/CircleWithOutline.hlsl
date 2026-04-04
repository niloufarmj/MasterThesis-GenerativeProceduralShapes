void CircleWithOutline_float(
    float2 UV,
    float2 Center,
    float Radius,
    float OutlineThickness,
    float4 FillColor,
    float4 OutlineColor,
    out float4 outColor
) {
    // Center the coordinates
    float2 p = UV - Center;
    
    // Calculate distance fields for both inner circle and outer outline
    float d_inner = length(p) - Radius;
    float d_outer = d_inner - OutlineThickness;
    
    // Calculate anti-aliasing softness based on screen derivatives
    float aa = max(fwidth(d_inner), 0.001);
    
    // Generate masks for inner and outer shapes using smoothstep for AA
    float alpha_inner = smoothstep(aa, -aa, d_inner);
    float alpha_outer = smoothstep(aa, -aa, d_outer);
    
    // Blend between outline color and fill color based on the inner mask
    float4 blendedColor = lerp(OutlineColor, FillColor, alpha_inner);
    
    // Apply the outer mask to cut out the final shape and output premultiplied alpha
    outColor = float4(blendedColor.rgb * alpha_outer, blendedColor.a * alpha_outer);
}