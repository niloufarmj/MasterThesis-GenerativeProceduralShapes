//==========================================================================
//  Procedural Primitives – Color + Outline (Dynamic Center)
//  Author: Niloufar Moradijam
//  File: CircleColorOutline_Centered.hlsl
//
//  Description
//  ------------------------------------------------------------------------
//  Centered circle with fill + outline using an SDF and analytic AA.
//  - Dynamic center via `center01` (0..1 UV space).
//  - Radius and stroke width measured in the post-centered -1..1 space.
//  - Minimal single-output RGBA (straight alpha), ready for Shader Graph.
//
//  Shader Graph (Custom Function - File)
//  ------------------------------------------------------------------------
//  Function Name : CircleColorOutlineCentered01_float
//  Inputs  :
//      uv01        (float2) – standard 0..1 UV
//      radius      (float)  – circle radius (units of -1..1 space; e.g. 0.35)
//      center01    (float2) – circle center in 0..1 UV (e.g. 0.5,0.5)
//      fillColor   (float4) – RGBA for the filled area
//      strokeColor (float4) – RGBA for the outline
//      strokeWidth (float)  – outline thickness (total, centered on edge),
//                              in -1..1 units (e.g. 0.02)
//  Output :
//      outColor    (float4) – RGBA (straight alpha)
//
//  Usage Notes
//  ------------------------------------------------------------------------
//  • Wire uv01 from your UV, center01 from a Vector2, and expose radius and
//    strokeWidth as floats in Shader Graph.
//  • The function composites the stroke OVER the fill (so the outline is
//    visible even if the fill is opaque).
//==========================================================================

#ifndef PI
#define PI 3.14159265359
#endif

// Signed distance to a circle at the origin in -1..1 space
inline float sdCircle(float2 p, float r) { return length(p) - r; }

// Composites "src over dst" (straight alpha)
inline float4 over(float4 src, float4 dst)
{
    float a  = src.a + dst.a * (1.0 - src.a);
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-8);
    return float4(c, a);
}

void CircleColorOutlineCentered01_float(
    float2 uv01,         // 0..1 UV
    float  radius,       // -1..1 units
    float2 center01,     // 0..1 center
    float4 fillColor,    // RGBA
    float4 strokeColor,  // RGBA
    float  strokeWidth,  // -1..1 units (total thickness)
    out    float4 outColor)
{
    // Shift UVs so the chosen center maps to (0,0), then scale to -1..1
    float2 p = (uv01 - center01) * 2.0;

    // SDF to circle edge and analytic AA
    float d  = sdCircle(p, radius);         // <0 inside, ~0 on edge, >0 outside
    float aa = fwidth(d);

    // ---- Fill coverage (inside the circle) ----
    // 1 at deep inside, 0 outside, smooth around d = 0
    float fillMask = 1.0 - smoothstep(0.0, aa, d);
    float4 fillOut = float4(fillColor.rgb, saturate(fillColor.a) * fillMask);

    // ---- Stroke coverage (centered on the edge) ----
    // Make a band of total thickness = strokeWidth around d = 0.
    // edge = 0 at the band center; positive outside the band.
    float halfW = 0.5 * max(strokeWidth, 0.0);
    float edge  = abs(d) - halfW;
    float strokeMask = 1.0 - smoothstep(0.0, aa, edge);
    float4 strokeOut = float4(strokeColor.rgb, saturate(strokeColor.a) * strokeMask);

    // Composite: stroke OVER fill (ensures outline is visible on top)
    outColor = over(strokeOut, fillOut);
}

//==========================================================================
//  Procedural Primitives – Color + Outline (Dynamic Center)
//  Author: Niloufar Moradijam
//  File: SquareColorOutline_Centered.hlsl
//
//  Description
//  ------------------------------------------------------------------------
//  Centered, axis-aligned square with solid fill + configurable outline,
//  implemented via SDF with analytic antialiasing.
//  - Dynamic center via `center01` (0..1 UV space).
//  - `halfSize` and `strokeWidth` are measured in the post-centered -1..1 space.
//  - Minimal single-output RGBA (straight alpha), ready for Shader Graph.
//
//  Shader Graph (Custom Function - File)
//  ------------------------------------------------------------------------
//  Function Name : SquareColorOutlineCentered01_float
//  Inputs  :
//      uv01        (float2) – standard 0..1 UV
//      halfSize    (float)  – half the side length in -1..1 units (e.g. 0.35)
//      center01    (float2) – square center in 0..1 (e.g. 0.5,0.5)
//      fillColor   (float4) – RGBA for the filled area
//      strokeColor (float4) – RGBA for the outline
//      strokeWidth (float)  – outline thickness (total, centered on edge),
//                              in -1..1 units (e.g. 0.02)
//  Output :
//      outColor    (float4) – RGBA (straight alpha)
//
//  Usage Notes
//  ------------------------------------------------------------------------
//  • Wire uv01 from your UV, center01 from a Vector2, and expose halfSize and
//    strokeWidth as floats in Shader Graph.
//  • The function composites the stroke OVER the fill.
//==========================================================================

