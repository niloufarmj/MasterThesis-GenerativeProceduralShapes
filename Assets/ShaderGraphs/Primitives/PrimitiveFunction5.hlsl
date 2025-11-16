#ifndef PI
#define PI 3.14159265359
#endif

//==========================================================================
//  Procedural Primitives – Color + Outline + Rotation (Dynamic Center)
//  Author: Niloufar Moradijam
//  File: SquareColorOutlineCenteredRotated.hlsl
//
//  Description
//  ------------------------------------------------------------------------
//  Centered, **rotatable** square with solid fill + outline, via SDF and
//  analytic AA. Adds a rotation angle so you can spin the square directly
//  from Shader Graph.
//
//  Minimal Interface (single RGBA output)
//  ------------------------------------------------------------------------
//  Function Name : SquareColorOutlineCenteredRotated01_float
//  Inputs  :
//      uv01        (float2) – standard 0..1 UV
//      halfSize    (float)  – half the side length in -1..1 units (e.g. 0.35)
//      center01    (float2) – square center in 0..1 UV (e.g. 0.5, 0.5)
//      angleRad    (float)  – rotation in **radians** (CCW). 0 = upright
//      fillColor   (float4) – RGBA fill
//      strokeColor (float4) – RGBA outline
//      strokeWidth (float)  – outline thickness (total), -1..1 units (e.g. 0.02)
//  Output :
//      outColor    (float4) – RGBA (straight alpha; A = coverage)
//
//  Usage (Shader Graph)
//  ------------------------------------------------------------------------
//  • Create a Custom Function (File) node.
//  • Source File  : this HLSL
//  • Function Name: SquareColorOutlineCenteredRotated01_float
//  • Wire UV to uv01, Vector2 to center01, Floats to halfSize / angleRad / strokeWidth,
//    and a Color to fillColor / strokeColor.
//  • Use Unlit/Transparent; connect RGB→BaseColor, A→Alpha.
//
//  Notes
//  ------------------------------------------------------------------------
//  • Coordinates: we recenter to 'center01' then scale to -1..1 for uniform sizing.
//  • Rotation: we rotate the *sampling point* by -angle (standard trick) before SDF.
//  • Stroke is composited OVER the fill so it stays visible.
//==========================================================================

// --- Helpers (minimal) ----------------------------------------------------

// SDF for an axis-aligned box centered at origin with half extents b
inline float sdBox(float2 p, float2 b)
{
    float2 q = abs(p) - b;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
}

// Straight-alpha "src over dst"
inline float4 over(float4 src, float4 dst)
{
    float a = src.a + dst.a * (1.0 - src.a);
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-8);
    return float4(c, a);
}

// --- Main -----------------------------------------------------------------
void SquareColorOutlineCenteredRotated01_float(
    float2 uv01, // 0..1 UV
    float halfSize, // -1..1 units (half side length)
    float2 center01, // 0..1 center
    float angleRad, // rotation in radians (CCW)
    float4 fillColor, // RGBA
    float4 strokeColor, // RGBA
    float strokeWidth, // -1..1 units (total thickness)
    out float4 outColor)
{
    // 1) Recenter to requested center and scale to -1..1 space
    float2 p = (uv01 - center01) * 2.0;

    // 2) Rotate the sampling point by -angle (so the shape appears rotated by +angle)
    float c = cos(angleRad);
    float s = sin(angleRad);
    float2 pr = float2(c * p.x + s * p.y,
                       -s * p.x + c * p.y);

    // 3) SDF to rotated square edge and analytic AA
    float d = sdBox(pr, float2(max(halfSize, 0.0), max(halfSize, 0.0)));
    float aa = fwidth(d);

    // 4) Fill coverage (inside the square)
    float fillMask = 1.0 - smoothstep(0.0, aa, d);
    float4 fillOut = float4(fillColor.rgb, saturate(fillColor.a) * fillMask);

    // 5) Stroke coverage (uniform band centered on the edge)
    float halfW = 0.5 * max(strokeWidth, 0.0);
    float edge = abs(d) - halfW;
    float strokeMask = 1.0 - smoothstep(0.0, aa, edge);
    float4 strokeOut = float4(strokeColor.rgb, saturate(strokeColor.a) * strokeMask);

    // 6) Composite: stroke OVER fill
    outColor = over(strokeOut, fillOut);
}

//==========================================================================
//  Procedural Primitives – Color + Outline + Rotation (Dynamic Center)
//  Author: Niloufar Moradijam
//  File: TriangleColorOutlineCenteredRotated.hlsl
//
//  Description
//  ------------------------------------------------------------------------
//  Centered, **rotatable** upright equilateral triangle with solid fill +
//  outline via SDF and analytic antialiasing. Rotation is controlled by a
//  single angle parameter (radians), exposed to Shader Graph.
//
//  Minimal Interface (single RGBA output)
//  ------------------------------------------------------------------------
//  Function Name : TriangleColorOutlineCenteredRotated01_float
//  Inputs  :
//      uv01        (float2) – standard 0..1 UV
//      radius      (float)  – **circumradius** (center → vertex) in -1..1 units
//      center01    (float2) – triangle center in 0..1 UV
//      angleRad    (float)  – rotation **in radians** (CCW). 0 = upright
//      fillColor   (float4) – RGBA fill
//      strokeColor (float4) – RGBA outline
//      strokeWidth (float)  – total outline thickness, -1..1 units
//  Output :
//      outColor    (float4) – RGBA (straight alpha; A = coverage)
//
//  Shader Graph (Custom Function - File)
//  ------------------------------------------------------------------------
//  • Source File  : this HLSL
//  • Function Name: TriangleColorOutlineCenteredRotated01_float
//  • Wire UV→uv01, Vector2→center01, Floats→radius/angleRad/strokeWidth,
//    and Colors→fillColor/strokeColor.
//  • Use Unlit/Transparent; plug RGB→BaseColor and A→Alpha.
//
//  Notes
//  ------------------------------------------------------------------------
//  • Coordinates: recenter to 'center01', scale to -1..1 for uniform sizing.
//  • Rotation: rotate the sampling point by -angle (so shape appears +angle).
//  • Stroke is composited OVER the fill.
//==========================================================================

