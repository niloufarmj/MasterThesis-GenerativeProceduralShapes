#ifndef PI
#define PI 3.14159265359
#endif

// Helper: SDF for an oriented box (line segment with thickness)
// p: sampling point
// a, b: start and end points of the center line
// th: full thickness of the box
float sdOrientedBox_N7(float2 p, float2 a, float2 b, float th)
{
    float l = length(b - a);
    float2 d = (b - a) / max(l, 1e-6); // Normalized direction
    float2 q = p - (a + b) * 0.5;      // Translate to center
    // Rotate to align with segment (dot with d for x, dot with perp(d) for y)
    q = float2(dot(q, d), dot(q, float2(-d.y, d.x)));
    // SDF for axis-aligned box in rotated space
    q = abs(q) - float2(l * 0.5, th * 0.5);
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
}

// Helper: Alpha blending (Source Over Destination)
float4 over_N7(float4 src, float4 dst)
{
    float a = src.a + dst.a * (1.0 - src.a);
    // Avoid divide by zero
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-6);
    return float4(c, a);
}

// MAIN FUNCTION: Cartoon Number 7 Shape
// User Request: A cartoon number 7 shape with adjustable size, width, height, thickness, outline, and dynamic corner radius.
// PLAN:
// 1. Center UVs.
// 2. Define key structural points (Top-Left, Top-Right, Bottom) based on Width/Height/Slant.
// 3. Compute 'effective thickness' to compensate for corner rounding (so radius doesn't bloat the shape).
// 4. Calculate SDFs for the Top Bar and Diagonal Leg using oriented boxes.
// 5. Combine them using min() for a sharp union, then subtract CornerRadius for rounded edges.
// 6. Generate Fill and Stroke masks using smoothstep AA.
// 7. Composite Stroke over Fill.
void CartoonNumberSevenShape_float(float2 UV, float Width, float Height, float Thickness, float CornerRadius, float LegSlant, float4 FillColor, float4 StrokeColor, float StrokeWidth, out float4 outColor)
{
    // 1. Center coordinates
    float2 p = UV - 0.5;

    // 2. Define Skeleton Points
    // Top Bar goes from Top-Left (A) to Top-Right (B)
    // Leg goes from Top-Right (B) to Bottom (C)
    float halfW = Width * 0.5;
    float halfH = Height * 0.5;
    
    float2 A = float2(-halfW, halfH);
    float2 B = float2(halfW, halfH);
    
    // Calculate bottom point X based on Slant
    // LegSlant 0.0 = Vertical leg, 1.0 = Diagonal roughly matching width
    // We shift the bottom point to the left relative to B
    float bottomX = halfW - (Width * LegSlant);
    float2 C = float2(bottomX, -halfH);

    // 3. Adjust thickness for rounding
    // We want the final visual thickness to match 'Thickness' parameter.
    // Since we subtract CornerRadius later (which expands the shape), we shrink the core box thickness.
    // Clamp radius to not exceed half thickness.
    float r = clamp(CornerRadius, 0.0, Thickness * 0.5);
    float coreTh = max(0.0, Thickness - 2.0 * r);

    // 4. Compute SDFs
    float dBar = sdOrientedBox_N7(p, A, B, coreTh);
    float dLeg = sdOrientedBox_N7(p, B, C, coreTh);

    // 5. Combine and Round
    // Union (min) creates the connected shape
    // Subtracting r rounds the sharp outer corners and caps
    float dShape = min(dBar, dLeg) - r;

    // 6. Anti-aliasing and Masks
    float aa = fwidth(dShape);
    
    // Fill Mask (inside the shape)
    float fillMask = 1.0 - smoothstep(0.0, aa, dShape);
    float4 fillLayer = float4(FillColor.rgb, FillColor.a * fillMask);

    // Stroke Mask (band around the edge)
    // We center the stroke on the edge of the fill shape
    float halfStroke = StrokeWidth * 0.5;
    float distToEdge = abs(dShape);
    float strokeMask = 1.0 - smoothstep(halfStroke, halfStroke + aa, distToEdge);
    float4 strokeLayer = float4(StrokeColor.rgb, StrokeColor.a * strokeMask);

    // 7. Composite Output (Stroke over Fill)
    outColor = over_N7(strokeLayer, fillLayer);
}