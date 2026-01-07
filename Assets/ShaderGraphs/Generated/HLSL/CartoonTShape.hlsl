#ifndef PI
#define PI 3.14159265359
#endif

// --- Helper Functions ---

// Straight-alpha compositing (Source Over Destination)
float4 CTS_over(float4 src, float4 dst) {
    float a = src.a + dst.a * (1.0 - src.a);
    // Avoid division by zero
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-8);
    return float4(c, a);
}

// Signed Distance to a Box
// p: point relative to center
// b: half-extents (width/2, height/2)
float CTS_sdBox(float2 p, float2 b) {
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// Signed Distance to a Rounded Box
// p: point, b: half-extents, r: radius
float CTS_sdRoundBox(float2 p, float2 b, float r) {
    return CTS_sdBox(p, b - r) - r;
}

// --- Main Shape Function ---
// User Request: Cartoon letter T shape with adjustable size, width, height, thickness, outline, and corner radius.
void CartoonTShape_float(
    float2 UV,
    float Width,
    float Height,
    float Thickness,
    float CornerRadius,
    float2 Center,
    float Angle,
    float4 FillColor,
    float4 StrokeColor,
    float StrokeWidth,
    out float4 outColor
) {
    // PLAN:
    // 1. Recenter UV to (0,0) and apply rotation.
    // 2. Define the T-shape as two overlapping boxes (Top Bar + Vertical Stem).
    // 3. Clamp corner radius to ensure it fits within the smallest dimension.
    // 4. Compute SDFs for both parts using sdRoundBox logic.
    // 5. Combine using min() for a smooth union (seamless connection).
    // 6. Compute anti-aliased coverage for Fill and Stroke.
    // 7. Composite Stroke over Fill for final output.

    // 1. Transform Coordinates (Center & Rotate)
    float2 p = UV - Center;
    float c = cos(Angle);
    float s = sin(Angle);
    p = float2(p.x * c - p.y * s, p.x * s + p.y * c);

    // 2. Geometry Setup
    // T consists of a Top Bar and a Vertical Stem.
    // We center the total shape bounding box at (0,0) relative to the rotation pivot.
    // Top Bar is at the very top. Stem runs from bottom to top.
    
    // Half dimensions
    float halfW = Width * 0.5;
    float halfH = Height * 0.5;
    float halfThick = Thickness * 0.5;

    // 3. Clamp Corner Radius
    // Radius cannot be larger than half the thickness (or half width if very thin)
    float minDim = min(min(halfW, halfH), halfThick);
    float r = clamp(CornerRadius, 0.0, minDim);

    // 4. SDF Calculation
    
    // Vertical Stem: centered horizontally (x=0).
    // Height spans from -halfH to +halfH (full height).
    // This ensures it overlaps with the top bar for a seamless joint.
    float2 stemSize = float2(halfThick, halfH);
    float dStem = CTS_sdRoundBox(p, stemSize, r);

    // Top Bar: centered horizontally (x=0).
    // Vertical position: Top edge is at +halfH.
    // Center Y = Top Edge - Half Thickness = halfH - halfThick.
    float barCenterY = halfH - halfThick;
    float2 pBar = p - float2(0.0, barCenterY);
    float2 barSize = float2(halfW, halfThick);
    float dBar = CTS_sdRoundBox(pBar, barSize, r);

    // 5. Union
    // min(d1, d2) provides the union of the two shapes.
    float dist = min(dStem, dBar);

    // 6. Anti-aliasing & Masks
    float aa = fwidth(dist);
    
    // Fill Mask (inside the shape)
    // dist < 0 is inside. smoothstep gives transition at the edge.
    float fillAlpha = 1.0 - smoothstep(-aa, aa, dist);
    float4 fill = float4(FillColor.rgb, FillColor.a * fillAlpha);

    // Stroke Mask (band around the edge)
    // The stroke is centered on dist = 0.
    float halfStroke = StrokeWidth * 0.5;
    float strokeDist = abs(dist) - halfStroke;
    float strokeAlpha = 1.0 - smoothstep(-aa, aa, strokeDist);
    float4 stroke = float4(StrokeColor.rgb, StrokeColor.a * strokeAlpha);

    // 7. Composite (Stroke Over Fill)
    outColor = CTS_over(stroke, fill);
}