#ifndef PI
#define PI 3.14159265359
#endif

// SDF for an axis-aligned box centered at origin with half extents b
inline float sdBox(float2 p, float2 b)
{
    float2 q = abs(p) - b;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
}

void SquareColorOutlineCentered01_float(
    float2 uv01,         // 0..1 UV
    float  halfSize,     // -1..1 units (half the side length)
    float2 center01,     // 0..1 center
    float4 fillColor,    // RGBA
    float4 strokeColor,  // RGBA
    float  strokeWidth,  // -1..1 units (total thickness)
    out    float4 outColor)
{
    // Shift UVs so the chosen center maps to (0,0), then scale to -1..1
    float2 p = (uv01 - center01) * 2.0;

    // SDF to square edge and analytic AA
    float d  = sdBox(p, float2(max(halfSize, 0.0), max(halfSize, 0.0)));
    float aa = fwidth(d);

    // ---- Fill coverage (inside the square) ----
    float fillMask = 1.0 - smoothstep(0.0, aa, d);
    float4 fillOut = float4(fillColor.rgb, saturate(fillColor.a) * fillMask);

    // ---- Stroke coverage (band centered on the edge) ----
    float halfW = 0.5 * max(strokeWidth, 0.0);
    float edge  = abs(d) - halfW;
    float strokeMask = 1.0 - smoothstep(0.0, aa, edge);
    float4 strokeOut = float4(strokeColor.rgb, saturate(strokeColor.a) * strokeMask);

    // Composite: stroke OVER fill
    outColor = over(strokeOut, fillOut);
}

//==========================================================================
//  Procedural Primitives – Color + Outline (Dynamic Center)
//  Author: Niloufar Moradijam
//  File: TriangleColorOutline_Centered.hlsl
//
//  Description
//  ------------------------------------------------------------------------
//  Centered, upright **equilateral** triangle with solid fill + outline,
//  implemented via SDF with analytic antialiasing.
//  - Dynamic center via `center01` (0..1 UV space).
//  - `radius` is the **circumradius** (center → vertex) in -1..1 space.
//  - Minimal single-output RGBA (straight alpha), ready for Shader Graph.
//
//  Shader Graph (Custom Function - File)
//  ------------------------------------------------------------------------
//  Function Name : TriangleColorOutlineCentered01_float
//  Inputs  :
//      uv01        (float2) – standard 0..1 UV
//      radius      (float)  – circumradius in -1..1 units (e.g. 0.40)
//      center01    (float2) – triangle center in 0..1 (e.g. 0.5,0.5)
//      fillColor   (float4) – RGBA for the filled area
//      strokeColor (float4) – RGBA for the outline
//      strokeWidth (float)  – outline thickness (total, centered on edge),
//                              in -1..1 units (e.g. 0.02)
//  Output :
//      outColor    (float4) – RGBA (straight alpha)
//
//  Usage Notes
//  ------------------------------------------------------------------------
//  • Same wiring as circle/square: expose radius, strokeWidth, and center01.
//  • Stroke is composited OVER the fill.
//==========================================================================

// SDF of an upright equilateral triangle centered at the origin,
// parameterized by **circumradius** r (center -> vertex).
// Reference form adapted for minimalism; returns d<0 inside, ~0 on edge.
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

void TriangleColorOutlineCentered01_float(
    float2 uv01,         // 0..1 UV
    float  radius,       // -1..1 units (circumradius)
    float2 center01,     // 0..1 center
    float4 fillColor,    // RGBA
    float4 strokeColor,  // RGBA
    float  strokeWidth,  // -1..1 units (total thickness)
    out    float4 outColor)
{
    // Shift UVs so the chosen center maps to (0,0), then scale to -1..1
    float2 p = (uv01 - center01) * 2.0;

    // SDF to triangle edge and analytic AA
    float d  = sdEquilateralTriangle_Centered(p, max(radius, 0.0));
    float aa = fwidth(d);

    // ---- Fill coverage (inside the triangle) ----
    float fillMask = 1.0 - smoothstep(0.0, aa, d);
    float4 fillOut = float4(fillColor.rgb, saturate(fillColor.a) * fillMask);

    // ---- Stroke coverage (band centered on the edge) ----
    float halfW = 0.5 * max(strokeWidth, 0.0);
    float edge  = abs(d) - halfW;
    float strokeMask = 1.0 - smoothstep(0.0, aa, edge);
    float4 strokeOut = float4(strokeColor.rgb, saturate(strokeColor.a) * strokeMask);

    // Composite: stroke OVER fill
    outColor = over(strokeOut, fillOut);
}

