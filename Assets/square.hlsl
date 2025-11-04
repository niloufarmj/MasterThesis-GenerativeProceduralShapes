//==========================================================================
//  Procedural Primitive – Square (Rounded) + Color + Outline + Rotation
//  Author: Niloufar Moradijam
//  File: SquareRoundedColorOutlineCenteredRotated.hlsl
//
//  Description
//  ------------------------------------------------------------------------
//  Centered, rotatable **rounded square** (uniform rounded corners) with
//  solid fill + outline via SDF and analytic AA. Corner rounding affects
//  the shape’s silhouette (NOT the stroke).
//
//  Minimal Shader Graph Interface (single RGBA output)
//  ------------------------------------------------------------------------
//  Function Name : SquareRoundedColorOutlineCenteredRotated01_float
//  Inputs  :
//      uv01         (float2) – standard 0..1 UV
//      halfSize     (float)  – half the side length in -1..1 units (e.g. 0.35)
//      cornerRadius (float)  – **shape** corner radius (in -1..1 units)
//      center01     (float2) – shape center in 0..1 UV (e.g. 0.5, 0.5)
//      angleRad     (float)  – rotation in radians (CCW). 0 = axis-aligned
//      fillColor    (float4) – RGBA fill
//      strokeColor  (float4) – RGBA outline
//      strokeWidth  (float)  – outline thickness (total), -1..1 units
//  Output :
//      outColor     (float4) – RGBA (straight alpha; A = coverage)
//
//  Notes
//  ------------------------------------------------------------------------
//  • Coordinates: recenter to 'center01' then scale to -1..1 for uniform sizing.
//  • Rotation: rotate the *sampling point* by -angle before SDF (standard trick).
//  • Corner radius is clamped to [0, halfSize] to stay valid.
//  • Stroke is composited OVER the fill.
//==========================================================================

// --- SDF helpers (minimal) ------------------------------------------------

// sdBox: signed distance to an axis-aligned box centered at origin
inline float sdBox(float2 p, float2 b)
{
    float2 q = abs(p) - b;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
}

// sdRoundBox (uniform corner radius): “round” a box by offsetting its SDF
// Equivalent form: sdBox(p, b - r) - r; (clamp r <= min(b.x,b.y) in caller)
inline float sdRoundBox(float2 p, float2 b, float r)
{
    return sdBox(p, b - r) - r;
}

// Straight-alpha "src over dst"
inline float4 over(float4 src, float4 dst)
{
    float a = src.a + dst.a * (1.0 - src.a);
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-8);
    return float4(c, a);
}

// --- Main -----------------------------------------------------------------
void SquareRoundedColorOutlineCenteredRotated01_float(
    float2 uv01, // 0..1 UV
    float halfSize, // -1..1 units (half side length)
    float cornerRadius, // -1..1 units (shape border radius)
    float2 center01, // 0..1 center
    float angleRad, // radians (CCW)
    float4 fillColor, // RGBA
    float4 strokeColor, // RGBA
    float strokeWidth, // -1..1 units (total thickness)
    out float4 outColor)
{
    // 1) Recenter to requested center and scale to -1..1
    float2 p = (uv01 - center01) * 2.0;

    // 2) Rotate sampling point by -angle (so shape appears rotated by +angle)
    float c = cos(angleRad);
    float s = sin(angleRad);
    float2 pr = float2(c * p.x + s * p.y,
                       -s * p.x + c * p.y);

    // 3) Rounded-square SDF
    float hs = max(halfSize, 0.0);
    float r = clamp(cornerRadius, 0.0, hs); // keep radius valid
    float d = sdRoundBox(pr, float2(hs, hs), r); // d<0 inside, ~0 edge

    // 4) Analytic AA width
    float aa = fwidth(d);

    // 5) Fill coverage (inside the rounded square)
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