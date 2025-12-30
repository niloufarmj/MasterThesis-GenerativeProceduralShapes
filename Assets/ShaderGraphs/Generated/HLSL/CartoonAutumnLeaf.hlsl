void CartoonAutumnLeaf_float(float2 UV, float Size, float LeafLength, float LeafWidth, float EdgeWaviness, float WaveFreq, float VeinThickness, float4 LeafColor, float4 VeinColor, float Rotation, float2 Center, out float4 outColor) {
    // PLAN:
    // 1) Transform UV to centered, rotated, scaled coordinate space 'p'.
    // 2) Construct a 'Vesica' SDF (intersection of two circles) determined by Width and Length.
    //    - Solve for circle offset 'd' and radius 'r' given w and h.
    // 3) Apply sinusoidal perturbation to the SDF for waviness, masked near tips.
    // 4) Construct a central vein SDF (tapered vertical line).
    // 5) Compute smooth masks using fwidth for AA.
    // 6) Composite Vein over Leaf color.
    // 7) Output final color with calculated alpha mask.

    // 1. Coordinates
    float2 p = (UV - Center) * 2.0; // Map 0..1 to -1..1
    
    // Rotation
    float c = cos(Rotation);
    float s = sin(Rotation);
    p = float2(c * p.x - s * p.y, s * p.x + c * p.y);
    
    // Scale normalization (prevent divide by zero)
    float safeSize = max(Size, 0.001);
    p /= safeSize;

    // 2. Leaf Shape (Vesica Segment)
    // h = half length, w = half width
    float h = max(LeafLength, 0.01) * 0.5;
    float w = max(LeafWidth, 0.01) * 0.5;
    
    // Solve for circle parameters that pass through (w,0) and (0,h)
    // Circle equation centered at (-d, 0) with radius r:
    // d = (h^2 - w^2) / (2w)
    // r = d + w
    float d_offset = (h*h - w*w) / (2.0 * w);
    float r = d_offset + w;
    
    // Intersection of two offset circles
    float2 c1 = float2(-d_offset, 0.0);
    float2 c2 = float2(d_offset, 0.0);
    
    // The leaf is the intersection of the two circles (SDF)
    // max() acts as boolean intersection for SDFs
    float distLeaf = max(length(p - c1) - r, length(p - c2) - r);
    
    // 3. Edge Waviness
    // Apply sine wave based on height (y), fade it out at the tips (near h and -h)
    // to preserve the pointed leaf tips.
    float tipMask = 1.0 - smoothstep(h * 0.7, h, abs(p.y));
    float wave = sin(p.y * WaveFreq * 6.28) * EdgeWaviness * 0.1 * tipMask;
    
    // Add wave to distance. 
    // Note: This isn't a perfect Euclidean SDF anymore, but visually correct for 2D.
    distLeaf += wave;

    // 4. Central Vein
    // Vertical line segment with tapering thickness
    // Taper: thickest at bottom/center, thins out towards tips
    float taper = 1.0 - smoothstep(0.0, h, abs(p.y)); // Simple linear-ish taper
    float currentVeinThickness = VeinThickness * 0.1 * (0.4 + 0.6 * taper);
    float distVein = abs(p.x) - currentVeinThickness;
    
    // Cut vein at the leaf tips (a bit shorter than the leaf)
    distVein = max(distVein, abs(p.y) - h * 0.9);

    // 5. Anti-aliasing and Masking
    float aa = fwidth(distLeaf);
    aa = max(aa, 0.001); // Safety for preview windows with no derivatives
    
    float maskLeaf = 1.0 - smoothstep(0.0, aa, distLeaf);
    float maskVein = 1.0 - smoothstep(0.0, aa, distVein);

    // 6. Composition
    // Vein sits on top of leaf.
    // We blend colors based on vein opacity (maskVein).
    float4 finalRGB = lerp(LeafColor, VeinColor, maskVein);
    
    // 7. Final Output
    // Apply leaf alpha mask to the color
    outColor = float4(finalRGB.rgb * maskLeaf, maskLeaf);
}