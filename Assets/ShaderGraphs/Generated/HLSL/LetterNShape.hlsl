#ifndef PI
#define PI 3.14159265359
#endif

// Helper: Signed Distance to a Box
// p: point relative to center, b: half-extents (width/2, height/2)
float sdBox_N(float2 p, float2 b) {
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// Helper: Signed Distance to an Oriented Box (Segment with thickness)
// p: point, a: start, b: end, th: half-thickness
float sdOrientedBox_N(float2 p, float2 a, float2 b, float th) {
    float l = length(b - a);
    if (l < 0.0001) return length(p - a) - th;
    float2 d = (b - a) / l;
    float2 q = (p - (a + b) * 0.5);
    // Rotate q to align with the segment vector
    q = mul(float2x2(d.x, d.y, -d.y, d.x), q);
    // q.x is along the segment, q.y is perpendicular
    // Segment length is l, so box width is l/2. Thickness is th.
    return sdBox_N(q, float2(l * 0.5, th));
}

// Helper: Composite Color (Source Over Destination) for Straight Alpha
float4 compositeColors_N(float4 src, float4 dst) {
    float outA = src.a + dst.a * (1.0 - src.a);
    float3 outRGB = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(outA, 0.0001);
    return float4(outRGB, outA);
}

// Main Function: Letter N Shape
// Plan:
// 1. Recenter UV coordinates and apply global rotation.
// 2. Define the N geometry using three segments:
//    - Left Vertical Leg, Right Vertical Leg (controlled by Width/Height)
//    - Diagonal Stroke connecting Top-Left to Bottom-Right.
// 3. Combine segments using Union (min).
// 4. Apply Corner Rounding by subtracting radius from SDF.
// 5. Generate Fill and Outline with smooth transitions.
void LetterNShape_float(
    float2 UV,
    float Width,
    float Height,
    float ShapeThickness,
    float CornerRadius,
    float2 Center,
    float RotationRadians,
    float4 FillColor,
    float4 OutlineColor,
    float OutlineWidth,
    out float4 outColor)
{
    // 1. Coordinate Setup
    float2 p = UV - Center;
    
    // Apply Rotation
    float c = cos(RotationRadians);
    float s = sin(RotationRadians);
    p = float2(p.x * c - p.y * s, p.x * s + p.y * c);

    // 2. Geometry Definitions
    // hw: Half-Width (distance from center to leg centers)
    // hh: Half-Height
    float hw = Width * 0.5;
    float hh = Height * 0.5;
    float hThick = ShapeThickness * 0.5;

    // Left Leg: Vertical box at x = -hw
    // Box half-size: (thickness/2, height/2)
    float dLeft = sdBox_N(p - float2(-hw, 0.0), float2(hThick, hh));

    // Right Leg: Vertical box at x = +hw
    float dRight = sdBox_N(p - float2(hw, 0.0), float2(hThick, hh));

    // Diagonal: Oriented box connecting Top-Left (-hw, hh) to Bottom-Right (hw, -hh)
    // This implicitly handles the 'diagonal angle' based on Width/Height ratio.
    float dDiag = sdOrientedBox_N(p, float2(-hw, hh), float2(hw, -hh), hThick);

    // 3. Combine Segments (Union)
    float d = min(dLeft, min(dRight, dDiag));

    // 4. Corner Rounding
    // Subtract radius to round external corners
    d -= CornerRadius;

    // 5. Rendering / Anti-Aliasing
    float aa = fwidth(d);
    
    // Fill Mask (d < 0 is inside)
    float fillMask = 1.0 - smoothstep(-aa, aa, d);
    float4 fillLayer = float4(FillColor.rgb, FillColor.a * fillMask);

    // Outline Mask (distance to edge < outlineWidth/2)
    float halfOutline = OutlineWidth * 0.5;
    float outlineEdge = abs(d) - halfOutline;
    float outlineMask = 1.0 - smoothstep(-aa, aa, outlineEdge);
    float4 outlineLayer = float4(OutlineColor.rgb, OutlineColor.a * outlineMask);

    // Composite: Outline draws over Fill
    outColor = compositeColors_N(outlineLayer, fillLayer);
}