// SDF for an upright equilateral triangle centered at origin,
// parameterized by circumradius r. d<0 inside, ~0 on edge.
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
void TriangleColorOutlineCenteredRotated01_float(
    float2 uv01, // 0..1 UV
    float radius, // -1..1 units (circumradius)
    float2 center01, // 0..1 center
    float angleRad, // radians (CCW)
    float4 fillColor, // RGBA
    float4 strokeColor, // RGBA
    float strokeWidth, // -1..1 units (total thickness)
    out float4 outColor)
{
    // 1) Recenter and scale to -1..1
    float2 p = (uv01 - center01) * 2.0;

    // 2) Rotate sampling point by -angle
    float c = cos(angleRad);
    float s = sin(angleRad);
    float2 pr = float2(c * p.x + s * p.y,
                       -s * p.x + c * p.y);

    // 3) SDF and analytic AA
    float d = sdEquilateralTriangle_Centered(pr, max(radius, 0.0));
    float aa = fwidth(d);

    // 4) Fill coverage (inside)
    float fillMask = 1.0 - smoothstep(0.0, aa, d);
    float4 fillOut = float4(fillColor.rgb, saturate(fillColor.a) * fillMask);

    // 5) Stroke coverage (band around edge)
    float halfW = 0.5 * max(strokeWidth, 0.0);
    float edge = abs(d) - halfW;
    float strokeMask = 1.0 - smoothstep(0.0, aa, edge);
    float4 strokeOut = float4(strokeColor.rgb, saturate(strokeColor.a) * strokeMask);

    // 6) Composite: stroke OVER fill
    outColor = over(strokeOut, fillOut);
}

//==========================================================================
//  Procedural Primitives – Color + Outline + Rotation (Dynamic Center)
//  Author: Niloufar Moradijam
//  File: RectangleColorOutlineCenteredRotated.hlsl
//
//  Description
//  ------------------------------------------------------------------------
//  Color-enabled, **rotatable** rectangle with solid fill + outline via SDF
//  and analytic AA. Dimensions are in 0..1 UV units (same as center01).
//  Rotation is a single angle (radians), CCW.
//
//  Minimal Interface (single RGBA output)
//  ------------------------------------------------------------------------
//  Function Name : RectangleColorOutlineCenteredRotated01_float
//  Inputs  :
//      uv01        (float2) – UV in 0..1
//      width       (float)  – full width in 0..1 UV units
//      height      (float)  – full height in 0..1 UV units
//      center01    (float2) – rectangle center in 0..1 UV
//      angleRad    (float)  – rotation in **radians** (CCW). 0 = axis-aligned
//      fillColor   (float4) – RGBA fill
//      strokeColor (float4) – RGBA outline
//      strokeWidth (float)  – outline thickness in 0..1 UV units (total)
//  Output :
//      outColor    (float4) – RGBA (straight alpha; A = coverage)
//
//  Shader Graph (Custom Function - File)
//  ------------------------------------------------------------------------
//  • Source File  : this HLSL
//  • Function Name: RectangleColorOutlineCenteredRotated01_float
//  • Wire UV→uv01, Vector2→center01, Floats→width/height/angleRad/strokeWidth,
//    and Colors→fillColor/strokeColor. Use Unlit/Transparent (RGB→BaseColor, A→Alpha).
//
//  Notes
//  ------------------------------------------------------------------------
//  • We rotate the *sampling point* by -angle so the shape appears rotated by +angle.
//  • Stroke is composited OVER the fill.
//==========================================================================

