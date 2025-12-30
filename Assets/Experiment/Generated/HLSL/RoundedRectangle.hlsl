#ifndef PI
#define PI 3.14159265359
#endif

// Helper: Signed Distance Function for a rounded box
// p: point in centered space
// b: half-extents of the box (width/2, height/2)
// r: corner radius
float sdRoundedBox(float2 p, float2 b, float r) {
    float2 q = abs(p) - (b - r);
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void RoundedRectangle_float(float2 UV, float Width, float Height, float Radius, float4 Color, out float4 outColor) {
    // PLAN:
    // 1) Center the UV coordinates (0.5, 0.5 becomes 0,0).
    // 2) Define half-size based on Width and Height.
    // 3) Clamp the radius so it doesn't exceed the size of the box (prevents artifacts).
    // 4) Calculate SDF using sdRoundedBox.
    // 5) Apply smoothstep for anti-aliasing.
    // 6) Output final color.

    // 1. Center UV coordinates
    float2 centered = UV - 0.5;

    // 2. Determine half-extents
    // Width and Height are total sizes, so we divide by 2.
    float2 halfSize = float2(Width, Height) * 0.5;
    
    // Ensure size is non-negative
    halfSize = max(halfSize, 0.0);

    // 3. Clamp Radius
    // The radius cannot be larger than half the smallest dimension,
    // otherwise the math inverts and looks wrong.
    float maxRadius = min(halfSize.x, halfSize.y);
    float r = clamp(Radius, 0.0, maxRadius);

    // 4. Calculate Signed Distance
    float dist = sdRoundedBox(centered, halfSize, r);

    // 5. Anti-aliasing
    // fwidth gives us a pixel-perfect edge width regardless of scale
    float edgeWidth = fwidth(dist);
    // Fallback for cases where fwidth might return 0
    edgeWidth = max(edgeWidth, 0.0001);
    
    // Smoothstep creates a smooth transition from 1 (inside) to 0 (outside)
    // The edge spans from -edgeWidth to +edgeWidth around the surface (dist=0)
    float mask = 1.0 - smoothstep(-edgeWidth, edgeWidth, dist);

    // 6. Final Output
    // Apply mask to RGB and Alpha
    outColor = float4(Color.rgb * mask, mask);
}