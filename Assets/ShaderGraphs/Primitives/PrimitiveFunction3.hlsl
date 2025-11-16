//==========================================================================
//  Procedural Primitives – Color (Centered via Property)
//  Author: Niloufar Moradijam
//  File: CircleColor_Centered.hlsl
//
//  Description
//  ------------------------------------------------------------------------
//  Color-enabled circle using an SDF with analytic anti-aliasing.
//  Unlike the origin-centered version, this one takes a dynamic center
//  (center01) so the circle can be positioned anywhere via Shader Graph.
//
//  Minimal Interface (no extras)
//  ------------------------------------------------------------------------
//  Function Name : CircleColorCentered01_float
//  Inputs  :
//      uv01      (float2) – standard 0..1 UV
//      radius    (float)  – circle radius (same units as the -1..1 space below)
//      center01  (float2) – circle center in 0..1 UV space (e.g. (0.5,0.5)=middle)
//      color     (float4) – RGBA fill color
//  Output :
//      outColor  (float4) – RGBA (straight alpha)
//
//  Notes
//  ------------------------------------------------------------------------
//  • We build the SDF in a centered -1..1 space for uniform scaling:
//        p = (uv01 - center01) * 2
//    This keeps radius behavior consistent with typical screen-space SDFs.
//  • Alpha is coverage (anti-aliased). Plug RGB → Base Color, A → Alpha
//    in an Unlit/Transparent Shader Graph.
//==========================================================================

inline float sdCircle(float2 p, float r) { return length(p) - r; }

void CircleColorCentered01_float(
    float2 uv01,        // 0..1 UV
    float  radius,      // circle radius (recommend ~0.3–0.5)
    float2 center01,    // circle center in 0..1 UV
    float4 color,       // RGBA
    out   float4 outColor)
{
    // Shift to the requested center (0..1) and scale to -1..1 space
    float2 p = (uv01 - center01) * 2.0;

    // Signed distance and analytic AA
    float  d   = sdCircle(p, radius);
    float  aa  = fwidth(d);
    float  mask = 1.0 - smoothstep(0.0, aa, d);

    // Final color with straight alpha
    outColor = float4(color.rgb, saturate(color.a) * mask);
}


//==========================================================================
//  Procedural Primitives – Color (Dynamic Center)
//  Author: Niloufar Moradijam
//  File: SquareColor_Centered.hlsl
//
//  Description
//  ------------------------------------------------------------------------
//  Color-enabled square using a Signed Distance Function (SDF) with analytic
//  anti-aliasing. Unlike the origin-centered version, this one takes a
//  dynamic center (center01) so the square can be positioned anywhere
//  directly from Shader Graph.
//
//  Minimal Interface
//  ------------------------------------------------------------------------
//  Function Name : SquareColorCentered01_float
//  Inputs  :
//      uv01      (float2) – UV in 0..1
//      s         (float)  – half-size in -1..1 space (edge at ±s)
//      center01  (float2) – square center in 0..1 UV (e.g. 0.5,0.5 = middle)
//      color     (float4) – RGBA fill
//  Output :
//      outColor  (float4) – RGBA (straight alpha; A = coverage)
//==========================================================================

