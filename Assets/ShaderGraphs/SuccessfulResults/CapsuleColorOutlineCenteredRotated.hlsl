#ifndef PI
#define PI 3.14159265359
#endif

// Helper: Straight-alpha composite (Source Over Destination)
inline float4 capsule_over(float4 src, float4 dst)
{
    float a = src.a + dst.a * (1.0 - src.a);
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-8);
    return float4(c, a);
}

void CapsuleColorOutlineCenteredRotated_float(
    float2 UV,
    float Length,
    float Radius,
    float2 Center,
    float Rotation,
    float4 FillColor,
    float4 StrokeColor,
    float StrokeWidth,
    out float4 Out)
{
    // PLAN:
    // 1) Translate UV to be relative to Center.
    // 2) Rotate the coordinate system so the capsule is vertical.
    // 3) Compute SDF for a vertical line segment of length 'Length'.
    // 4) Subtract 'Radius' to form the capsule shape.
    // 5) Apply analytic anti-aliasing (AA) for smooth edges.
    // 6) Compute Fill and Stroke layers.
    // 7) Composite Stroke over Fill.

    // 1) Recenter
    float2 p = UV - Center;

    // 2) Rotate (rotate sample point by -angle)
    float c = cos(Rotation);
    float s = sin(Rotation);
    p = float2(c * p.x + s * p.y, -s * p.x + c * p.y);

    // 3) Vertical Segment SDF
    // The segment extends from -Length/2 to +Length/2 along the Y axis.
    float halfLen = max(Length, 0.0) * 0.5;
    
    // Clamp the Y coordinate to the segment range.
    // This effectively finds the Y-distance to the closest point on the segment.
    // We modify p.y in place to represent the vector from the closest point on the segment.
    p.y -= clamp(p.y, -halfLen, halfLen);

    // 4) Capsule SDF
    // p now represents the vector from the segment axis to the sample point.
    // length(p) is the Euclidean distance to the segment.
    // Subtract Radius to get signed distance (negative inside, positive outside).
    float d = length(p) - max(Radius, 0.0);

    // 5) Analytic AA
    // fwidth gives the screen-space rate of change of the distance field.
    float aa = fwidth(d);

    // 6) Fill Layer
    // Smoothstep creates a smooth anti-aliased edge at d=0.
    float fillAlpha = 1.0 - smoothstep(0.0, aa, d);
    float4 fillLayer = float4(FillColor.rgb, saturate(FillColor.a) * fillAlpha);

    // 7) Stroke Layer
    // The stroke is a band centered on the shape's boundary.
    float halfStroke = max(StrokeWidth, 0.0) * 0.5;
    float strokeDist = abs(d) - halfStroke;
    float strokeAlpha = 1.0 - smoothstep(0.0, aa, strokeDist);
    float4 strokeLayer = float4(StrokeColor.rgb, saturate(StrokeColor.a) * strokeAlpha);

    // 8) Composition
    Out = capsule_over(strokeLayer, fillLayer);
}