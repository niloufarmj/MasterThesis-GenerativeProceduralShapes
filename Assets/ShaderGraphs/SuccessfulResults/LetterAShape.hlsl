// PLAN:
// 1) Define SDF segment function and smooth union helper.
// 2) Map UV to centered local coordinates.
// 3) Define key points (Apex, Bottom Left, Bottom Right) based on Width/Height.
// 4) Calculate Crossbar endpoints by interpolating along the legs at CrossbarHeight.
// 5) Combine 3 segments (2 legs, 1 bar) using smooth union for rounded joints.
// 6) Subtract Thickness/2 to create the solid shape volume.
// 7) Compute Fill and Outline coverage using fwidth-based AA and composite.

#ifndef PI
#define PI 3.14159265359
#endif

// Helper: Signed Distance to a Line Segment
// p: sampling point, a: start, b: end
float nm_sdSegment(float2 p, float2 a, float2 b) {
    float2 pa = p - a;
    float2 ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}

// Helper: Smooth Min (Polynomial) for organic unions
// k: smoothness radius (approximate)
float nm_smin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / max(k, 0.0001), 0.0, 1.0);
    return lerp(b, a, h) - k * h * (1.0 - h);
}

// Helper: Composite Source Over Destination (Straight Alpha)
float4 nm_over(float4 src, float4 dst) {
    float a = src.a + dst.a * (1.0 - src.a);
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-8);
    return float4(c, a);
}

void LetterAShape_float(
    float2 UV,
    float Width,
    float Height,
    float Thickness,
    float CrossbarHeight, // 0.0 to 1.0 range (relative to leg height)
    float CornerRounding,
    float4 FillColor,
    float OutlineThickness,
    float4 OutlineColor,
    out float4 outColor
) {
    // 1) Center and Coordinate Setup
    float2 p = UV - 0.5;
    
    // 2) Define Skeleton Key Points
    // h = half-height, w = half-width
    float h = max(Height, 0.001) * 0.5;
    float w = max(Width, 0.001) * 0.5;
    
    float2 apex = float2(0.0, h);
    float2 legL = float2(-w, -h);
    float2 legR = float2(w, -h);
    
    // 3) Calculate Crossbar Points
    // Interpolate vertical position based on CrossbarHeight (0=bottom, 1=top)
    float barY = lerp(-h, h, clamp(CrossbarHeight, 0.0, 1.0));
    
    // Find the horizontal position (x) on the leg at height barY
    // Using similar triangles: width scales linearly from w (at bottom) to 0 (at top)
    float t = (h - barY) / (2.0 * h); // normalized distance from top (0.0) to bottom (1.0)
    float barX = lerp(0.0, w, t);
    
    float2 barL = float2(-barX, barY);
    float2 barR = float2(barX, barY);
    
    // 4) Compute SDFs for the 3 segments (skeleton)
    float dLeg1 = nm_sdSegment(p, legL, apex);
    float dLeg2 = nm_sdSegment(p, legR, apex);
    float dBar  = nm_sdSegment(p, barL, barR);
    
    // 5) Combine segments
    // Use smin for the apex and crossbar joints to apply CornerRounding.
    // Note: smin slightly alters distance field, but works well for visual shapes.
    float d = nm_smin(dLeg1, dLeg2, CornerRounding);
    d = nm_smin(d, dBar, CornerRounding);
    
    // 6) Apply Thickness
    // d is the distance to the geometric skeleton (centerline).
    // The surface is at distance Thickness/2.
    // SDF < 0 inside the shape.
    float dist = d - max(Thickness, 0.001) * 0.5;
    
    // 7) Rendering (Fill + Outline)
    float aa = fwidth(dist);
    
    // Fill Layer
    float fillAlpha = 1.0 - smoothstep(-aa, aa, dist);
    float4 fill = float4(FillColor.rgb, FillColor.a * fillAlpha);
    
    // Outline Layer
    // Outline is centered on the shape edge: |dist| < outline/2
    float outlineHalf = max(OutlineThickness, 0.001) * 0.5;
    float outlineDist = abs(dist) - outlineHalf;
    float outlineAlpha = 1.0 - smoothstep(-aa, aa, outlineDist);
    float4 stroke = float4(OutlineColor.rgb, OutlineColor.a * outlineAlpha);
    
    // Composite Stroke OVER Fill
    outColor = nm_over(stroke, fill);
}