// SDF for an axis-aligned rectangle centered at origin.
// halfSize = (width/2, height/2) in the same units as p.
inline float sdRectangle(float2 p, float2 halfSize)
{
    float2 d = abs(p) - halfSize;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// --- Main -----------------------------------------------------------------
void RectangleColorOutlineCenteredRotated01_float(
    float2 uv01, // 0..1 UV
    float width, // full width in UV units
    float height, // full height in UV units
    float2 center01, // 0..1 center
    float angleRad, // radians (CCW)
    float4 fillColor, // RGBA
    float4 strokeColor, // RGBA
    float strokeWidth, // UV units (total thickness)
    out float4 outColor)
{
    // 1) Recenter in UV space (stay in 0..1 units)
    float2 p = uv01 - center01;

    // 2) Rotate sampling point by -angle (shape appears +angle)
    float c = cos(angleRad);
    float s = sin(angleRad);
    float2 pr = float2(c * p.x + s * p.y,
                       -s * p.x + c * p.y);

    // 3) SDF and analytic AA
    float2 halfSize = 0.5 * float2(max(width, 0.0), max(height, 0.0));
    float sd = sdRectangle(pr, halfSize);
    float aa = fwidth(sd);

    // 4) Fill coverage (inside)
    float fillMask = 1.0 - smoothstep(0.0, aa, sd);
    float4 fillOut = float4(fillColor.rgb, saturate(fillColor.a) * fillMask);

    // 5) Stroke coverage (band centered on edge)
    float halfW = 0.5 * max(strokeWidth, 0.0);
    float edge = abs(sd) - halfW;
    float strokeMask = 1.0 - smoothstep(0.0, aa, edge);
    float4 strokeOut = float4(strokeColor.rgb, saturate(strokeColor.a) * strokeMask);

    // 6) Composite: stroke OVER fill
    outColor = over(strokeOut, fillOut);
}

//==========================================================================
//  Procedural Primitives – Color + Outline + Rotation (Dynamic Center)
//  Author: Niloufar Moradijam
//  File: RhombusColorOutlineCenteredRotated.hlsl
//
//  Description
//  ------------------------------------------------------------------------
//  **Rotatable** rhombus (diamond) with solid fill + uniform outline,
//  using a convex-polygon SDF (exact Euclidean distance) and analytic AA.
//  All size parameters are in 0..1 UV units, consistent with center01.
//  Rotation is a single angle in radians (CCW).
//
//  Minimal Interface (single RGBA output)
//  ------------------------------------------------------------------------
//  Function Name : RhombusColorOutlineCenteredRotated01_float
//  Inputs  :
//      uv01        (float2) – UV in 0..1
//      a           (float)  – half horizontal diagonal (UV units)
//      b           (float)  – half vertical   diagonal (UV units)
//      center01    (float2) – rhombus center in 0..1 UV
//      angleRad    (float)  – rotation in **radians** (CCW). 0 = upright
//      fillColor   (float4) – RGBA fill
//      strokeColor (float4) – RGBA outline
//      strokeWidth (float)  – outline thickness in UV units (total)
//  Output :
//      outColor    (float4) – RGBA (straight alpha; A = coverage)
//
//  Shader Graph (Custom Function - File)
//  ------------------------------------------------------------------------
//  • Source File  : this HLSL
//  • Function Name: RhombusColorOutlineCenteredRotated01_float
//  • Wire: UV→uv01, Vector2→center01, Floats→a/b/angleRad/strokeWidth,
//          Colors→fillColor/strokeColor. Use Unlit/Transparent.
//  • Plug RGB→BaseColor and A→Alpha.
//
//  Notes
//  ------------------------------------------------------------------------
//  • We rotate the *sampling point* by -angle so the shape appears rotated
//    by +angle (standard SDF trick).
//  • Stroke is composited OVER the fill.
//==========================================================================

// --- Helpers --------------------------------------------------------------

// Exact SDF to a segment AB (Euclidean)
inline float sdSegment(float2 p, float2 a, float2 b)
{
    float2 pa = p - a, ba = b - a;
    float h = saturate(dot(pa, ba) / dot(ba, ba));
    return length(pa - ba * h);
}

// Exact SDF to a **convex** polygon given in CCW order.
// Returns d<0 inside, ~0 on edge, d>0 outside.
inline float sdConvexPoly4(float2 p, float2 v0, float2 v1, float2 v2, float2 v3)
{
    float2 v[4] = { v0, v1, v2, v3 };

    // min squared distance to edges
    float d2 = 1e20;
    // inside test accumulator (keeps the most positive signed half-space)
    float s = -1e20;

    [unroll]
    for (int i = 0; i < 4; ++i)
    {
        float2 a = v[i];
        float2 b = v[(i + 1) & 3];

        // distance to edge segment
        float sdE = sdSegment(p, a, b);
        d2 = min(d2, sdE * sdE);

        // signed distance to edge line (outward normal for CCW polygon)
        float2 e = b - a;
        float2 n = normalize(float2(e.y, -e.x)); // outward normal (CCW)
        float sEdge = dot(p - a, n);
        s = max(s, sEdge);
    }

    // outside: positive (distance to boundary); inside: negative
    return (s > 0.0) ? sqrt(d2) : -sqrt(d2);
}

// Guarded straight-alpha "src over dst" (minimizes redefinition risk)
#ifndef NM_OVER_HELPER
#define NM_OVER_HELPER
inline float4 nm_over(float4 src, float4 dst)
{
    float a = src.a + dst.a * (1.0 - src.a);
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-8);
    return float4(c, a);
}
#endif

// --- Main -----------------------------------------------------------------
void RhombusColorOutlineCenteredRotated01_float(
    float2 uv01, // 0..1 UV
    float a, // half horizontal diagonal (UV units)
    float b, // half vertical   diagonal (UV units)
    float2 center01, // 0..1 center
    float angleRad, // radians (CCW)
    float4 fillColor, // RGBA
    float4 strokeColor, // RGBA
    float strokeWidth, // UV units (total thickness)
    out float4 outColor)
{
    // 1) Recenter in UV space
    float2 p = uv01 - center01;

    // 2) Rotate sampling point by -angle (shape appears +angle)
    float c = cos(angleRad);
    float s = sin(angleRad);
    float2 pr = float2(c * p.x + s * p.y,
                       -s * p.x + c * p.y);

    // 3) Rhombus vertices (CCW) in rotated space
    float2 v0 = float2(a, 0.0);
    float2 v1 = float2(0.0, b);
    float2 v2 = float2(-a, 0.0);
    float2 v3 = float2(0.0, -b);

    // 4) True Euclidean signed distance and analytic AA
    float d = sdConvexPoly4(pr, v0, v1, v2, v3);
    float aa = fwidth(d);

    // 5) Fill coverage (inside polygon)
    float fillMask = 1.0 - smoothstep(0.0, aa, d);
    float4 fillOut = float4(fillColor.rgb, saturate(fillColor.a) * fillMask);

    // 6) Stroke coverage (uniform band around edge)
    float halfW = 0.5 * max(strokeWidth, 0.0);
    float edge = abs(d) - halfW;
    float strokeMask = 1.0 - smoothstep(0.0, aa, edge);
    float4 strokeOut = float4(strokeColor.rgb, saturate(strokeColor.a) * strokeMask);

    // 7) Composite: stroke OVER fill
    outColor = nm_over(strokeOut, fillOut);
}

