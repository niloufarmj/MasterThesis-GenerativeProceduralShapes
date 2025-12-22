#ifndef PI
#define PI 3.14159265359
#endif

// --- Helpers ---

// Signed distance to an axis-aligned box centered at origin.
// b is half-extents (width/2, height/2).
inline float sdBox(float2 p, float2 b)
{
    float2 q = abs(p) - b;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
}

// Signed distance to a rounded box.
// b is outer half-extents, r is corner radius.
// Conceptually: shrink box by r, then expand field by r.
inline float sdRoundedBox(float2 p, float2 b, float r)
{
    return sdBox(p, b - r) - r;
}

// Alpha compositing: Source Over Destination (pre-multiplied alpha logic)
inline float4 composite_over(float4 src, float4 dst)
{
    float a = src.a + dst.a * (1.0 - src.a);
    // Avoid division by zero in color normalization
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-8);
    return float4(c, a);
}

// --- Main Function ---
/*
 PLAN:
 1) Recenter UV coordinate (p = UV - Center).
 2) Rotate p by negative Rotation angle.
 3) Clamp CornerRadius so it doesn't exceed half the smallest dimension.
 4) Calculate SDF using sdRoundedBox.
 5) Calculate Fill Mask (internal area).
 6) Calculate Border Mask (outline/stroke area).
 7) Composite Border over Fill.
*/
void RectangleBorderRadius_float(
    float2 UV,
    float Width,
    float Height,
    float CornerRadius,
    float2 Center,
    float Rotation,
    float4 FillColor,
    float4 BorderColor,
    float BorderThickness,
    out float4 outColor)
{
    // 1) Recenter
    float2 p = UV - Center;

    // 2) Rotate (rotate sampling point by -angle)
    float c = cos(Rotation);
    float s = sin(Rotation);
    p = float2(c * p.x + s * p.y, -s * p.x + c * p.y);

    // 3) Setup Dimensions
    float2 halfSize = float2(max(Width, 0.0), max(Height, 0.0)) * 0.5;
    // Clamp radius to ensure valid shape (cannot be larger than the smallest half-dimension)
    float r = clamp(CornerRadius, 0.0, min(halfSize.x, halfSize.y));

    // 4) SDF Calculation
    float dist = sdRoundedBox(p, halfSize, r);
    
    // Analytic Anti-Aliasing width
    float aa = fwidth(dist);

    // 5) Fill Layer
    // dist < 0 is inside. smoothstep(0, aa, dist) gives 0 inside, 1 outside.
    float fillAlpha = 1.0 - smoothstep(0.0, aa, dist);
    float4 fillLayer = float4(FillColor.rgb, FillColor.a * fillAlpha);

    // 6) Border Layer
    // We want a band of width 'BorderThickness' centered on the edge (dist = 0)
    float halfBorder = max(BorderThickness, 0.0) * 0.5;
    float borderDist = abs(dist) - halfBorder;
    float borderAlpha = 1.0 - smoothstep(0.0, aa, borderDist);
    float4 borderLayer = float4(BorderColor.rgb, BorderColor.a * borderAlpha);

    // 7) Composite
    outColor = composite_over(borderLayer, fillLayer);
}