#ifndef PI
#define PI 3.14159265359
#endif

// Helper: Signed distance to a circle
float sdCircle(float2 p, float r) {
    return length(p) - r;
}

// Helper: Polynomial smooth min for organic blending
// k controls the radius of the smooth blend
float smin(float a, float b, float k) {
    float h = max(k - abs(a - b), 0.0) / max(k, 0.0001);
    return min(a, b) - h * h * k * 0.25;
}

// User Request: A soft cartoon-style cloud made from multiple rounded bumps.
// The cloud should feel organic, not perfectly symmetric. Overall size should be adjustable.
// Single fill color with smooth edges.

void CloudShape_float(float2 UV, float2 Center, float Size, float Puffiness, float EdgeSoftness, float4 Color, out float4 outColor) {
    // PLAN:
    // 1) Remap UV to local centered coordinates.
    // 2) Scale coordinates by inverse Size to control visual scale.
    // 3) Construct cloud from 5 overlapping circles with slight asymmetry.
    // 4) Blend circles using smooth minimum (smin) to create 'puffy' organic connections.
    // 5) Apply smoothstep for soft anti-aliased edges.
    // 6) Output final RGBA color.

    // 1) Center and 2) Scale
    float2 p = UV - Center;
    float s = max(Size, 0.0001); // Prevent divide by zero
    p = p / s;

    // 3) & 4) Build SDF
    // We use a blend factor 'k' based on Puffiness input
    float k = max(Puffiness, 0.01);

    // Main central body (Base)
    float d = sdCircle(p - float2(0.0, -0.1), 0.4);

    // Left lower bump
    float d_left = sdCircle(p - float2(-0.45, -0.15), 0.3);
    d = smin(d, d_left, k);

    // Right lower bump (slightly different position/size for asymmetry)
    float d_right = sdCircle(p - float2(0.5, -0.2), 0.35);
    d = smin(d, d_right, k);

    // Top left bump
    float d_topLeft = sdCircle(p - float2(-0.25, 0.25), 0.32);
    d = smin(d, d_topLeft, k);

    // Top right bump (the peak)
    float d_topRight = sdCircle(p - float2(0.3, 0.3), 0.28);
    d = smin(d, d_topRight, k);

    // 5) Anti-aliasing / Softness
    // Smoothstep creates the gradient for the edge.
    // We range from +soft to -soft. Negative distance is inside shape.
    float soft = max(EdgeSoftness, 0.001);
    float alpha = smoothstep(soft, -soft, d);

    // 6) Output
    // Apply alpha to RGB for proper blending in standard transparent setups
    outColor = float4(Color.rgb * alpha, alpha);
}