//==========================================================================
//  Procedural Primitives – Color + Outline + Rotation (Dynamic Center)
//  Author: Niloufar Moradijam
//  File: EllipseColorOutlineCenteredRotated.hlsl
//
//  Description
//  ------------------------------------------------------------------------
//  **Rotatable** axis-aligned-in-local-space ellipse with solid fill +
//  uniform outline using an analytic pseudo-distance (F/||∇F||) and
//  fwidth-based antialiasing. Size params are in 0..1 UV units.
//  Rotation is a single CCW angle (radians), applied by rotating the
//  sampling point.
//
//  Minimal Interface (single RGBA output)
//  ------------------------------------------------------------------------
//  Function Name : EllipseColorOutlineCenteredRotated01_float
//  Inputs  :
//      uv01        (float2) – UV in 0..1
//      width       (float)  – full ellipse width  (UV units)
//      height      (float)  – full ellipse height (UV units)
//      center01    (float2) – ellipse center in 0..1 UV
//      angleRad    (float)  – rotation in **radians** (CCW). 0 = upright
//      fillColor   (float4) – RGBA fill
//      strokeColor (float4) – RGBA outline
//      strokeWidth (float)  – outline thickness in UV units (total)
//  Output :
//      outColor    (float4) – RGBA (straight alpha; A = coverage)
//
//  Shader Graph (Custom Function - File)
//  ------------------------------------------------------------------------
//  • Source File  : this HLSL
//  • Function Name: EllipseColorOutlineCenteredRotated01_float
//  • Wire UV→uv01, Vector2→center01, Floats→width/height/angleRad/strokeWidth,
//    Colors→fillColor/strokeColor. Use Unlit/Transparent (RGB→BaseColor, A→Alpha).
//==========================================================================

// --- Minimal helpers ------------------------------------------------------


// Signed pseudo-distance to an axis-aligned ellipse with half-axes (a,b).
inline float sdEllipseApprox(float2 p, float2 halfAxes)
{
    float a = max(halfAxes.x, 1e-8);
    float b = max(halfAxes.y, 1e-8);

    float aa = a * a;
    float bb = b * b;

    // Implicit ellipse: F = x^2/a^2 + y^2/b^2 - 1
    float x = p.x, y = p.y;
    float F = (x * x) / aa + (y * y) / bb - 1.0;

    // ||∇F|| = 2 * sqrt( x^2/a^4 + y^2/b^4 )
    float gradLen = 2.0 * sqrt((x * x) / (aa * aa) + (y * y) / (bb * bb));

    // Pseudo-distance with robust fallback near center
    return (gradLen > 1e-8) ? (F / gradLen) : -min(a, b);
}

// --- Main -----------------------------------------------------------------
void EllipseColorOutlineCenteredRotated01_float(
    float2 uv01, // 0..1 UV
    float width, // full width (UV units)
    float height, // full height (UV units)
    float2 center01, // 0..1 center
    float angleRad, // radians (CCW)
    float4 fillColor, // RGBA
    float4 strokeColor, // RGBA
    float strokeWidth, // UV units (total thickness)
    out float4 outColor)
{
    // 1) Recenter in UV space
    float2 p = uv01 - center01;

    // 2) Rotate sampling point by -angle (shape appears +angle)
    float c = cos(angleRad);
    float s = sin(angleRad);
    float2 pr = float2(c * p.x + s * p.y,
                       -s * p.x + c * p.y);

    // 3) Signed pseudo-distance and AA
    float2 halfAxes = 0.5 * float2(max(width, 0.0), max(height, 0.0));
    float d = sdEllipseApprox(pr, halfAxes);
    float aa = fwidth(d);

    // 4) Fill coverage
    float fillMask = 1.0 - smoothstep(0.0, aa, d);
    float4 fillOut = float4(fillColor.rgb, saturate(fillColor.a) * fillMask);

    // 5) Stroke coverage (band centered on edge)
    float halfW = 0.5 * max(strokeWidth, 0.0);
    float edge = abs(d) - halfW;
    float strokeMask = 1.0 - smoothstep(0.0, aa, edge);
    float4 strokeOut = float4(strokeColor.rgb, saturate(strokeColor.a) * strokeMask);

    // 6) Composite: stroke OVER fill
    outColor = nm_over(strokeOut, fillOut);
}

//==========================================================================
//  Procedural Primitives – Color + Outline + Rotation (Dynamic Center)
//  Author: Niloufar Moradijam
//  File: TrapezoidColorOutlineCenteredRotated.hlsl
//
//  Description
//  ------------------------------------------------------------------------
//  **Rotatable** isosceles trapezoid with solid fill + uniform outline,
//  using exact distance to edges + half-space sign and fwidth-based AA.
//  All size parameters are in 0..1 UV units (same space as center01).
//  Rotation is a single CCW angle (radians), applied by rotating the
//  sampling point.
//
//  Minimal Interface (single RGBA output)
//  ------------------------------------------------------------------------
//  Function Name : TrapezoidColorOutlineCenteredRotated01_float
//  Inputs  :
//      uv01        (float2) – UV in 0..1
//      widthBottom (float)  – full bottom width  (UV units)
//      widthTop    (float)  – full top width     (UV units)
//      height      (float)  – full height        (UV units)
//      center01    (float2) – trapezoid center in 0..1 UV
//      angleRad    (float)  – rotation in **radians** (CCW). 0 = upright
//      fillColor   (float4) – RGBA fill
//      strokeColor (float4) – RGBA outline
//      strokeWidth (float)  – outline thickness in UV units (total)
//  Output :
//      outColor    (float4) – RGBA (straight alpha; A = coverage)
//
//  Shader Graph (Custom Function - File)
//  ------------------------------------------------------------------------
//  • Source File  : this HLSL
//  • Function Name: TrapezoidColorOutlineCenteredRotated01_float
//  • Wire: UV→uv01, Vector2→center01, Floats→widthBottom/widthTop/height/
//           angleRad/strokeWidth, Colors→fillColor/strokeColor.
//  • Use Unlit/Transparent; connect RGB→BaseColor, A→Alpha.
//==========================================================================