//==========================================================================
//  Procedural Primitives – Color + Outline (Dynamic Center)
//  Author: Niloufar Moradijam
//  File: RectangleColorOutline_Centered.hlsl
//
//  Description
//  ------------------------------------------------------------------------
//  Color-enabled rectangle with a configurable outline, using an SDF with
//  analytic antialiasing. Matches the minimal interface pattern where
//  width/height and center01 are in 0..1 UV units.
//  - Fill and outline colors are composited (stroke over fill).
//  - strokeWidth is in **UV units** (same space as width/height).
//
//  Minimal Interface
//  ------------------------------------------------------------------------
//  Function Name : RectangleColorOutlineCentered01_float
//  Inputs  :
//      uv01        (float2) – UV in 0..1
//      width       (float)  – full width in 0..1 UV units
//      height      (float)  – full height in 0..1 UV units
//      center01    (float2) – rectangle center in 0..1 UV
//      fillColor   (float4) – RGBA fill
//      strokeColor (float4) – RGBA outline
//      strokeWidth (float)  – outline thickness in 0..1 UV units (total)
//  Output :
//      outColor    (float4) – RGBA (straight alpha; A = coverage)
//==========================================================================

// Signed Distance Function for an axis-aligned rectangle at the origin.
// halfSize = (width/2, height/2) in the same units as p.
inline float sdRectangle(float2 p, float2 halfSize)
{
    float2 d = abs(p) - halfSize;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}


void RectangleColorOutlineCentered01_float(
    float2 uv01,        // 0..1 UV
    float  width,       // full width in UV units
    float  height,      // full height in UV units
    float2 center01,    // 0..1 center
    float4 fillColor,   // RGBA
    float4 strokeColor, // RGBA
    float  strokeWidth, // UV units (total thickness)
    out    float4 outColor)
{
    // Recenter UVs around center01 (stay in 0..1 UV units)
    float2 p = uv01 - center01;

    // Half extents in UV units
    float2 halfSize = float2(max(width, 0.0) * 0.5, max(height, 0.0) * 0.5);

    // SDF and analytic AA
    float sd = sdRectangle(p, halfSize);
    float aa = fwidth(sd);

    // ---- Fill coverage (inside the rectangle) ----
    float fillMask = 1.0 - smoothstep(0.0, aa, sd);
    float4 fillOut = float4(fillColor.rgb, saturate(fillColor.a) * fillMask);

    // ---- Stroke coverage (band centered on the edge) ----
    float halfW = 0.5 * max(strokeWidth, 0.0);
    float edge  = abs(sd) - halfW;
    float strokeMask = 1.0 - smoothstep(0.0, aa, edge);
    float4 strokeOut = float4(strokeColor.rgb, saturate(strokeColor.a) * strokeMask);

    // Composite: stroke OVER fill
    outColor = over(strokeOut, fillOut);
}

//==========================================================================
//  Procedural Primitives – Color + Outline (Dynamic Center)
//  Author: Niloufar Moradijam
//  File: RhombusColorOutline_Centered.hlsl
//
//  Description
//  ------------------------------------------------------------------------
//  Rhombus (diamond) with solid fill + uniform outline using a convex-
//  polygon SDF (exact Euclidean distance) and analytic AA.
//  Parameters are in 0..1 UV units, matching your color-only variant.
//
//  Minimal Interface
//  ------------------------------------------------------------------------
//  Function Name : RhombusColorOutlineCentered01_float
//  Inputs  :
//      uv01        (float2) – UV in 0..1
//      a           (float)  – half horizontal diagonal (UV units)
//      b           (float)  – half vertical   diagonal (UV units)
//      center01    (float2) – rhombus center in 0..1 UV
//      fillColor   (float4) – RGBA fill
//      strokeColor (float4) – RGBA outline
//      strokeWidth (float)  – outline thickness in UV units (total)
//  Output :
//      outColor    (float4) – RGBA (straight alpha; A = coverage)
//==========================================================================

// --- Helpers --------------------------------------------------------------

// Exact SDF to a segment AB (Euclidean)
inline float sdSegment(float2 p, float2 a, float2 b)
{
    float2 pa = p - a, ba = b - a;
    float  h  = saturate(dot(pa, ba) / dot(ba, ba));
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
        float  sEdge = dot(p - a, n);
        s = max(s, sEdge);
    }

    // outside: positive (distance to boundary); inside: negative
    return (s > 0.0) ? sqrt(d2) : -sqrt(d2);
}

// Guarded straight-alpha "src over dst" to avoid multiple-definition errors
#ifndef NM_OVER_HELPER
#define NM_OVER_HELPER
inline float4 nm_over(float4 src, float4 dst)
{
    float a  = src.a + dst.a * (1.0 - src.a);
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-8);
    return float4(c, a);
}
#endif

