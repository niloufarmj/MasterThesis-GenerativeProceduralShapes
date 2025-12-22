void DonutShape_float(float2 UV, float2 Center, float OuterRadius, float InnerRadius, float4 Color, out float4 outColor) {
    // PLAN:
    // 1) Compute centered UV coordinates (p = UV - Center).
    // 2) Compute SDF for an annulus (donut) defined by OuterRadius and InnerRadius.
    //    Formula: max(distToOuterEdge, distToHoleEdge)
    //    distToOuterEdge = length(p) - OuterRadius
    //    distToHoleEdge = InnerRadius - length(p)
    // 3) Apply analytic anti-aliasing using fwidth.
    // 4) Output final color with alpha mask.

    float2 p = UV - Center;
    float len = length(p);

    // Signed Distance Field (SDF)
    // dist < 0 inside the donut band
    // dist > 0 in the hole or outside the outer circle
    float dist = max(len - OuterRadius, InnerRadius - len);

    // Analytic Anti-aliasing
    // fwidth gives the change in distance over one pixel
    float aa = fwidth(dist);
    // Ensure aa is non-zero to prevent division issues
    aa = max(aa, 1e-5);
    
    // Create smooth mask: 1.0 inside, 0.0 outside
    float mask = 1.0 - smoothstep(0.0, aa, dist);

    // Output
    // Applying mask to both RGB and Alpha for premultiplied-compatible output
    outColor = float4(Color.rgb * mask, mask);
}