#ifndef NM_OVER_HELPER
#define NM_OVER_HELPER
// Straight-alpha "src over dst" (guarded to avoid redefinition)
inline float4 nm_over(float4 src, float4 dst)
{
    float a  = src.a + dst.a * (1.0 - src.a);
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-8);
    return float4(c, a);
}
#endif

#ifndef NM_TRAPEZOID_HELPERS
#define NM_TRAPEZOID_HELPERS
inline float2 nm_perpRight(float2 e)
{
    return float2(e.y, -e.x);
} // right-hand perp

inline float nm_distPointToSegment(float2 p, float2 v0, float2 v1)
{
    float2 e = v1 - v0;
    float ee = max(dot(e, e), 1e-12);
    float t = clamp(dot(p - v0, e) / ee, 0.0, 1.0);
    float2 q = v0 + t * e;
    return length(p - q);
}

// Signed distance to an origin-centered, axis-aligned **isosceles** trapezoid
inline float nm_sdTrapezoid(float2 p, float widthBottom, float widthTop, float height)
{
    float a = 0.5 * widthTop; // half top width
    float b = 0.5 * widthBottom; // half bottom width
    float h = 0.5 * height; // half height

    // CCW vertices (bottom-left → bottom-right → top-right → top-left)
    float2 v0 = float2(-b, -h);
    float2 v1 = float2(b, -h);
    float2 v2 = float2(a, h);
    float2 v3 = float2(-a, h);

    // Edges and outward normals (CCW → right-hand perpendicular is outward)
    float2 E0 = v1 - v0, n0 = normalize(nm_perpRight(E0));
    float2 E1 = v2 - v1, n1 = normalize(nm_perpRight(E1));
    float2 E2 = v3 - v2, n2 = normalize(nm_perpRight(E2));
    float2 E3 = v0 - v3, n3 = normalize(nm_perpRight(E3));

    // Half-space distances (positive = outside for outward normals)
    float d0 = dot(n0, p - v0);
    float d1 = dot(n1, p - v1);
    float d2 = dot(n2, p - v2);
    float d3 = dot(n3, p - v3);

    // Inside if all <= 0 → sign = -1 inside, +1 outside
    float sgn = (max(max(d0, d1), max(d2, d3)) <= 0.0) ? -1.0 : 1.0;

    // Unsigned distance to boundary: min distance to edges
    float du = min(
        min(nm_distPointToSegment(p, v0, v1), nm_distPointToSegment(p, v1, v2)),
        min(nm_distPointToSegment(p, v2, v3), nm_distPointToSegment(p, v3, v0))
    );

    return du * sgn;
}
#endif // NM_TRAPEZOID_HELPERS

//------------------------------------------------------------------------------
// TrapezoidColorOutlineCenteredRotated01_float
//------------------------------------------------------------------------------
void TrapezoidColorOutlineCenteredRotated01_float(
    float2 uv01, // 0..1 UV
    float widthBottom, // full bottom width  (UV units)
    float widthTop, // full top width     (UV units)
    float height, // full height        (UV units)
    float2 center01, // 0..1 center
    float angleRad, // radians (CCW)
    float4 fillColor, // RGBA
    float4 strokeColor, // RGBA
    float strokeWidth, // UV units (total thickness)
    out float4 outColor)
{
    // 1) Recenter in UV space
    float2 p = uv01 - center01;

    // 2) Rotate sampling point by -angle so the shape appears rotated by +angle
    float c = cos(angleRad);
    float s = sin(angleRad);
    float2 pr = float2(c * p.x + s * p.y,
                       -s * p.x + c * p.y);

    // 3) Signed distance and AA factor
    float d = nm_sdTrapezoid(pr, widthBottom, widthTop, height);
    float aa = fwidth(d);

    // 4) Fill coverage
    float fillMask = 1.0 - smoothstep(0.0, aa, d);
    float4 fillOut = float4(fillColor.rgb, saturate(fillColor.a) * fillMask);

    // 5) Stroke coverage (uniform band around the edge)
    float halfW = 0.5 * max(strokeWidth, 0.0);
    float edge = abs(d) - halfW;
    float strokeMask = 1.0 - smoothstep(0.0, aa, edge);
    float4 strokeOut = float4(strokeColor.rgb, saturate(strokeColor.a) * strokeMask);

    // 6) Composite: stroke OVER fill
    outColor = nm_over(strokeOut, fillOut);
}

