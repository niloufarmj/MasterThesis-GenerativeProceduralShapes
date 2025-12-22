#ifndef PI
#define PI 3.14159265359
#endif

// --- Helpers ---

// SDF for an axis-aligned box centered at origin with half extents b
inline float sdBox(float2 p, float2 b) {
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// SDF for a rounded box
// b = half extents of the bounding box
// r = radius
// Effectively an inner box of size b-r, inflated by r
inline float sdRoundBox(float2 p, float2 b, float r) {
    return sdBox(p, b - r) - r;
}

// Straight-alpha "src over dst" composition
inline float4 over(float4 src, float4 dst) {
    float a = src.a + dst.a * (1.0 - src.a);
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-8);
    return float4(c, a);
}

// --- Main Function ---
// PLAN:
// 1) Recenter UV coordinates based on Center input.
// 2) Apply 2D rotation to the coordinate system.
// 3) Calculate half-extents from Width/Height and clamp Radius to be valid.
// 4) Compute SDF using sdRoundBox.
// 5) Compute Anti-Aliasing factor using fwidth.
// 6) Generate Fill mask and Stroke mask.
// 7) Composite Stroke over Fill for final output.

void RoundedRectangle_float(float2 UV, float Width, float Height, float Radius, float2 Center, float Rotation, float4 FillColor, float4 StrokeColor, float StrokeWidth, out float4 outColor) {
    // 1) Recenter
    float2 p = UV - Center;

    // 2) Rotate coordinates
    float c = cos(Rotation);
    float s = sin(Rotation);
    p = float2(c * p.x + s * p.y, -s * p.x + c * p.y);

    // 3) Define dimensions
    // Ensure positive dimensions
    float2 halfSize = float2(max(Width, 0.0), max(Height, 0.0)) * 0.5;
    // Clamp radius so it doesn't exceed half the shortest side
    float r = clamp(Radius, 0.0, min(halfSize.x, halfSize.y));

    // 4) Calculate SDF
    float d = sdRoundBox(p, halfSize, r);

    // 5) Analytic Anti-Aliasing
    // fwidth gives the rate of change of the SDF (pixel footprint)
    float aa = fwidth(d);

    // 6) Fill Logic
    // smoothstep from 0 to aa creates a smooth edge at the boundary
    float fillMask = 1.0 - smoothstep(0.0, aa, d);
    float4 fillOut = float4(FillColor.rgb, saturate(FillColor.a) * fillMask);

    // 7) Stroke Logic
    // Stroke is a band centered on the zero-distance contour
    float halfStroke = max(StrokeWidth, 0.0) * 0.5;
    float strokeD = abs(d) - halfStroke;
    float strokeMask = 1.0 - smoothstep(0.0, aa, strokeD);
    float4 strokeOut = float4(StrokeColor.rgb, saturate(StrokeColor.a) * strokeMask);

    // 8) Composition (Stroke Over Fill)
    outColor = over(strokeOut, fillOut);
}