// --- Main -----------------------------------------------------------------
void RhombusColorOutlineCentered01_float(
    float2 uv01,        // 0..1 UV
    float  a,           // half horizontal diagonal (UV units)
    float  b,           // half vertical   diagonal (UV units)
    float2 center01,    // 0..1 center
    float4 fillColor,   // RGBA
    float4 strokeColor, // RGBA
    float  strokeWidth, // UV units (total thickness)
    out    float4 outColor)
{
    // Recenter in UV space (stay in 0..1 units)
    float2 p = uv01 - center01;

    // Diamond vertices (CCW): (a,0) -> (0,b) -> (-a,0) -> (0,-b)
    float2 v0 = float2( a, 0.0);
    float2 v1 = float2(0.0,  b );
    float2 v2 = float2(-a, 0.0);
    float2 v3 = float2(0.0, -b );

    // True Euclidean signed distance and AA
    float d  = sdConvexPoly4(p, v0, v1, v2, v3);
    float aa = fwidth(d);

    // Fill (inside polygon)
    float fillMask = 1.0 - smoothstep(0.0, aa, d);
    float4 fillOut = float4(fillColor.rgb, saturate(fillColor.a) * fillMask);

    // Stroke: uniform band around edge
    float halfW = 0.5 * max(strokeWidth, 0.0);
    float edge  = abs(d) - halfW;
    float strokeMask = 1.0 - smoothstep(0.0, aa, edge);
    float4 strokeOut = float4(strokeColor.rgb, saturate(strokeColor.a) * strokeMask);

    // Stroke OVER fill
    outColor = nm_over(strokeOut, fillOut);
}

//==========================================================================
//  Procedural Primitives – Color + Outline (Dynamic Center)
//  Author: Niloufar Moradijam
//  File: ParallelogramColorOutline_Centered.hlsl
//
//  Description
//  ------------------------------------------------------------------------
//  Color-filled 2D parallelogram with configurable outline using an exact
//  convex-polygon SDF (Euclidean) + analytic AA. Parameters are in 0..1 UV
//  units, matching your color-only variant.
//
//  Geometry
//      P = A + s*u + t*v,   0 ≤ s ≤ 1,  0 ≤ t ≤ 1
//
//  Minimal Interface
//  ------------------------------------------------------------------------
//  Function Name : ParallelogramColorOutlineCentered01_float
//  Inputs  :
//      uv01        (float2) – UV in 0..1
//      A           (float2) – one corner (UV units, in centered space)
//      u           (float2) – side vector 1 (UV units)
//      v           (float2) – side vector 2 (UV units)
//      center01    (float2) – shape center in 0..1 UV
//      fillColor   (float4) – RGBA fill
//      strokeColor (float4) – RGBA outline
//      strokeWidth (float)  – outline thickness in UV units (total)
//  Output :
//      outColor    (float4) – RGBA (straight alpha; A = coverage)
//==========================================================================

// --- Helpers (guarded to avoid multiple-definition across files) ---------
#ifndef NM_PARALLEL_HELPERS
#define NM_PARALLEL_HELPERS

inline float det2(float2 a, float2 b) { return a.x * b.y - a.y * b.x; }


// Exact SDF to a convex quad given CCW vertices v0..v3.
// Returns d<0 inside, ~0 on edge, d>0 outside.
inline float sdConvexQuad(float2 p, float2 v0, float2 v1, float2 v2, float2 v3)
{
    float2 v[4] = { v0, v1, v2, v3 };

    float d2 = 1e20;   // min squared distance to edges
    float s  = -1e20;  // max signed half-space value (outside > 0)

    [unroll]
    for (int i = 0; i < 4; ++i)
    {
        float2 a = v[i];
        float2 b = v[(i + 1) & 3];

        d2 = min(d2, sdSegment(p, a, b) * sdSegment(p, a, b));

        float2 e = b - a;
        float2 n = normalize(float2(e.y, -e.x)); // outward normal for CCW
        s = max(s, dot(p - a, n));
    }
    return (s > 0.0) ? sqrt(d2) : -sqrt(d2);
}


#endif // NM_PARALLEL_HELPERS

// --- Main -----------------------------------------------------------------
void ParallelogramColorOutlineCentered01_float(
    float2 uv01,         // 0..1 UV
    float2 A,            // corner (relative to centered space)
    float2 u,            // side vector 1
    float2 v,            // side vector 2
    float2 center01,     // 0..1 center
    float4 fillColor,    // RGBA
    float4 strokeColor,  // RGBA
    float  strokeWidth,  // UV units (total thickness)
    out    float4 outColor)
{
    // Recenter in UV space (stay in 0..1 units)
    float2 p = uv01 - center01;

    // Build vertices from A,u,v. Ensure CCW winding (swap if det(u,v) < 0).
    bool ccw = det2(u, v) >= 0.0;
    float2 uu = ccw ? u : v;
    float2 vv = ccw ? v : u;

    float2 v0 = A;
    float2 v1 = A + uu;
    float2 v2 = A + uu + vv;
    float2 v3 = A + vv;

    // Exact signed distance + AA
    float d  = sdConvexQuad(p, v0, v1, v2, v3);
    float aa = fwidth(d);

    // ---- Fill (inside polygon) ----
    float fillMask = 1.0 - smoothstep(0.0, aa, d);
    float4 fillOut = float4(fillColor.rgb, saturate(fillColor.a) * fillMask);

    // ---- Stroke: uniform band around edge ----
    float halfW = 0.5 * max(strokeWidth, 0.0);
    float edge  = abs(d) - halfW;
    float strokeMask = 1.0 - smoothstep(0.0, aa, edge);
    float4 strokeOut = float4(strokeColor.rgb, saturate(strokeColor.a) * strokeMask);

    // Composite: stroke OVER fill
    outColor = nm_over(strokeOut, fillOut);
}