//==========================================================================
//  Procedural Primitives – Color + Outline + Rotation (Dynamic Center)
//  Author: Niloufar Moradijam
//  File: PentagonColorOutlineCenteredRotated.hlsl
//
//  Description
//  ------------------------------------------------------------------------
//  **Rotatable** regular pentagon with solid fill + configurable outline,
//  using a convex-polygon SDF (exact Euclidean edge distance + half-space
//  sign) and fwidth-based AA. Size params are in 0..1 UV units.
//  Rotation is a single CCW angle (radians), applied by rotating the
//  sampling point.
//
//  Minimal Interface (single RGBA output)
//  ------------------------------------------------------------------------
//  Function Name : PentagonColorOutlineCenteredRotated01_float
//  Inputs  :
//      uv01        (float2) – UV in 0..1
//      radius      (float)  – circumradius (center → vertex), UV units
//      center01    (float2) – pentagon center in 0..1 UV
//      angleRad    (float)  – rotation in **radians** (CCW). 0 = upright
//      fillColor   (float4) – RGBA fill
//      strokeColor (float4) – RGBA outline
//      strokeWidth (float)  – outline thickness in UV units (total)
//  Output :
//      outColor    (float4) – RGBA (straight alpha; A = coverage)
//
//  Shader Graph (Custom Function - File)
//  ------------------------------------------------------------------------
//  • Source File  : this HLSL
//  • Function Name: PentagonColorOutlineCenteredRotated01_float
//  • Wire UV→uv01, Vector2→center01, Floats→radius/angleRad/strokeWidth,
//    Colors→fillColor/strokeColor. Use Unlit/Transparent (RGB→BaseColor, A→Alpha).
//==========================================================================

#ifndef NM_OVER_HELPER
#define NM_OVER_HELPER
// Straight-alpha "src over dst" (guarded to avoid redefinition)
inline float4 nm_over(float4 src, float4 dst)
{
    float a  = src.a + dst.a * (1.0 - src.a);
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-8);
    return float4(c, a);
}
#endif


// Signed distance to an origin-centered **upright** regular pentagon (circumradius = r)
inline float nm_sdPentagon(float2 p, float r)
{
    float2 v[5];

    // 5 CCW vertices starting at top (0, +r)
    [unroll]
    for (int i = 0; i < 5; ++i)
    {
        float ang = 0.5 * PI + (2.0 * PI * i) / 5.0;
        v[i] = r * float2(cos(ang), sin(ang));
    }

    float maxHalf = -1e9; // max half-space (outside > 0)
    float minEdge = 1e9; // min unsigned distance to any edge

    [unroll]
    for (int i = 0; i < 5; ++i)
    {
        int j = (i + 1) % 5;
        float2 a = v[i], b = v[j];
        float2 e = b - a;
        float2 n = normalize(nm_perpRight(e)); // outward normal for CCW

        maxHalf = max(maxHalf, dot(p - a, n)); // >0 outside this edge
        minEdge = min(minEdge, nm_distPointToSegment(p, a, b));
    }

    // Inside if all half-spaces <= 0 → sign = -1 inside, +1 outside
    float sgn = (maxHalf <= 0.0) ? -1.0 : 1.0;
    return minEdge * sgn;
}

// --- Main -----------------------------------------------------------------
void PentagonColorOutlineCenteredRotated01_float(
    float2 uv01, // 0..1 UV
    float radius, // circumradius (UV units)
    float2 center01, // 0..1 center
    float angleRad, // radians (CCW)
    float4 fillColor, // RGBA
    float4 strokeColor, // RGBA
    float strokeWidth, // UV units (total thickness)
    out float4 outColor)
{
    // 1) Recenter in UV space
    float2 p = uv01 - center01;

    // 2) Rotate sampling point by -angle so the shape appears rotated by +angle
    float c = cos(angleRad);
    float s = sin(angleRad);
    float2 pr = float2(c * p.x + s * p.y,
                       -s * p.x + c * p.y);

    // 3) Signed distance and AA
    float d = nm_sdPentagon(pr, max(radius, 0.0));
    float aa = fwidth(d);

    // 4) Fill coverage
    float fillMask = 1.0 - smoothstep(0.0, aa, d);
    float4 fillOut = float4(fillColor.rgb, saturate(fillColor.a) * fillMask);

    // 5) Stroke coverage (uniform band around the edge)
    float halfW = 0.5 * max(strokeWidth, 0.0);
    float edge = abs(d) - halfW;
    float strokeMask = 1.0 - smoothstep(0.0, aa, edge);
    float4 strokeOut = float4(strokeColor.rgb, saturate(strokeColor.a) * strokeMask);

    // 6) Composite: stroke OVER fill
    outColor = nm_over(strokeOut, fillOut);
}

//==========================================================================
//  Procedural Primitives – Color + Outline + Rotation (Dynamic Center)
//  Author: Niloufar Moradijam
//  File: HexagonColorOutlineCenteredRotated.hlsl
//
//  Description
//  ------------------------------------------------------------------------
//  **Rotatable** flat-top regular hexagon with solid fill + configurable
//  outline, using a convex-polygon SDF (exact edge distance + half-space
//  sign) and fwidth-based AA. Size params are in 0..1 UV units.
//  Rotation is a single CCW angle (radians), applied by rotating the
//  sampling point.
//
//  Minimal Interface (single RGBA output)
//  ------------------------------------------------------------------------
//  Function Name : HexagonColorOutlineCenteredRotated01_float
//  Inputs  :
//      uv01        (float2) – UV in 0..1
//      radius      (float)  – circumradius (center→vertex), UV units
//      center01    (float2) – hexagon center in 0..1 UV
//      angleRad    (float)  – rotation in **radians** (CCW). 0 = flat-top
//      fillColor   (float4) – RGBA fill
//      strokeColor (float4) – RGBA outline
//      strokeWidth (float)  – outline thickness in UV units (total)
//  Output :
//      outColor    (float4) – RGBA (straight alpha; A = coverage)
//
//  Shader Graph (Custom Function - File)
//  ------------------------------------------------------------------------
//  • Source File  : this HLSL
//  • Function Name: HexagonColorOutlineCenteredRotated01_float
//  • Wire UV→uv01, Vector2→center01, Floats→radius/angleRad/strokeWidth,
//    Colors→fillColor/strokeColor. Use Unlit/Transparent (RGB→BaseColor, A→Alpha).
//==========================================================================


