void HollowCircle_float(float2 UV, float InnerRadius, float OuterRadius, float4 Color, out float4 outColor) {
    // User Request: A hollow circle with a clear inner hole. Inner and outer radius adjustable.
    // PLAN:
    // 1) Center UV coordinates at (0.5, 0.5).
    // 2) Determine valid inner and outer radii (handle swaps).
    // 3) Calculate SDF for the ring (Intersection of Outer Circle and NOT Inner Circle).
    // 4) Apply smoothstep for anti-aliasing.
    // 5) Apply color and alpha mask.

    float2 centered = UV - 0.5;

    // Ensure radii are ordered correctly to prevent negative thickness issues
    float rIn = min(InnerRadius, OuterRadius);
    float rOut = max(InnerRadius, OuterRadius);

    // Calculate distance from center
    float len = length(centered);

    // SDF Calculation:
    // Distance to outer circle edge: len - rOut
    // Distance to inner circle edge: len - rIn
    // Ring is defined as: Inside Outer (dist < 0) AND Outside Inner (dist > 0)
    // In SDF terms: max(dist_outer, -dist_inner)
    float dOuter = len - rOut;
    float dInner = len - rIn;
    
    // Final SDF: Negative inside the ring, Positive outside
    float sdf = max(dOuter, -dInner);

    // smoothstep creates a soft anti-aliased edge between 0.01 (outside) and -0.01 (inside)
    float edge = smoothstep(0.01, -0.01, sdf);

    // Final output: RGB from Color, Alpha scaled by the shape mask
    outColor = float4(Color.rgb, Color.a * edge);
}