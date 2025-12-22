#ifndef PI
#define PI 3.14159265359
#endif

// --- Helpers ---

// 2D Rotation
inline float2 rotate2D(float2 p, float angle)
{
    float c = cos(angle);
    float s = sin(angle);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

// Signed Distance to a Box
inline float sdBox(float2 p, float2 b)
{
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// Signed Distance to a Triangle (vertices p0, p1, p2)
inline float sdTriangle(float2 p, float2 p0, float2 p1, float2 p2)
{
    float2 e0 = p1 - p0;
    float2 e1 = p2 - p1;
    float2 e2 = p0 - p2;

    float2 v0 = p - p0;
    float2 v1 = p - p1;
    float2 v2 = p - p2;

    float2 pq0 = v0 - e0 * clamp(dot(v0, e0) / dot(e0, e0), 0.0, 1.0);
    float2 pq1 = v1 - e1 * clamp(dot(v1, e1) / dot(e1, e1), 0.0, 1.0);
    float2 pq2 = v2 - e2 * clamp(dot(v2, e2) / dot(e2, e2), 0.0, 1.0);

    float s = sign(e0.x * e2.y - e0.y * e2.x);
    float2 d = min(min(float2(dot(pq0, pq0), s * (v0.x * e0.y - v0.y * e0.x)),
                       float2(dot(pq1, pq1), s * (v1.x * e1.y - v1.y * e1.x))),
                       float2(dot(pq2, pq2), s * (v2.x * e2.y - v2.y * e2.x)));

    return -sqrt(d.x) * sign(d.y);
}

// Alpha Blending (Src Over Dst)
inline float4 arrow_over(float4 src, float4 dst)
{
    float a = src.a + dst.a * (1.0 - src.a);
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-8);
    return float4(c, a);
}

// --- Main Function ---
// PLAN:
// 1) Center UVs and apply rotation.
// 2) Offset UVs to visually center the arrow based on its dimensions.
// 3) Create SDF for the Shaft (Box) positioned below the origin.
// 4) Create SDF for the Head (Triangle) positioned above the origin.
// 5) Combine SDFs using union (min).
// 6) Apply Fill and Stroke logic using smoothstep AA.
// 7) Output blended color.

void ArrowShape_float(float2 UV, float2 Center, float RotationRad, 
                     float2 ShaftSize, // x=Width, y=Length
                     float2 HeadSize,  // x=Width, y=Length
                     float4 FillColor, float4 StrokeColor, float StrokeWidth,
                     out float4 outColor)
{
    // 1) Center and Rotate
    float2 p = UV - Center;
    p = rotate2D(p, -RotationRad);

    // 2) Visual Centering
    // Total geometry Y range: [-ShaftSize.y, HeadSize.y]
    // Midpoint Y = (HeadSize.y - ShaftSize.y) * 0.5
    // We shift p.y down by this amount so the visual center is at (0,0)
    float midY = (HeadSize.y - ShaftSize.y) * 0.5;
    p.y -= midY;

    // 3) Shaft SDF
    // Shaft goes from y=0 down to y=-ShaftSize.y
    // Box Center relative to p: (0, -ShaftSize.y * 0.5)
    // Box HalfExtents: (ShaftSize.x * 0.5, ShaftSize.y * 0.5)
    float2 shaftHalfSize = float2(max(ShaftSize.x, 0.0) * 0.5, max(ShaftSize.y, 0.0) * 0.5);
    float2 shaftCenter = float2(0.0, -shaftHalfSize.y * 2.0 + shaftHalfSize.y); // = -shaftHalfSize.y
    float dShaft = sdBox(p - shaftCenter, shaftHalfSize);

    // 4) Head SDF (Triangle)
    // Vertices relative to p (with join at y=0):
    // Top: (0, HeadSize.y)
    // BottomRight: (HeadSize.x/2, 0)
    // BottomLeft: (-HeadSize.x/2, 0)
    float hw = max(HeadSize.x, 0.0) * 0.5;
    float hl = max(HeadSize.y, 0.0);
    float2 t1 = float2(0.0, hl);
    float2 t2 = float2(hw, 0.0);
    float2 t3 = float2(-hw, 0.0);
    float dHead = sdTriangle(p, t1, t2, t3);

    // 5) Combine (Union)
    float dist = min(dShaft, dHead);

    // 6) Rendering
    float aa = fwidth(dist);
    
    // Fill
    float fillMask = 1.0 - smoothstep(-aa, aa, dist);
    float4 fill = float4(FillColor.rgb, FillColor.a * fillMask);

    // Stroke
    float halfStroke = max(StrokeWidth, 0.0) * 0.5;
    float strokeDist = abs(dist) - halfStroke;
    float strokeMask = 1.0 - smoothstep(-aa, aa, strokeDist);
    float4 stroke = float4(StrokeColor.rgb, StrokeColor.a * strokeMask);

    // 7) Composite Stroke Over Fill
    outColor = arrow_over(stroke, fill);
}