// Signed distance to an origin-centered **flat-top** regular hexagon
inline float nm_sdHexagon(float2 p, float r)
{

    // 6 CCW vertices, flat top (start at 30°)
    float2 v[6];
    [unroll]
    for (int i = 0; i < 6; ++i)
    {
        float ang = PI / 6.0 + (PI / 3.0) * i; // 30°, 90°, 150°, ...
        v[i] = r * float2(cos(ang), sin(ang));
    }

    float maxHalf = -1e9; // outside > 0
    float minEdge = 1e9; // min unsigned distance to edges

    [unroll]
    for (int i = 0; i < 6; ++i)
    {
        int j = (i + 1) % 6;
        float2 a = v[i], b = v[j];
        float2 e = b - a;
        float2 n = normalize(nm_perpRight(e)); // outward normal (CCW)

        maxHalf = max(maxHalf, dot(p - a, n)); // >0 outside edge
        minEdge = min(minEdge, nm_distPointToSegment(p, a, b));
    }

    // Inside if all half-spaces <= 0
    float sgn = (maxHalf <= 0.0) ? -1.0 : 1.0;
    return minEdge * sgn; // negative inside, positive outside
}

// --- Main -----------------------------------------------------------------
void HexagonColorOutlineCenteredRotated01_float(
    float2 uv01, // 0..1 UV
    float radius, // circumradius (UV units)
    float2 center01, // 0..1 center
    float angleRad, // radians (CCW)
    float4 fillColor, // RGBA
    float4 strokeColor, // RGBA
    float strokeWidth, // UV units (total thickness)
    out float4 outColor)
{
    // 1) Recenter in UV space
    float2 p = uv01 - center01;

    // 2) Rotate sampling point by -angle so the shape appears rotated by +angle
    float c = cos(angleRad);
    float s = sin(angleRad);
    float2 pr = float2(c * p.x + s * p.y,
                       -s * p.x + c * p.y);

    // 3) Signed distance and AA
    float d = nm_sdHexagon(pr, max(radius, 0.0));
    float aa = fwidth(d);

    // 4) Fill coverage
    float fillMask = 1.0 - smoothstep(0.0, aa, d);
    float4 fillOut = float4(fillColor.rgb, saturate(fillColor.a) * fillMask);

    // 5) Stroke coverage (uniform band around the edge)
    float halfW = 0.5 * max(strokeWidth, 0.0);
    float edge = abs(d) - halfW;
    float strokeMask = 1.0 - smoothstep(0.0, aa, edge);
    float4 strokeOut = float4(strokeColor.rgb, saturate(strokeColor.a) * strokeMask);

    // 6) Composite: stroke OVER fill
    outColor = nm_over(strokeOut, fillOut);
}

//==========================================================================
//  Procedural Primitives – Color + Outline + Rotation (Dynamic Center)
//  Author: Niloufar Moradijam
//  File: HeptagonColorOutlineCenteredRotated.hlsl
//
//  Description
//  ------------------------------------------------------------------------
//  **Rotatable** regular heptagon with solid fill + configurable outline,
//  using a convex-polygon SDF (exact edge distance + half-space sign) and
//  fwidth-based AA. Size params are in 0..1 UV units. Rotation is a single
//  CCW angle (radians) applied by rotating the sampling point.
//
//  Minimal Interface (single RGBA output)
//  ------------------------------------------------------------------------
//  Function Name : HeptagonColorOutlineCenteredRotated01_float
//  Inputs  :
//      uv01        (float2) – UV in 0..1
//      radius      (float)  – circumradius (center→vertex), UV units
//      center01    (float2) – heptagon center in 0..1 UV
//      angleRad    (float)  – rotation in **radians** (CCW). 0 = upright
//      fillColor   (float4) – RGBA fill
//      strokeColor (float4) – RGBA outline
//      strokeWidth (float)  – outline thickness in UV units (total)
//  Output :
//      outColor    (float4) – RGBA (straight alpha; A = coverage)
//
//  Shader Graph (Custom Function - File)
//  ------------------------------------------------------------------------
//  • Source File  : this HLSL
//  • Function Name: HeptagonColorOutlineCenteredRotated01_float
//  • Wire UV→uv01, Vector2→center01, Floats→radius/angleRad/strokeWidth,
//    Colors→fillColor/strokeColor. Use Unlit/Transparent (RGB→BaseColor, A→Alpha).
//==========================================================================


// Signed distance to an origin-centered, **upright** regular heptagon
inline float nm_sdHeptagon(float2 p, float r)
{
    const int N = 7;

    float2 v[N];

    // CCW vertices, start at "top" (angle = +90°)
    [unroll]
    for (int i = 0; i < N; ++i)
    {
        float ang = 0.5 * PI + (2.0 * PI * i) / (float) N;
        v[i] = r * float2(cos(ang), sin(ang));
    }

    float maxHalf = -1e9; // outside > 0
    float minEdge = 1e9; // min unsigned distance to edges

    [unroll]
    for (int i = 0; i < N; ++i)
    {
        int j = (i + 1) % N;
        float2 a = v[i], b = v[j];
        float2 e = b - a;
        float2 n = normalize(nm_perpRight(e)); // outward normal (CCW)

        maxHalf = max(maxHalf, dot(p - a, n));
        minEdge = min(minEdge, nm_distPointToSegment(p, a, b));
    }

    // Inside if all half-spaces <= 0
    float sgn = (maxHalf <= 0.0) ? -1.0 : 1.0;
    return minEdge * sgn; // negative inside, positive outside
}

