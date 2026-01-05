#ifndef PI
#define PI 3.14159265359
#endif

// Helper: Box SDF
// Returns signed distance to an axis-aligned box with half-extents b
float sdBox(float2 p, float2 b) {
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// Helper: Rounded Box SDF
// Wraps sdBox to subtract radius r, creating rounded corners
float sdRoundBox(float2 p, float2 b, float r) {
    // We shrink the box by r so the visual size remains (b+r) - r = b
    // But here b is the target visual half-size, so we subtract r from it.
    // We clamp r to avoid negative dimensions.
    float2 q = b - r;
    return sdBox(p, q) - r;
}

// Helper: Alpha Blending (Source Over)
// Composites src on top of dst
float4 over(float4 src, float4 dst) {
    float a = src.a + dst.a * (1.0 - src.a);
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-8);
    return float4(c, a);
}

void LetterIShape_float(
    float2 UV,
    float Height,
    float StemThickness,
    float SerifWidth,
    float CornerRadius,
    float2 Center,
    float Rotation,
    float4 FillColor,
    float4 OutlineColor,
    float OutlineThickness,
    out float4 outColor
) {
    // PLAN:
    // 1) Transform UV to centered, rotated local space.
    // 2) Define half-sizes for the vertical stem and horizontal serifs.
    // 3) Compute SDFs for the stem and the two serifs (top/bottom).
    // 4) Combine them using min() to form the union.
    // 5) Render fill and outline with analytic anti-aliasing.

    // 1) Coordinates
    float2 p = UV - Center;
    float cosR = cos(Rotation);
    float sinR = sin(Rotation);
    p = float2(cosR * p.x + sinR * p.y, -sinR * p.x + cosR * p.y);

    // 2) Dimensions & Setup
    // Half-dimensions for calculations
    float h = max(Height, 0.001) * 0.5;
    float t = max(StemThickness, 0.001) * 0.5;
    float sw = max(SerifWidth, 0.0) * 0.5;

    // Clamp corner radius to half the stem thickness to prevent artifacts
    // This ensures rounded corners don't consume the entire shape
    float r = clamp(CornerRadius, 0.0, t);

    // 3) SDF Construction
    // Vertical Stem: Centered at (0,0), total height 'Height'
    float dStem = sdRoundBox(p, float2(t, h), r);

    // Serifs: Top and Bottom horizontal bars
    // They are placed so their outer edges align with the total Height.
    // Center Y offset = (Height/2 - Thickness/2)
    float yOffset = max(0.0, h - t);
    float2 serifSize = float2(sw, t);

    // Calculate distance to top and bottom serifs
    float dTop = sdRoundBox(p - float2(0.0, yOffset), serifSize, r);
    float dBot = sdRoundBox(p + float2(0.0, yOffset), serifSize, r);

    // 4) Union
    // Combine all parts. min() creates a boolean union.
    float d = min(dStem, min(dTop, dBot));

    // 5) Rendering
    // Analytic Anti-Aliasing using screen-space derivatives
    float aa = fwidth(d);
    if (aa < 0.0001) aa = 0.002; // Safety fallback

    // Fill Mask
    // SDF is negative inside, positive outside.
    float fillAlpha = 1.0 - smoothstep(-aa, aa, d);
    float4 fill = float4(FillColor.rgb, FillColor.a * fillAlpha);

    // Outline Mask
    // Outline is a band centered on the zero-crossing.
    float halfOutline = OutlineThickness * 0.5;
    float outlineEdge = abs(d) - halfOutline;
    float outlineAlpha = 1.0 - smoothstep(-aa, aa, outlineEdge);
    float4 outline = float4(OutlineColor.rgb, OutlineColor.a * outlineAlpha);

    // 6) Composite (Outline on top of Fill)
    outColor = over(outline, fill);
}