//==========================================================================
//  Procedural Primitives – Color + Outline (Dynamic Center)
//  Author: Niloufar Moradijam
//  File: EllipseColorOutline_Centered.hlsl
//
//  Description
//  ------------------------------------------------------------------------
//  Axis-aligned ellipse with solid fill + configurable outline using an
//  analytic pseudo-distance (F / ||∇F||) and fwidth-based AA.
//  Matches the UV-space parameterization of your color-only variant.
//
//  Minimal Interface
//  ------------------------------------------------------------------------
//  Function Name : EllipseColorOutlineCentered01_float
//  Inputs  :
//      uv01        (float2) – UV in 0..1
//      width       (float)  – full ellipse width  (UV units)
//      height      (float)  – full ellipse height (UV units)
//      center01    (float2) – ellipse center in 0..1 UV
//      fillColor   (float4) – RGBA fill
//      strokeColor (float4) – RGBA outline
//      strokeWidth (float)  – outline thickness in UV units (total)
//  Output :
//      outColor    (float4) – RGBA (straight alpha; A = coverage)
//==========================================================================

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


void EllipseColorOutlineCentered01_float(
    float2 uv01,        // 0..1 UV
    float  width,       // full width (UV units)
    float  height,      // full height (UV units)
    float2 center01,    // 0..1 center
    float4 fillColor,   // RGBA
    float4 strokeColor, // RGBA
    float  strokeWidth, // UV units (total thickness)
    out    float4 outColor)
{
    // Recenter in UV space
    float2 p = uv01 - center01;

    // Half-axes
    float2 halfAxes = float2(width * 0.5, height * 0.5);

    // Signed pseudo-distance and AA
    float d  = sdEllipseApprox(p, halfAxes);
    float aa = fwidth(d);

    // ---- Fill coverage ----
    float fillMask = 1.0 - smoothstep(0.0, aa, d);
    float4 fillOut = float4(fillColor.rgb, saturate(fillColor.a) * fillMask);

    // ---- Stroke coverage ----
    float halfW = 0.5 * max(strokeWidth, 0.0);
    float edge  = abs(d) - halfW;
    float strokeMask = 1.0 - smoothstep(0.0, aa, edge);
    float4 strokeOut = float4(strokeColor.rgb, saturate(strokeColor.a) * strokeMask);

    // Composite: stroke OVER fill
    outColor = nm_over(strokeOut, fillOut);
}

//==========================================================================
//  Procedural Primitives – Color + Outline (Dynamic Center)
//  Author: Niloufar Moradijam
//  File: TrapezoidColorOutline_Centered.hlsl
//
//  Description
//  ------------------------------------------------------------------------
//  Axis-aligned isosceles trapezoid with solid fill + configurable outline,
//  using exact distance to edges + half-space sign and fwidth-based AA.
//  Parameters are in 0..1 UV units, matching the color-only variant.
//
//  Minimal Interface
//  ------------------------------------------------------------------------
//  Function Name : TrapezoidColorOutlineCentered01_float
//  Inputs  :
//      uv01        (float2) – UV in 0..1
//      widthBottom (float)  – full bottom width  (UV units)
//      widthTop    (float)  – full top width     (UV units)
//      height      (float)  – full height        (UV units)
//      center01    (float2) – trapezoid center in 0..1 UV
//      fillColor   (float4) – RGBA fill
//      strokeColor (float4) – RGBA outline
//      strokeWidth (float)  – outline thickness in UV units (total)
//  Output :
//      outColor    (float4) – RGBA (straight alpha; A = coverage)
//==========================================================================

#ifndef NM_TRAPEZOID_HELPERS
#define NM_TRAPEZOID_HELPERS

inline float2 nm_perpRight(float2 e) { return float2(e.y, -e.x); } // right-hand perp

inline float nm_distPointToSegment(float2 p, float2 v0, float2 v1)
{
    float2 e = v1 - v0;
    float  ee = max(dot(e, e), 1e-12);
    float  t  = clamp(dot(p - v0, e) / ee, 0.0, 1.0);
    float2 q  = v0 + t * e;
    return length(p - q);
}

// Signed distance to an origin-centered, axis-aligned isosceles trapezoid
inline float nm_sdTrapezoid(float2 p, float widthBottom, float widthTop, float height)
{
    float a = 0.5 * widthTop;     // half top width
    float b = 0.5 * widthBottom;  // half bottom width
    float h = 0.5 * height;       // half height

    // CCW vertices
    float2 v0 = float2(-b, -h);
    float2 v1 = float2( b, -h);
    float2 v2 = float2( a,  h);
    float2 v3 = float2(-a,  h);

    // Edges and outward normals (CCW → right-hand perp is outward)
    float2 E0 = v1 - v0, n0 = normalize(nm_perpRight(E0));
    float2 E1 = v2 - v1, n1 = normalize(nm_perpRight(E1));
    float2 E2 = v3 - v2, n2 = normalize(nm_perpRight(E2));
    float2 E3 = v0 - v3, n3 = normalize(nm_perpRight(E3));

    // Half-space distances (positive outside)
    float d0 = dot(n0, p - v0);
    float d1 = dot(n1, p - v1);
    float d2 = dot(n2, p - v2);
    float d3 = dot(n3, p - v3);

    // Inside if all <= 0 → sign = -1 inside, +1 outside
    float sgn = (max(max(d0, d1), max(d2, d3)) <= 0.0) ? -1.0 : 1.0;

    // Unsigned distance to boundary: min distance to any edge segment
    float du = min(
        min(nm_distPointToSegment(p, v0, v1), nm_distPointToSegment(p, v1, v2)),
        min(nm_distPointToSegment(p, v2, v3), nm_distPointToSegment(p, v3, v0))
    );

    return du * sgn;
}

