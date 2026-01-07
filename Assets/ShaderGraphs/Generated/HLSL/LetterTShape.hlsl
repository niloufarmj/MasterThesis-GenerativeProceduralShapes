#ifndef PI
#define PI 3.14159265359
#endif

// SDF for an axis-aligned box
float sdBox(float2 p, float2 b) {
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// Alpha blending helper (Src Over Dst)
float4 nm_over(float4 src, float4 dst) {
    float a = src.a + dst.a * (1.0 - src.a);
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-8);
    return float4(c, a);
}

void LetterTShape_float(float2 UV, float Width, float Height, float Thickness, float CornerRadius, float Angle, float4 FillColor, float4 OutlineColor, float OutlineWidth, out float4 OutColor) {
    // PLAN:
    // 1) Center UVs at (0,0) and rotate by Angle.
    // 2) Define geometry for Top Bar and Vertical Stem based on Width, Height, Thickness.
    // 3) Create SDFs for both boxes, using a boolean Union (min).
    // 4) Apply CornerRadius by shrinking boxes and subtracting radius from the result.
    // 5) Render solid fill and outline using analytic AA (fwidth).

    float2 p = UV - 0.5;

    // 1) Rotation
    float c = cos(Angle);
    float s = sin(Angle);
    p = float2(c * p.x + s * p.y, -s * p.x + c * p.y);

    // 2) Dimensions & Clamping
    float w = max(Width, 0.0);
    float h = max(Height, 0.0);
    float t = clamp(Thickness, 0.001, h); // Thickness limited by total height

    // Box 1: Top Horizontal Bar
    // Centered horizontally. Y position is at the top of the shape.
    // Total Height is h. Top edge at y = h/2.
    // Bar extends down by 't'. Center Y = h/2 - t/2.
    float2 topCenter = float2(0.0, h * 0.5 - t * 0.5);
    float2 topSize = float2(w * 0.5, t * 0.5);

    // Box 2: Vertical Stem
    // Centered horizontally. Bottom edge at y = -h/2.
    // Top of stem meets the top bar at y = h/2 - t.
    // Stem Height = h - t.
    // Stem Center Y = -h/2 + (h - t)/2 = -t/2.
    float2 stemCenter = float2(0.0, -t * 0.5);
    float2 stemSize = float2(t * 0.5, max((h - t) * 0.5, 0.0));

    // 3) Corner Radius Logic
    // Valid radius is limited by the smallest dimension of the shapes
    float minDim = min(min(topSize.x, topSize.y), min(stemSize.x, stemSize.y));
    float r = clamp(CornerRadius, 0.0, minDim);

    // Shrink box dimensions by r so that 'd - r' maintains correct outer size
    float2 topSizeR = topSize - r;
    float2 stemSizeR = stemSize - r;

    // 4) SDF Calculation
    float dTop = sdBox(p - topCenter, topSizeR);
    float dStem = sdBox(p - stemCenter, stemSizeR);
    
    // Union of the two parts, then rounded
    float dist = min(dTop, dStem) - r;

    // 5) Rendering with AA
    float aa = fwidth(dist);
    aa = max(aa, 0.0001); // Safety for preview

    // Fill Layer
    float fillAlpha = 1.0 - smoothstep(-aa, aa, dist);
    float4 fill = float4(FillColor.rgb, FillColor.a * fillAlpha);

    // Outline Layer
    float halfStroke = OutlineWidth * 0.5;
    float outlineDist = abs(dist) - halfStroke;
    float outlineAlpha = 1.0 - smoothstep(-aa, aa, outlineDist);
    float4 outline = float4(OutlineColor.rgb, OutlineColor.a * outlineAlpha);

    // Composite Outline OVER Fill
    OutColor = nm_over(outline, fill);
}