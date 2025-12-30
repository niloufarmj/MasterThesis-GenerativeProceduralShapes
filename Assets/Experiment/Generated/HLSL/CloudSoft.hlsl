/*
  User Request: A soft cartoon-style cloud made from multiple rounded bumps.
  Features: Organic asymmetry, adjustable size, single fill color, smooth blending.
*/

#ifndef SMIN_POLY
#define SMIN_POLY
// Smooth Minimum (Polynomial) - blends shapes organically
// k controls the smoothness of the blend
float smin_poly(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / max(k, 0.0001), 0.0, 1.0);
    return lerp(b, a, h) - k * h * (1.0 - h);
}
#endif

void CloudSoft_float(float2 UV, float Size, float4 Color, float Blend, out float4 outColor) {
    // PLAN:
    // 1. Center UV coordinates and normalize by Size parameter.
    // 2. Define multiple circle SDFs with asymmetric offsets to form an organic cloud cluster.
    // 3. Combine circles using smooth minimum (smin) to create soft, merging joints.
    // 4. Rescale the distance field to UV space to ensure consistent edge softness.
    // 5. Compute anti-aliased alpha mask using fwidth and output premultiplied color.

    // 1. Center and Scale
    float2 p = UV - 0.5;
    // Divide by Size to scale the coordinate system (avoid div by zero)
    // A larger Size value effectively 'zooms in', making the object larger
    float2 pos = p / max(Size, 0.0001);

    // 2. Define Cloud Bumps (Offsets are relative to the scaled space)
    // Main central body (slightly offset downwards)
    float d = length(pos - float2(0.0, -0.1)) - 0.4;

    // Left-bottom lobe
    float d2 = length(pos - float2(-0.35, -0.15)) - 0.25;
    d = smin_poly(d, d2, Blend);

    // Right-bottom lobe
    float d3 = length(pos - float2(0.35, -0.12)) - 0.28;
    d = smin_poly(d, d3, Blend);

    // Top-left lobe (creates height variation)
    float d4 = length(pos - float2(-0.2, 0.22)) - 0.28;
    d = smin_poly(d, d4, Blend);

    // Top-right lobe
    float d5 = length(pos - float2(0.25, 0.18)) - 0.26;
    d = smin_poly(d, d5, Blend);

    // 3. Rescale Distance
    // Multiply by Size to bring distance values back to UV unit scale
    d *= Size;

    // 4. Anti-Aliasing
    // Calculate screen-space derivative for sharp yet smooth edges at any scale
    float aa = fwidth(d);
    aa = max(aa, 0.001); // Safety clamp

    // Smoothstep creates the anti-aliased edge mask
    // 1.0 inside the cloud, 0.0 outside
    float alpha = 1.0 - smoothstep(-aa, aa, d);

    // 5. Output
    // Apply mask to RGB and Alpha (premultiplied-like behavior for blending)
    outColor = float4(Color.rgb * alpha, alpha);
}