#endif // NM_TRAPEZOID_HELPERS

//------------------------------------------------------------------------------
// TrapezoidColorOutlineCentered01_float
//------------------------------------------------------------------------------
void TrapezoidColorOutlineCentered01_float(
    float2 uv01,        // 0..1 UV
    float  widthBottom, // full bottom width  (UV units)
    float  widthTop,    // full top width     (UV units)
    float  height,      // full height        (UV units)
    float2 center01,    // 0..1 center
    float4 fillColor,   // RGBA
    float4 strokeColor, // RGBA
    float  strokeWidth, // UV units (total thickness)
    out   float4 outColor)
{
    // Recenter to center01 (stay in UV units)
    float2 p = uv01 - center01;

    // Signed distance and AA factor
    float d  = nm_sdTrapezoid(p, widthBottom, widthTop, height);
    float aa = fwidth(d);

    // Fill coverage
    float fillMask = 1.0 - smoothstep(0.0, aa, d);
    float4 fillOut = float4(fillColor.rgb, saturate(fillColor.a) * fillMask);

    // Stroke coverage (uniform band around the edge)
    float halfW = 0.5 * max(strokeWidth, 0.0);
    float edge  = abs(d) - halfW;
    float strokeMask = 1.0 - smoothstep(0.0, aa, edge);
    float4 strokeOut = float4(strokeColor.rgb, saturate(strokeColor.a) * strokeMask);

    // Stroke OVER fill
    outColor = nm_over(strokeOut, fillOut);
}

//==========================================================================
//  Procedural Primitives – Color + Outline (Dynamic Center)
//  Author: Niloufar Moradijam
//  File: PentagonColorOutline_Centered.hlsl
//
//  Description
//  ------------------------------------------------------------------------
//  Upright regular pentagon (no rotation) with solid fill + configurable
//  outline using a convex-polygon SDF (exact Euclidean edge distance +
//  half-space sign) and fwidth-based AA. Parameters are in 0..1 UV units.
//
//  Minimal Interface
//  ------------------------------------------------------------------------
//  Function Name : PentagonColorOutlineCentered01_float
//  Inputs  :
//      uv01        (float2) – UV in 0..1
//      radius      (float)  – circumradius (center → vertex), UV units
//      center01    (float2) – pentagon center in 0..1 UV
//      fillColor   (float4) – RGBA fill
//      strokeColor (float4) – RGBA outline
//      strokeWidth (float)  – outline thickness in UV units (total)
//  Output :
//      outColor    (float4) – RGBA (straight alpha; A = coverage)
//==========================================================================

// Signed distance to an origin-centered upright regular pentagon (circumradius = r)
inline float nm_sdPentagon(float2 p, float r)
{
    // Build 5 CCW vertices starting at "top" (0, +r)
    float2 v[5];
    [unroll]
    for (int i = 0; i < 5; ++i)
    {
        float ang = PI * 0.5 + (2.0 * PI * i) / 5.0;
        v[i] = r * float2(cos(ang), sin(ang));
    }

    float maxHalf = -1e9; // max half-space (outside > 0)
    float minEdge =  1e9; // min unsigned distance to any edge

    [unroll]
    for (int i = 0; i < 5; ++i)
    {
        int j = (i + 1) % 5;
        float2 a = v[i], b = v[j];
        float2 e = b - a;
        float2 n = normalize(nm_perpRight(e));   // outward normal for CCW

        maxHalf = max(maxHalf, dot(p - a, n));   // >0 outside this edge
        minEdge = min(minEdge, nm_distPointToSegment(p, a, b));
    }

    // Inside if all half-spaces <= 0  → sign = -1 inside, +1 outside
    float sgn = (maxHalf <= 0.0) ? -1.0 : 1.0;
    return minEdge * sgn;
}

