//==========================================================================
//  Procedural Primitive – Triangle (Rounded) + Color + Outline + Rotation
//  Author: Niloufar Moradijam
//  File: TriangleRoundedColorOutlineCenteredRotated.hlsl
//
//  Description
//  ------------------------------------------------------------------------
//  Centered, rotatable **rounded equilateral triangle** (uniform corner
//  radius) with solid fill + outline via SDF and analytic AA. The corner
//  radius modifies the triangle silhouette (NOT the stroke).
//
//  Minimal Shader Graph Interface (single RGBA output)
//  ------------------------------------------------------------------------
//  Function Name : TriangleRoundedColorOutlineCenteredRotated01_float
//  Inputs  :
//      uv01         (float2) – standard 0..1 UV
//      radius       (float)  – circumradius (center→vertex), -1..1 units
//      cornerRadius (float)  – shape corner radius (in -1..1 units)
//      center01     (float2) – triangle center in 0..1 UV
//      angleRad     (float)  – rotation in radians (CCW). 0 = upright
//      fillColor    (float4) – RGBA fill
//      strokeColor  (float4) – RGBA outline
//      strokeWidth  (float)  – outline thickness (total), -1..1 units
//  Output :
//      outColor     (float4) – RGBA (straight alpha; A = coverage)
//
//  Shader Graph (Custom Function - File)
//  ------------------------------------------------------------------------
//  • Source File  : this HLSL
//  • Function Name: TriangleRoundedColorOutlineCenteredRotated01_float
//  • Wire UV→uv01, Vector2→center01, Floats→radius/cornerRadius/angleRad/
//    strokeWidth, and Colors→fillColor/strokeColor.
//  • Use Unlit/Transparent; plug RGB→BaseColor and A→Alpha.
//
//  Notes
//  ------------------------------------------------------------------------
//  • Coordinates: recenter to 'center01', scale to -1..1 for uniform sizing.
//  • Rotation: rotate the sampling point by -angle (so shape appears +angle).
//  • Rounded silhouette: analogous to round box -> use (radius - r) then -r.
//    d_round = sdTriangle(p, radius - r) - r, with r clamped to [0, radius].
//  • Stroke is composited OVER the fill.
//==========================================================================

// Straight-alpha "src over dst"
inline float4 over(float4 src, float4 dst)
{
    float a = src.a + dst.a * (1.0 - src.a);
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-8);
    return float4(c, a);
}

// SDF for upright equilateral triangle centered at origin,
// parameterized by circumradius r. d<0 inside, ~0 at edge.
inline float sdEquilateralTriangle_Centered(float2 p, float r)
{
    const float k = 1.7320508; // sqrt(3)
    p.x = abs(p.x) - r;
    p.y = p.y + r / k;
    if (p.x + k * p.y > 0.0)
        p = float2(p.x - k * p.y, -k * p.x - p.y) * 0.5;
    p.x -= clamp(p.x, -2.0 * r, 0.0);
    return -length(p) * sign(p.y);
}

// --- Main -----------------------------------------------------------------
void TriangleRoundedColorOutlineCenteredRotated01_float(
    float2 uv01, // 0..1 UV
    float radius, // -1..1 units (circumradius)
    float cornerRadius, // -1..1 units (shape corner radius)
    float2 center01, // 0..1 center
    float angleRad, // radians (CCW)
    float4 fillColor, // RGBA
    float4 strokeColor, // RGBA
    float strokeWidth, // -1..1 units (total thickness)
    out float4 outColor)
{
    // 1) Recenter and scale to -1..1
    float2 p = (uv01 - center01) * 2.0;

    // 2) Rotate sampling point by -angle (shape appears rotated by +angle)
    float c = cos(angleRad);
    float s = sin(angleRad);
    float2 pr = float2(c * p.x + s * p.y,
                       -s * p.x + c * p.y);

    // 3) Rounded-triangle SDF:
    //    shrink base triangle by 'r' and then subtract 'r' (inset rounding)
    float R = max(radius, 0.0);
    float r = clamp(cornerRadius, 0.0, R);
    float d = sdEquilateralTriangle_Centered(pr, R - r) - r; // d<0 inside

    // 4) Analytic AA width
    float aa = fwidth(d);

    // 5) Fill coverage (inside)
    float fillMask = 1.0 - smoothstep(0.0, aa, d);
    float4 fillOut = float4(fillColor.rgb, saturate(fillColor.a) * fillMask);

    // 6) Stroke coverage (uniform band centered on the rounded edge)
    float halfW = 0.5 * max(strokeWidth, 0.0);
    float edge = abs(d) - halfW;
    float strokeMask = 1.0 - smoothstep(0.0, aa, edge);
    float4 strokeOut = float4(strokeColor.rgb, saturate(strokeColor.a) * strokeMask);

    // 7) Composite: stroke OVER fill
    outColor = over(strokeOut, fillOut);
}