inline float sdSquare(float2 p, float s)
{
    // Signed distance to an axis-aligned square of half-size s at the origin
    float2 d = abs(p) - s;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

void SquareColorCentered01_float(
    float2 uv01,        // 0..1 UV
    float  s,           // half-size in -1..1 space
    float2 center01,    // 0..1 center
    float4 color,       // RGBA
    out   float4 outColor)
{
    // Recenter UVs around center01 and scale to -1..1 space
    float2 p = (uv01 - center01) * 2.0;

    float d   = sdSquare(p, s);
    float aa  = fwidth(d);
    float mask = 1.0 - smoothstep(0.0, aa, d);

    outColor = float4(color.rgb, saturate(color.a) * mask);
}

//==========================================================================
//  Procedural Primitives – Color (Dynamic Center)
//  Author: Niloufar Moradijam
//  File: TriangleColor_Centered.hlsl
//
//  Description
//  ------------------------------------------------------------------------
//  Color-enabled equilateral triangle using an SDF with analytic AA.
//  This variant adds a dynamic center (center01) so you can position the
//  triangle anywhere from Shader Graph.
//
//  Minimal Interface
//  ------------------------------------------------------------------------
//  Function Name : TriangleColorCentered01_float
//  Inputs  :
//      uv01      (float2) – UV in 0..1
//      size      (float)  – uniform scale in -1..1 space (try ~0.35)
//      center01  (float2) – triangle center in 0..1 UV (e.g. 0.5,0.5)
//      color     (float4) – RGBA fill
//  Output :
//      outColor  (float4) – RGBA (straight alpha; A = coverage)
//==========================================================================

inline float sdEquilateralTriangle(float2 p, float size)
{
    // SDF for an equilateral triangle centered at origin (axis-aligned “point up”).
    // Adapted for consistency with your previous minimal version.
    const float k = 1.7320508075688772; // sqrt(3)
    float invSize = 1.0 / max(size, 1e-8);
    p *= invSize;

    p.x = abs(p.x) - 1.0;
    p.y = p.y + 1.0 / k;

    if (p.x + k * p.y > 0.0)
    {
        p = float2((p.x - k * p.y) * 0.5, (-k * p.x - p.y) * 0.5);
    }

    p.x -= clamp(p.x, -2.0, 0.0);

    // Negative inside, positive outside
    return (-length(p) * sign(p.y)) * size;
}

void TriangleColorCentered01_float(
    float2 uv01,        // 0..1 UV
    float  size,        // scale (recommend ~0.3–0.5)
    float2 center01,    // 0..1 center
    float4 color,       // RGBA
    out   float4 outColor)
{
    // Shift around center and scale to -1..1 space
    float2 p = (uv01 - center01) * 2.0;

    float d    = sdEquilateralTriangle(p, size);
    float aa   = fwidth(d);
    float mask = 1.0 - smoothstep(0.0, aa, d);

    outColor = float4(color.rgb, saturate(color.a) * mask);
}

//==========================================================================
//  Procedural Primitives – Color (Dynamic Center)
//  Author: Niloufar Moradijam
//  File: RectangleColor_Centered.hlsl
//
//  Description
//  ------------------------------------------------------------------------
//  Color-enabled rectangle using a Signed Distance Function (SDF) with
//  analytic anti-aliasing. This variant adds a dynamic center (center01)
//  so the rectangle can be positioned anywhere from Shader Graph.
//
//  Minimal Interface
//  ------------------------------------------------------------------------
//  Function Name : RectangleColorCentered01_float
//  Inputs  :
//      uv01      (float2) – UV in 0..1
//      width     (float)  – full width in 0..1 UV units
//      height    (float)  – full height in 0..1 UV units
//      center01  (float2) – rectangle center in 0..1 UV
//      color     (float4) – RGBA fill
//  Output :
//      outColor  (float4) – RGBA (straight alpha; A = coverage)
//==========================================================================

// Signed Distance Function for an axis-aligned rectangle at the origin.
// halfSize = (width/2, height/2) in the same units as p.
inline float sdRectangle(float2 p, float2 halfSize)
{
    float2 d = abs(p) - halfSize;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

void RectangleColorCentered01_float(
    float2 uv01,        // 0..1 UV
    float  width,       // full width in UV units
    float  height,      // full height in UV units
    float2 center01,    // 0..1 center
    float4 color,       // RGBA
    out   float4 outColor)
{
    // Recenter UVs around center01 (stay in 0..1 UV units)
    float2 p = uv01 - center01;

    // Half extents in UV units
    float2 halfSize = float2(width * 0.5, height * 0.5);

    // SDF and analytic AA
    float sd   = sdRectangle(p, halfSize);
    float aa   = fwidth(sd);
    float mask = 1.0 - smoothstep(0.0, aa, sd);

    // Final color with straight alpha
    outColor = float4(color.rgb, saturate(color.a) * mask);
}

//==========================================================================
//  Procedural Primitives – Color (Dynamic Center)
//  Author: Niloufar Moradijam
//  File: RhombusColor_Centered.hlsl
//
//  Description
//  ------------------------------------------------------------------------
//  Color-filled rhombus (diamond) via exact SDF with analytic AA.
//  This variant adds a dynamic center (center01) so the shape can be placed
//  anywhere from Shader Graph.
//
//  Minimal Interface
//  ------------------------------------------------------------------------
//  Function Name : RhombusColorCentered01_float
//  Inputs  :
//      uv01      (float2) – UV in 0..1
//      a         (float)  – half of horizontal diagonal (UV units)
//      b         (float)  – half of vertical   diagonal (UV units)
//      center01  (float2) – rhombus center in 0..1 UV
//      color     (float4) – RGBA fill
//  Output :
//      outColor  (float4) – RGBA (straight alpha; A = coverage)
//==========================================================================

// Signed Distance Function for a rhombus at the origin.
// halfDiag = float2(a, b) are half-diagonals in the same units as p.
inline float sdRhombus(float2 p, float2 halfDiag)
{
    p = abs(p); // first quadrant symmetry

    float bb = dot(halfDiag, halfDiag);
    float h  = clamp((-2.0 * dot(p, halfDiag) + bb) / bb, -1.0, 1.0);
    float2 q = p - 0.5 * halfDiag * float2(1.0 - h, 1.0 + h);

    float unsignedDist = length(q);

    // Negative inside, positive outside
    float s = (p.x * halfDiag.y + p.y * halfDiag.x - halfDiag.x * halfDiag.y) >= 0.0 ? 1.0 : -1.0;
    return unsignedDist * s;
}

void RhombusColorCentered01_float(
    float2 uv01,        // 0..1 UV
    float  a,           // half horizontal diagonal (UV units)
    float  b,           // half vertical   diagonal (UV units)
    float2 center01,    // 0..1 center
    float4 color,       // RGBA
    out   float4 outColor)
{
    // Recenter in UV space (stay in 0..1 units; no -1..1 scaling)
    float2 p = uv01 - center01;

    float sd   = sdRhombus(p, float2(a, b));
    float aa   = fwidth(sd);
    float mask = 1.0 - smoothstep(0.0, aa, sd);

    outColor = float4(color.rgb, saturate(color.a) * mask);
}

//==========================================================================
//  Procedural Primitives – Color (Dynamic Center)
//  Author: Niloufar Moradijam
//  File: ParallelogramColor_Centered.hlsl
//
//  Description
//  ------------------------------------------------------------------------
//  Color-filled 2D parallelogram defined by one corner (A) and two side
//  vectors (u, v). Adds a dynamic center (center01) so you can position the
//  shape anywhere directly from Shader Graph. Analytic AA via fwidth().
//
//  Geometry
//      P = A + s*u + t*v,   0 ≤ s ≤ 1,  0 ≤ t ≤ 1
//
//  Minimal Interface
//  ------------------------------------------------------------------------
//  Function Name : ParallelogramColorCentered01_float
//  Inputs  :
//      uv01      (float2) – UV in 0..1
//      A         (float2) – corner position in the centered space (UV units)
//      u         (float2) – side vector 1 (UV units)
//      v         (float2) – side vector 2 (UV units)
//      center01  (float2) – center of the shape in 0..1 UV
//      color     (float4) – RGBA fill
//  Output :
//      outColor  (float4) – RGBA (straight alpha; A = coverage)
//==========================================================================

// 2D determinant helper
inline float det2(float2 a, float2 b) { return a.x * b.y - a.y * b.x; }

void ParallelogramColorCentered01_float(
    float2 uv01,        // 0..1 UV
    float2 A,           // corner (relative to centered space)
    float2 u,           // side vector 1
    float2 v,           // side vector 2
    float2 center01,    // 0..1 center
    float4 color,       // RGBA
    out   float4 outColor)
{
    // Recenter UVs around center01 (all params in UV units)
    float2 p = uv01 - center01;

    // Solve p = A + s*u + t*v  → find (s,t)
    float2 r   = p - A;
    float  D   = det2(u, v);
    float  invD = 1.0 / D;
    float  s   = det2(r, v) * invD;
    float  t   = det2(u, r) * invD;

    // Positive inside distance to borders, negative outside
    float borderDist = min(min(s, 1.0 - s), min(t, 1.0 - t));

    // Analytic AA
    float aa   = fwidth(borderDist);
    float mask = smoothstep(0.0, aa, borderDist);

    outColor = float4(color.rgb, saturate(color.a) * mask);
}


//==========================================================================
//  Procedural Primitives – Color (Dynamic Center)
//  Author: Niloufar Moradijam
//  File: EllipseColor_Centered.hlsl
//
//  Description
//  ------------------------------------------------------------------------
//  Axis-aligned ellipse with color fill and analytic edge AA (via
//  signed pseudo-distance F/||∇F||). Adds a dynamic center (center01)
//  so the ellipse can be positioned anywhere from Shader Graph.
//
//  Minimal Interface
//  ------------------------------------------------------------------------
//  Function Name : EllipseColorCentered01_float
//  Inputs  :
//      uv01      (float2) – UV in 0..1
//      width     (float)  – full ellipse width  (UV units)
//      height    (float)  – full ellipse height (UV units)
//      center01  (float2) – ellipse center in 0..1 UV
//      color     (float4) – RGBA fill
//  Output :
//      outColor  (float4) – RGBA (straight alpha; A = coverage)
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

void EllipseColorCentered01_float(
    float2 uv01,        // 0..1 UV
    float  width,       // full width (UV units)
    float  height,      // full height (UV units)
    float2 center01,    // 0..1 center
    float4 color,       // RGBA
    out   float4 outColor)
{
    // Recenter in UV space (stay in 0..1 units)
    float2 p = uv01 - center01;

    // Half-axes
    float2 halfAxes = float2(width * 0.5, height * 0.5);

    // Signed pseudo-distance and AA
    float sd   = sdEllipseApprox(p, halfAxes);
    float aa   = fwidth(sd);
    float mask = 1.0 - smoothstep(0.0, aa, sd);

    // Final color (straight alpha)
    outColor = float4(color.rgb, saturate(color.a) * mask);
}

//==========================================================================
//  Procedural Primitives – Color (Dynamic Center)
//  Author: Niloufar Moradijam
//  File: TrapezoidColor_Centered.hlsl
//
//  Description
//  ------------------------------------------------------------------------
//  Axis-aligned isosceles trapezoid using a robust signed distance
//  (half-spaces + min distance to edges) with analytic AA.
//  Adds a dynamic center (center01) so the shape can be positioned
//  anywhere from Shader Graph.
//
//  Minimal Interface
//  ------------------------------------------------------------------------
//  Function Name : TrapezoidColorCentered01_float
//  Inputs  :
//      uv01        (float2) – UV in 0..1
//      widthBottom (float)  – full bottom width  (UV units)
//      widthTop    (float)  – full top width     (UV units)
//      height      (float)  – full height        (UV units)
//      center01    (float2) – trapezoid center in 0..1 UV
//      color       (float4) – RGBA fill
//  Output :
//      outColor    (float4) – RGBA (straight alpha; A = coverage)
//==========================================================================

inline float2 perpRight(float2 e) { return float2(e.y, -e.x); } // right-hand perp

// Distance from point p to segment [v0, v1] (unsigned)
inline float distPointToSegment(float2 p, float2 v0, float2 v1)
{
    float2 e = v1 - v0;
    float  ee = max(dot(e, e), 1e-12);
    float  t  = clamp(dot(p - v0, e) / ee, 0.0, 1.0);
    float2 q  = v0 + t * e;
    return length(p - q);
}

// Signed distance to an origin-centered, axis-aligned isosceles trapezoid
inline float sdTrapezoid(float2 p, float widthBottom, float widthTop, float height)
{
    // Half-dimensions
    float a = 0.5 * widthTop;     // half top width
    float b = 0.5 * widthBottom;  // half bottom width
    float h = 0.5 * height;       // half height

    // CCW vertices
    float2 v0 = float2(-b, -h);
    float2 v1 = float2( b, -h);
    float2 v2 = float2( a,  h);
    float2 v3 = float2(-a,  h);

    // Edges
    float2 E0 = v1 - v0;
    float2 E1 = v2 - v1;
    float2 E2 = v3 - v2;
    float2 E3 = v0 - v3;

    // Outward normals (CCW → right-hand perp is outward)
    float2 n0 = normalize(perpRight(E0));
    float2 n1 = normalize(perpRight(E1));
    float2 n2 = normalize(perpRight(E2));
    float2 n3 = normalize(perpRight(E3));

    // Half-space distances (positive outside)
    float d0 = dot(n0, p - v0);
    float d1 = dot(n1, p - v1);
    float d2 = dot(n2, p - v2);
    float d3 = dot(n3, p - v3);

    // Inside if all <= 0 → sign = -1 inside, +1 outside
    float sgn = (max(max(d0, d1), max(d2, d3)) <= 0.0) ? -1.0 : 1.0;

    // Unsigned distance to boundary: min distance to any edge
    float du = min(
                 min(distPointToSegment(p, v0, v1), distPointToSegment(p, v1, v2)),
                 min(distPointToSegment(p, v2, v3), distPointToSegment(p, v3, v0))
              );

    return du * sgn;
}

//------------------------------------------------------------------------------
// TrapezoidColorCentered01_float (minimal RGBA output)
//------------------------------------------------------------------------------
void TrapezoidColorCentered01_float(
    float2 uv01,        // 0..1 UV
    float  widthBottom, // full bottom width  (UV units)
    float  widthTop,    // full top width     (UV units)
    float  height,      // full height        (UV units)
    float2 center01,    // 0..1 center
    float4 color,       // RGBA
    out   float4 outColor)
{
    // Recenter UV to (0,0) at center01 (stay in 0..1 units)
    float2 p = uv01 - center01;

    // Signed distance
    float sd = sdTrapezoid(p, widthBottom, widthTop, height);

    // Analytic AA coverage
    float aa   = fwidth(sd);
    float mask = 1.0 - smoothstep(0.0, aa, sd);

    // Final RGBA (straight alpha)
    outColor = float4(color.rgb, saturate(color.a) * mask);
}

//==========================================================================
//  Procedural Primitives – Color (Dynamic Center)
//  Author: Niloufar Moradijam
//  File: PentagonColor_Centered.hlsl
//
//  Description
//  ------------------------------------------------------------------------
//  Upright regular pentagon (no rotation), color-filled, using a convex-
//  polygon SDF: sign from half-spaces, magnitude from min distance to edges.
//  Adds a dynamic center (center01) to position the shape via Shader Graph.
//
//  Minimal Interface
//  ------------------------------------------------------------------------
//  Function Name : PentagonColorCentered01_float
//  Inputs  :
//      uv01      (float2) – UV in 0..1
//      radius    (float)  – circumradius (center → vertex), e.g. ~0.35
//      center01  (float2) – pentagon center in 0..1 UV
//      color     (float4) – RGBA fill
//  Output :
//      outColor  (float4) – RGBA (straight alpha; A = coverage)
//==========================================================================

#ifndef PI
#define PI 3.14159265359
#endif


// Signed distance to an origin-centered, upright regular pentagon (circumradius = r)
inline float sdPentagon(float2 p, float r)
{
    // Build 5 CCW vertices, starting from "top" (0, +r)
    float2 v[5];
    [unroll]
    for (int i = 0; i < 5; ++i)
    {
        float ang = PI * 0.5 + (2.0 * PI * i) / 5.0;
        v[i] = r * float2(cos(ang), sin(ang));
    }

    float maxHalfSpace = -1e9;
    float minEdgeDist  =  1e9;

    [unroll]
    for (int i = 0; i < 5; ++i)
    {
        int j = (i + 1) % 5;
        float2 e = v[j] - v[i];
        float2 n = normalize(perpRight(e)); // outward (CCW)

        float di = dot(n, p - v[i]);                 // >0 outside w.r.t. edge i
        maxHalfSpace = max(maxHalfSpace, di);

        float du = distPointToSegment(p, v[i], v[j]); // unsigned distance to edge
        minEdgeDist = min(minEdgeDist, du);
    }

    // Inside if all half-space distances <= 0
    float sgn = (maxHalfSpace <= 0.0) ? -1.0 : 1.0;
    return minEdgeDist * sgn; // negative inside, positive outside
}

void PentagonColorCentered01_float(
    float2 uv01,        // 0..1 UV
    float  radius,      // circumradius
    float2 center01,    // 0..1 center
    float4 color,       // RGBA
    out   float4 outColor)
{
    // Recenter in UV space (stay in 0..1 units; no -1..1 scaling)
    float2 p = uv01 - center01;

    float sd   = sdPentagon(p, radius);
    float aa   = fwidth(sd);
    float mask = 1.0 - smoothstep(0.0, aa, sd);

    outColor = float4(color.rgb, saturate(color.a) * mask);
}

//==========================================================================
//  Procedural Primitives – Color (Dynamic Center)
//  Author: Niloufar Moradijam
//  File: HexagonColor_Centered.hlsl
//
//  Description
//  ------------------------------------------------------------------------
//  Upright, flat-top regular hexagon using a convex-polygon SDF:
//  sign from half-spaces, magnitude from min distance to edges.
//  Adds a dynamic center (center01) for placement via Shader Graph.
//
//  Minimal Interface
//  ------------------------------------------------------------------------
//  Function Name : HexagonColorCentered01_float
//  Inputs  :
//      uv01      (float2) – UV in 0..1
//      radius    (float)  – circumradius (center→vertex), e.g. ~0.35
//      center01  (float2) – hexagon center in 0..1 UV
//      color     (float4) – RGBA fill
//  Output :
//      outColor  (float4) – RGBA (straight alpha; A = coverage)
//==========================================================================

// Signed distance to an origin-centered, flat-top regular hexagon
inline float sdHexagon(float2 p, float r)
{
    // 6 CCW vertices, flat top (start at 30°)
    float2 v[6];
    [unroll]
    for (int i = 0; i < 6; ++i)
    {
        float ang = PI / 6.0 + (PI / 3.0) * i; // 30°, 90°, 150°, ...
        v[i] = r * float2(cos(ang), sin(ang));
    }

    float maxHalfSpace = -1e9;
    float minEdgeDist  =  1e9;

    [unroll]
    for (int i = 0; i < 6; ++i)
    {
        int j = (i + 1) % 6;
        float2 e = v[j] - v[i];
        float2 n = normalize(perpRight(e)); // outward (CCW)

        float di = dot(n, p - v[i]);                  // >0 outside w.r.t. edge i
        maxHalfSpace = max(maxHalfSpace, di);

        float du = distPointToSegment(p, v[i], v[j]); // unsigned distance to edge
        minEdgeDist = min(minEdgeDist, du);
    }

    // Inside if all half-space distances <= 0
    float sgn = (maxHalfSpace <= 0.0) ? -1.0 : 1.0;
    return minEdgeDist * sgn; // negative inside, positive outside
}

void HexagonColorCentered01_float(
    float2 uv01,        // 0..1 UV
    float  radius,      // circumradius
    float2 center01,    // 0..1 center
    float4 color,       // RGBA
    out   float4 outColor)
{
    // Recenter in UV space (stay in 0..1 units)
    float2 p = uv01 - center01;

    float sd   = sdHexagon(p, radius);
    float aa   = fwidth(sd);
    float mask = 1.0 - smoothstep(0.0, aa, sd);

    outColor = float4(color.rgb, saturate(color.a) * mask);
}

//==========================================================================
//  Procedural Primitives – Color (Dynamic Center)
//  Author: Niloufar Moradijam
//  File: HeptagonColor_Centered.hlsl
//
//  Description
//  ------------------------------------------------------------------------
//  Upright regular heptagon (7 sides) using a convex-polygon SDF:
//  sign from half-spaces, magnitude from min distance to edges.
//  Adds a dynamic center (center01) for placement from Shader Graph.
//
//  Minimal Interface
//  ------------------------------------------------------------------------
//  Function Name : HeptagonColorCentered01_float
//  Inputs  :
//      uv01      (float2) – UV in 0..1
//      radius    (float)  – circumradius (center→vertex), e.g. ~0.35
//      center01  (float2) – heptagon center in 0..1 UV
//      color     (float4) – RGBA fill
//  Output :
//      outColor  (float4) – RGBA (straight alpha; A = coverage)
//==========================================================================

// Signed distance to an origin-centered, upright regular heptagon
inline float sdHeptagon(float2 p, float r)
{
    const int N = 7;
    float2 v[N];

    // CCW vertices, start at top (angle = +90°)
    [unroll]
    for (int i = 0; i < N; ++i)
    {
        float ang = PI * 0.5 + (2.0 * PI * i) / (float)N;
        v[i] = r * float2(cos(ang), sin(ang));
    }

    float maxHalfSpace = -1e9;
    float minEdgeDist  =  1e9;

    [unroll]
    for (int i = 0; i < N; ++i)
    {
        int j = (i + 1) % N;
        float2 e = v[j] - v[i];
        float2 n = normalize(perpRight(e)); // outward (CCW)

        float di = dot(n, p - v[i]);                  // >0 outside w.r.t. edge i
        maxHalfSpace = max(maxHalfSpace, di);

        float du = distPointToSegment(p, v[i], v[j]); // unsigned distance to edge
        minEdgeDist = min(minEdgeDist, du);
    }

    // Inside if all half-space distances <= 0
    float sgn = (maxHalfSpace <= 0.0) ? -1.0 : 1.0;
    return minEdgeDist * sgn; // negative inside, positive outside
}

void HeptagonColorCentered01_float(
    float2 uv01,        // 0..1 UV
    float  radius,      // circumradius
    float2 center01,    // 0..1 center
    float4 color,       // RGBA
    out   float4 outColor)
{
    // Recenter in UV space (stay in 0..1 units)
    float2 p = uv01 - center01;

    float sd   = sdHeptagon(p, radius);
    float aa   = fwidth(sd);
    float mask = 1.0 - smoothstep(0.0, aa, sd);

    outColor = float4(color.rgb, saturate(color.a) * mask);
}

//==========================================================================
//  Procedural Primitives – Color (Dynamic Center)
//  Author: Niloufar Moradijam
//  File: OctagonColor_Centered.hlsl
//
//  Description
//  ------------------------------------------------------------------------
//  Upright regular octagon (8 sides) using convex-polygon SDF:
//  sign from half-spaces, magnitude from min distance to edges.
//  Adds a dynamic center (center01) for placement via Shader Graph.
//
//  Minimal Interface
//  ------------------------------------------------------------------------
//  Function Name : OctagonColorCentered01_float
//  Inputs  :
//      uv01      (float2) – UV in 0..1
//      radius    (float)  – circumradius (center→vertex), e.g. ~0.35
//      center01  (float2) – octagon center in 0..1 UV
//      color     (float4) – RGBA fill
//  Output :
//      outColor  (float4) – RGBA (straight alpha; A = coverage)
//==========================================================================


// Signed distance to an origin-centered, upright regular octagon
inline float sdOctagon(float2 p, float r)
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

    float maxHalfSpace = -1e9;
    float minEdgeDist  =  1e9;

    [unroll]
    for (int i = 0; i < N; ++i)
    {
        int j = (i + 1) % N;
        float2 e = v[j] - v[i];
        float2 n = normalize(perpRight(e)); // outward (CCW)

        float di = dot(n, p - v[i]);                  // >0 outside w.r.t. edge i
        maxHalfSpace = max(maxHalfSpace, di);

        float du = distPointToSegment(p, v[i], v[j]); // unsigned distance to edge
        minEdgeDist = min(minEdgeDist, du);
    }

    // Inside if all half-space distances <= 0
    float sgn = (maxHalfSpace <= 0.0) ? -1.0 : 1.0;
    return minEdgeDist * sgn; // negative inside, positive outside
}

void OctagonColorCentered01_float(
    float2 uv01,        // 0..1 UV
    float  radius,      // circumradius
    float2 center01,    // 0..1 center
    float4 color,       // RGBA
    out   float4 outColor)
{
    // Recenter in UV space (stay in 0..1 units)
    float2 p = uv01 - center01;

    float sd   = sdOctagon(p, radius);
    float aa   = fwidth(sd);
    float mask = 1.0 - smoothstep(0.0, aa, sd);

    outColor = float4(color.rgb, saturate(color.a) * mask);
}