// --- Main -----------------------------------------------------------------
void PentagonColorOutlineCentered01_float(
    float2 uv01,         // 0..1 UV
    float  radius,       // circumradius (UV units)
    float2 center01,     // 0..1 center
    float4 fillColor,    // RGBA
    float4 strokeColor,  // RGBA
    float  strokeWidth,  // UV units (total thickness)
    out    float4 outColor)
{
    // Recenter in UV space (stay in 0..1 units)
    float2 p = uv01 - center01;

    // Signed distance and AA
    float d  = nm_sdPentagon(p, max(radius, 0.0));
    float aa = fwidth(d);

    // ---- Fill coverage ----
    float fillMask = 1.0 - smoothstep(0.0, aa, d);
    float4 fillOut = float4(fillColor.rgb, saturate(fillColor.a) * fillMask);

    // ---- Stroke coverage (uniform band around the edge) ----
    float halfW = 0.5 * max(strokeWidth, 0.0);
    float edge  = abs(d) - halfW;
    float strokeMask = 1.0 - smoothstep(0.0, aa, edge);
    float4 strokeOut = float4(strokeColor.rgb, saturate(strokeColor.a) * strokeMask);

    // Composite: stroke OVER fill
    outColor = nm_over(strokeOut, fillOut);
}

//==========================================================================
//  Procedural Primitives – Color + Outline (Dynamic Center)
//  Author: Niloufar Moradijam
//  File: HexagonColorOutline_Centered.hlsl
//
//  Description
//  ------------------------------------------------------------------------
//  Upright, flat-top regular hexagon with solid fill + configurable outline.
//  Uses a convex-polygon SDF (exact Euclidean edge distance + half-space
//  sign) and fwidth-based AA. Parameters are in 0..1 UV units.
//
//  Minimal Interface
//  ------------------------------------------------------------------------
//  Function Name : HexagonColorOutlineCentered01_float
//  Inputs  :
//      uv01        (float2) – UV in 0..1
//      radius      (float)  – circumradius (center→vertex), UV units
//      center01    (float2) – hexagon center in 0..1 UV
//      fillColor   (float4) – RGBA fill
//      strokeColor (float4) – RGBA outline
//      strokeWidth (float)  – outline thickness in UV units (total)
//  Output :
//      outColor    (float4) – RGBA (straight alpha; A = coverage)
//==========================================================================


// Signed distance to an origin-centered, flat-top regular hexagon
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
    float minEdge =  1e9; // min unsigned distance to edges

    [unroll]
    for (int i = 0; i < 6; ++i)
    {
        int j = (i + 1) % 6;
        float2 a = v[i], b = v[j];
        float2 e = b - a;
        float2 n = normalize(nm_perpRight(e));   // outward normal (CCW)

        maxHalf = max(maxHalf, dot(p - a, n));
        minEdge = min(minEdge, nm_distPointToSegment(p, a, b));
    }

    // Inside if all half-spaces <= 0
    float sgn = (maxHalf <= 0.0) ? -1.0 : 1.0;
    return minEdge * sgn; // negative inside, positive outside
}

// --- Main -----------------------------------------------------------------
void HexagonColorOutlineCentered01_float(
    float2 uv01,         // 0..1 UV
    float  radius,       // circumradius (UV units)
    float2 center01,     // 0..1 center
    float4 fillColor,    // RGBA
    float4 strokeColor,  // RGBA
    float  strokeWidth,  // UV units (total thickness)
    out    float4 outColor)
{
    // Recenter in UV space
    float2 p = uv01 - center01;

    // Signed distance and AA
    float d  = nm_sdHexagon(p, max(radius, 0.0));
    float aa = fwidth(d);

    // ---- Fill coverage ----
    float fillMask = 1.0 - smoothstep(0.0, aa, d);
    float4 fillOut = float4(fillColor.rgb, saturate(fillColor.a) * fillMask);

    // ---- Stroke coverage (uniform band around edge) ----
    float halfW = 0.5 * max(strokeWidth, 0.0);
    float edge  = abs(d) - halfW;
    float strokeMask = 1.0 - smoothstep(0.0, aa, edge);
    float4 strokeOut = float4(strokeColor.rgb, saturate(strokeColor.a) * strokeMask);

    // Composite: stroke OVER fill
    outColor = nm_over(strokeOut, fillOut);
}

//==========================================================================
//  Procedural Primitives – Color + Outline (Dynamic Center)
//  Author: Niloufar Moradijam
//  File: HeptagonColorOutline_Centered.hlsl
//
//  Description
//  ------------------------------------------------------------------------
//  Upright regular heptagon (no rotation control) with solid fill +
//  configurable outline, using a convex-polygon SDF (exact edge distance +
//  half-space sign) and fwidth-based AA. All params in 0..1 UV units.
//
//  Minimal Interface
//  ------------------------------------------------------------------------
//  Function Name : HeptagonColorOutlineCentered01_float
//  Inputs  :
//      uv01        (float2) – UV in 0..1
//      radius      (float)  – circumradius (center→vertex), UV units
//      center01    (float2) – heptagon center in 0..1 UV
//      fillColor   (float4) – RGBA fill
//      strokeColor (float4) – RGBA outline
//      strokeWidth (float)  – outline thickness in UV units (total)
//  Output :
//      outColor    (float4) – RGBA (straight alpha; A = coverage)
//==========================================================================


