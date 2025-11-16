void ExclamationMark_float(float2 UV, float Size, float4 Color, out float4 outColor) {
    // Plan:
    // 1) Center and scale UV coordinates
    // 2) Define narrow rectangle for the stem
    // 3) Define small circle for the dot
    // 4) Combine shapes with union
    // 5) Apply color and output
    
    float2 centered = UV - float2(0.5, 0.5);
    centered.y *= 1.6; // Stretch vertically to make space for dot
    
    // Stem: narrow vertical rectangle
    float2 stemSize = float2(Size * 0.1, Size);
    float stemDist = length(max(abs(centered) - stemSize, 0.0));
    
    // Dot: small circle below stem
    float dotRadius = Size * 0.15;
    float dotDist = length(centered - float2(0.0, -Size * 0.75)) - dotRadius;
    
    // Union of stem and dot
    float dist = min(stemDist, dotDist);
    
    // Smooth edge for anti-aliasing
    float edge = smoothstep(0.01, -0.01, dist);
    
    // Apply color and alpha mask
    outColor = float4(Color.rgb * edge, edge);
}