// --- Main -----------------------------------------------------------------
void HeptagonColorOutlineCenteredRotated01_float(
    float2 uv01, // 0..1 UV
    float radius, // circumradius (UV units)
    float2 center01, // 0..1 center
    float angleRad, // radians (CCW)
    float4 fillColor, // RGBA
    float4 strokeColor, // RGBA
    float strokeWidth, // UV units (total thickness)
    out float4 outColor)
{
    // 1) Recenter in UV space
    float2 p = uv01 - center01;

    // 2) Rotate sampling point by -angle so the shape appears rotated by +angle
    float c = cos(angleRad);
    float s = sin(angleRad);
    float2 pr = float2(c * p.x + s * p.y,
                       -s * p.x + c * p.y);

    // 3) Signed distance and AA
    float d = nm_sdHeptagon(pr, max(radius, 0.0));
    float aa = fwidth(d);

    // 4) Fill coverage
    float fillMask = 1.0 - smoothstep(0.0, aa, d);
    float4 fillOut = float4(fillColor.rgb, saturate(fillColor.a) * fillMask);

    // 5) Stroke coverage (uniform band around the edge)
    float halfW = 0.5 * max(strokeWidth, 0.0);
    float edge = abs(d) - halfW;
    float strokeMask = 1.0 - smoothstep(0.0, aa, edge);
    float4 strokeOut = float4(strokeColor.rgb, saturate(strokeColor.a) * strokeMask);

    // 6) Composite: stroke OVER fill
    outColor = nm_over(strokeOut, fillOut);
}

//==========================================================================
//  Procedural Primitives – Color + Outline + Rotation (Dynamic Center)
//  Author: Niloufar Moradijam
//  File: OctagonColorOutlineCenteredRotated.hlsl
//
//  Description
//  ------------------------------------------------------------------------
//  **Rotatable** regular octagon (8 sides) with solid fill + configurable
//  outline, using a convex-polygon SDF (exact edge distance + half-space
//  sign) and fwidth-based analytic AA. Parameters are in 0..1 UV units.
//  Rotation is a single CCW angle (radians) applied by rotating the
//  sampling point.
//
//  Minimal Interface (single RGBA output)
//  ------------------------------------------------------------------------
//  Function Name : OctagonColorOutlineCenteredRotated01_float
//  Inputs  :
//      uv01        (float2) – UV in 0..1
//      radius      (float)  – circumradius (center→vertex), UV units
//      center01    (float2) – octagon center in 0..1 UV
//      angleRad    (float)  – rotation in **radians** (CCW). 0 = upright
//      fillColor   (float4) – RGBA fill
//      strokeColor (float4) – RGBA outline
//      strokeWidth (float)  – outline thickness in UV units (total)
//  Output :
//      outColor    (float4) – RGBA (straight alpha; A = coverage)
//
//  Shader Graph (Custom Function - File)
//  ------------------------------------------------------------------------
//  • Source File  : this HLSL
//  • Function Name: OctagonColorOutlineCenteredRotated01_float
//  • Wire UV→uv01, Vector2→center01, Floats→radius/angleRad/strokeWidth,
//    Colors→fillColor/strokeColor. Use Unlit/Transparent (RGB→BaseColor, A→Alpha).
//==========================================================================


// Signed distance to an origin-centered, **upright** regular octagon
inline float nm_sdOctagon(float2 p, float r)
{
    const int N = 8;

    float2 v[N];

    // CCW vertices, start at top (angle = +90°)
    [unroll]
    for (int i = 0; i < N; ++i)
    {
        float ang = 0.5 * PI + (2.0 * PI * i) / (float) N;
        v[i] = r * float2(cos(ang), sin(ang));
    }

    float maxHalf = -1e9; // outside > 0
    float minEdge = 1e9; // min unsigned distance to edges

    [unroll]
    for (int i = 0; i < N; ++i)
    {
        int j = (i + 1) % N;
        float2 a = v[i], b = v[j];
        float2 e = b - a;
        float2 n = normalize(nm_perpRight(e)); // outward (CCW)

        maxHalf = max(maxHalf, dot(p - a, n));
        minEdge = min(minEdge, nm_distPointToSegment(p, a, b));
    }

    // Inside if all half-spaces <= 0
    float sgn = (maxHalf <= 0.0) ? -1.0 : 1.0;
    return minEdge * sgn; // negative inside, positive outside
}

// --- Main -----------------------------------------------------------------
void OctagonColorOutlineCenteredRotated01_float(
    float2 uv01, // 0..1 UV
    float radius, // circumradius (UV units)
    float2 center01, // 0..1 center
    float angleRad, // radians (CCW)
    float4 fillColor, // RGBA
    float4 strokeColor, // RGBA
    float strokeWidth, // UV units (total thickness)
    out float4 outColor)
{
    // 1) Recenter in UV space
    float2 p = uv01 - center01;

    // 2) Rotate sampling point by -angle so the shape appears rotated by +angle
    float c = cos(angleRad);
    float s = sin(angleRad);
    float2 pr = float2(c * p.x + s * p.y,
                       -s * p.x + c * p.y);

    // 3) Signed distance and AA
    float d = nm_sdOctagon(pr, max(radius, 0.0));
    float aa = fwidth(d);

    // 4) Fill coverage
    float fillMask = 1.0 - smoothstep(0.0, aa, d);
    float4 fillOut = float4(fillColor.rgb, saturate(fillColor.a) * fillMask);

    // 5) Stroke coverage (uniform band around edge)
    float halfW = 0.5 * max(strokeWidth, 0.0);
    float edge = abs(d) - halfW;
    float strokeMask = 1.0 - smoothstep(0.0, aa, edge);
    float4 strokeOut = float4(strokeColor.rgb, saturate(strokeColor.a) * strokeMask);

    // 6) Composite: stroke OVER fill
    outColor = nm_over(strokeOut, fillOut);
}