// Signed distance to an origin-centered, upright regular heptagon
inline float nm_sdHeptagon(float2 p, float r)
{
    const int N = 7;
    float2 v[N];

    // CCW vertices, start at "top" (angle = +90°)
    [unroll]
    for (int i = 0; i < N; ++i)
    {
        float ang = PI * 0.5 + (2.0 * PI * i) / (float)N;
        v[i] = r * float2(cos(ang), sin(ang));
    }

    float maxHalf = -1e9; // outside > 0
    float minEdge =  1e9; // min unsigned distance to edges

    [unroll]
    for (int i = 0; i < N; ++i)
    {
        int j = (i + 1) % N;
        float2 a = v[i], b = v[j];
        float2 e = b - a;
        float2 n = normalize(nm_perpRight(e));   // outward normal (CCW)

        maxHalf = max(maxHalf, dot(p - a, n));
        minEdge = min(minEdge, nm_distPointToSegment(p, a, b));
    }

    // Inside if all half-spaces <= 0
    float sgn = (maxHalf <= 0.0) ? -1.0 : 1.0;
    return minEdge * sgn; // negative inside, positive outside
}

// --- Main -----------------------------------------------------------------
void HeptagonColorOutlineCentered01_float(
    float2 uv01,         // 0..1 UV
    float  radius,       // circumradius (UV units)
    float2 center01,     // 0..1 center
    float4 fillColor,    // RGBA
    float4 strokeColor,  // RGBA
    float  strokeWidth,  // UV units (total thickness)
    out    float4 outColor)
{
    // Recenter in UV space (stay in 0..1 units)
    float2 p = uv01 - center01;

    // Signed distance and AA
    float d  = nm_sdHeptagon(p, max(radius, 0.0));
    float aa = fwidth(d);

    // ---- Fill coverage ----
    float fillMask = 1.0 - smoothstep(0.0, aa, d);
    float4 fillOut = float4(fillColor.rgb, saturate(fillColor.a) * fillMask);

    // ---- Stroke coverage (uniform band around edge) ----
    float halfW = 0.5 * max(strokeWidth, 0.0);
    float edge  = abs(d) - halfW;
    float strokeMask = 1.0 - smoothstep(0.0, aa, edge);
    float4 strokeOut = float4(strokeColor.rgb, saturate(strokeColor.a) * strokeMask);

    // Composite: stroke OVER fill
    outColor = nm_over(strokeOut, fillOut);
}

//==========================================================================
//  Procedural Primitives – Color + Outline (Dynamic Center)
//  Author: Niloufar Moradijam
//  File: OctagonColorOutline_Centered.hlsl
//
//  Description
//  ------------------------------------------------------------------------
//  Upright regular octagon (8 sides) with solid fill + configurable outline,
//  implemented via convex-polygon SDF (exact edge distance + half-space sign)
//  and fwidth-based analytic AA. All parameters are in 0..1 UV units.
//
//  Minimal Interface
//  ------------------------------------------------------------------------
//  Function Name : OctagonColorOutlineCentered01_float
//  Inputs  :
//      uv01        (float2) – UV in 0..1
//      radius      (float)  – circumradius (center→vertex), UV units
//      center01    (float2) – octagon center in 0..1 UV
//      fillColor   (float4) – RGBA fill
//      strokeColor (float4) – RGBA outline
//      strokeWidth (float)  – outline thickness in UV units (total)
//  Output :
//      outColor    (float4) – RGBA (straight alpha; A = coverage)
//==========================================================================

// Signed distance to an origin-centered, upright regular octagon
inline float nm_sdOctagon(float2 p, float r)
{
    const int N = 8;
    float2 v[N];

    // CCW vertices, start at top (angle = +90°)
    [unroll]
    for (int i = 0; i < N; ++i)
    {
        float ang = PI * 0.5 + (2.0 * PI * i) / (float)N;
        v[i] = r * float2(cos(ang), sin(ang));
    }

    float maxHalf = -1e9; // outside > 0
    float minEdge =  1e9; // min unsigned distance to edges

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
void OctagonColorOutlineCentered01_float(
    float2 uv01,         // 0..1 UV
    float  radius,       // circumradius (UV units)
    float2 center01,     // 0..1 center
    float4 fillColor,    // RGBA
    float4 strokeColor,  // RGBA
    float  strokeWidth,  // UV units (total thickness)
    out    float4 outColor)
{
    // Recenter in UV space
    float2 p = uv01 - center01;

    // Signed distance and AA
    float d  = nm_sdOctagon(p, max(radius, 0.0));
    float aa = fwidth(d);

    // ---- Fill coverage ----
    float fillMask = 1.0 - smoothstep(0.0, aa, d);
    float4 fillOut = float4(fillColor.rgb, saturate(fillColor.a) * fillMask);

    // ---- Stroke coverage (uniform band around edge) ----
    float halfW = 0.5 * max(strokeWidth, 0.0);
    float edge  = abs(d) - halfW;
    float strokeMask = 1.0 - smoothstep(0.0, aa, edge);
    float4 strokeOut = float4(strokeColor.rgb, saturate(strokeColor.a) * strokeMask);

    // Composite: stroke OVER fill
    outColor = nm_over(strokeOut, fillOut);
}
