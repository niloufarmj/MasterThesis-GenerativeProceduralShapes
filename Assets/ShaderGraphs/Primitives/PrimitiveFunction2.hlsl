//==========================================================================
//  Procedural Primitives Library – Color Edition
//  Author: Niloufar Moradijam
//  File: Primitives_CircleColor.hlsl
//
//  Description
//  ------------------------------------------------------------------------
//  Simple color-enabled circle primitive using a Signed Distance Function
//  (SDF). The circle is centered at (0,0) in UV space and outputs an RGBA
//  color (with alpha) suitable for compositing in Shader Graph.
//
//  Features
//  ------------------------------------------------------------------------
//  - Centered at (0,0) in normalized UV coordinates
//  - Adjustable radius
//  - Analytic anti-aliasing (fwidth)
//  - Fill color controllable from Shader Graph
//
//  Shader Graph Integration
//  ------------------------------------------------------------------------
//  Function Name : CircleColor_float
//  Inputs  :
//      uv        (float2) – Centered UV coordinates (e.g. (0,0) = screen center)
//      radius    (float)  – Circle radius in UV units
//      fillColor (float4) – RGBA color of the circle
//  Outputs :
//      outColor  (float4) – Final color (RGB + Alpha)
//      outMask   (float)  – Coverage mask [0..1] for compositing
//
//  Usage Notes
//  ------------------------------------------------------------------------
//  1. Feed UVs centered around (0,0), typically via (UV - 0.5) * 2.
//  2. Output can be plugged into Unlit BaseColor or mixed with backgrounds.
//  3. The alpha channel corresponds to the filled region’s coverage.
//==========================================================================

inline float sdCircle(float2 p, float r) { return length(p) - r; }

void CircleColor01_float(                // Function name to use in SG
    float2 uv01,                         // regular 0..1 UV
    float  r,                            // radius (try ~0.35)
    float4 color,                        // RGBA
    out float4 outColor)                 // RGBA (straight alpha)
{
    // Center UVs to (-1..1) around (0,0)
    float2 uv = (uv01 - 0.5) * 2.0;

    // SDF + analytic AA
    float d  = sdCircle(uv, r);
    float aa = fwidth(d);
    float mask = 1.0 - smoothstep(0.0, aa, d);

    // Final color (RGB) and alpha = coverage * color.a
    outColor = float4(color.rgb, saturate(color.a) * mask);
}

//==========================================================================
//  Procedural Primitives Library – Minimal Color Edition
//  Author: Niloufar Moradijam
//  File: Primitives_SquareColor.hlsl
//
//  Description
//  ------------------------------------------------------------------------
//  Simple color-enabled square primitive using a Signed Distance Function
//  (SDF). The square is centered at (0,0) in UV space and outputs an RGBA
//  color suitable for compositing in Unity Shader Graph.
//
//  Features
//  ------------------------------------------------------------------------
//  - Centered at (0,0) in normalized UV coordinates
//  - Adjustable half-size (radius-like control)
//  - Analytic anti-aliasing using fwidth()
//  - Fill color controllable directly from Shader Graph
//  - Minimal interface (no extras)
//
//  Shader Graph Integration
//  ------------------------------------------------------------------------
//  Function Name : SquareColor01_float
//  Inputs  :
//      uv01   (float2) – Standard 0..1 UV coordinates
//      s      (float)  – Half-size of the square (typical range: 0.2–0.5)
//      color  (float4) – RGBA color for the filled area
//  Outputs :
//      outColor (float4) – Final RGBA color (straight alpha)
//
//  Usage Notes
//  ------------------------------------------------------------------------
//  1. Plug UV → uv01, Float → s, and Color → color.
//  2. Split outColor → RGB to BaseColor, A to Alpha.
//  3. Set Shader Graph Surface = Transparent.
//  4. Output will be a centered, anti-aliased, colored square.
//
//  Example Visual
//  ------------------------------------------------------------------------
//     +-------------------------+
//     |                         |
//     |          ■■■            |
//     |          ■■■            |   ← Colored square centered at (0,0)
//     |          ■■■            |
//     |                         |
//     +-------------------------+
//
//==========================================================================

// --- Signed Distance Function for a square centered at origin ------------
inline float sdSquare(float2 p, float s)
{
    // Signed distance from point p to the edge of the square.
    // Negative inside, positive outside.
    float2 d = abs(p) - s;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// --- Main color-enabled square function ----------------------------------
void SquareColor01_float(
    float2 uv01,     // Input UV (0..1)
    float  s,        // Half-size
    float4 color,    // RGBA
    out float4 outColor) // RGBA output
{
    // Center UVs to (-1..1) around (0,0)
    float2 uv = (uv01 - 0.5) * 2.0;

    // Signed distance computation
    float d  = sdSquare(uv, s);

    // Anti-aliased edge via fwidth()
    float aa = fwidth(d);

    // Smooth inside mask
    float mask = 1.0 - smoothstep(0.0, aa, d);

    // Final color output
    outColor = float4(color.rgb, saturate(color.a) * mask);
}

//==========================================================================
//  Procedural Primitives Library – Minimal Color Edition
//  Author: Niloufar Moradijam
//  File: Primitives_TriangleColor.hlsl
//
//  Description
//  ------------------------------------------------------------------------
//  Minimal color-enabled, centered equilateral triangle using an SDF.
//  Matches the CircleColor01_float / SquareColor01_float style.
//
//  Shader Graph (Custom Function - File)
//  ------------------------------------------------------------------------
//  Function Name : TriangleColor01_float
//  Inputs  :
//    uv01   (float2)  - standard 0..1 UV
//    size   (float)   - uniform scale (try ~0.35)
//    color  (float4)  - RGBA fill
//  Output  :
//    outColor (float4) - RGBA (straight alpha), no extra outputs
//==========================================================================

inline float sdEquilateralTriangle(float2 p, float size)
{
    // Scale to unit triangle, compute SDF, scale back.
    const float k = 1.7320508075688772; // sqrt(3)
    p /= max(size, 1e-8);

    p.x = abs(p.x) - 1.0;
    p.y = p.y + 1.0 / k;

    if (p.x + k * p.y > 0.0)
    {
        p = float2((p.x - k * p.y) * 0.5, (-k * p.x - p.y) * 0.5);
    }

    p.x -= clamp(p.x, -2.0, 0.0);

    // Negative inside, positive outside (like circle SDF)
    return (-length(p) * sign(p.y)) * size;
}

void TriangleColor01_float(
    float2 uv01,       // 0..1 UV
    float  size,       // triangle size
    float4 color,      // RGBA
    out float4 outColor)
{
    // Center to (-1..1) space
    float2 uv = (uv01 - 0.5) * 2.0;

    // Signed distance to triangle edge
    float d  = sdEquilateralTriangle(uv, size);

    // Anti-aliased coverage
    float aa = fwidth(d);
    float mask = 1.0 - smoothstep(0.0, aa, d);

    // Final color (straight alpha)
    outColor = float4(color.rgb, saturate(color.a) * mask);
}

//==========================================================================
//  Procedural Primitives Library – Minimal Color Edition
//  Author: Niloufar Moradijam
//  File: Primitives_RectangleColor.hlsl
//
//  Description
//  ------------------------------------------------------------------------
//  Minimal color-enabled rectangle primitive based on Inigo Quilez’s SDF
//  formulation. Centered at (0,0) in UV space and parameterized by width
//  and height. Outputs a single RGBA color (no extra outputs).
//
//  Shader Graph (Custom Function - File)
//  ------------------------------------------------------------------------
//  Function Name : RectangleColor01_float
//  Inputs  :
//      uv01   (float2) – Standard UV coordinates [0..1]
//      width  (float)  – Full width of the rectangle (normalized units)
//      height (float)  – Full height of the rectangle (normalized units)
//      color  (float4) – RGBA fill color
//  Output  :
//      outColor (float4) – RGBA (straight alpha)
//==========================================================================

//--------------------------------------------------------------------------
// Signed Distance Function (SDF) for a centered rectangle
//--------------------------------------------------------------------------
inline float sdRectangle(float2 p, float2 halfSize)
{
    float2 d = abs(p) - halfSize;
    float outside = length(max(d, 0.0));
    float inside  = min(max(d.x, d.y), 0.0);
    return outside + inside;
}

//--------------------------------------------------------------------------
// RectangleColor01_float
//--------------------------------------------------------------------------
void RectangleColor01_float(
    float2 uv01,      // 0..1 UV
    float  width,     // rectangle width
    float  height,    // rectangle height
    float4 color,     // RGBA
    out float4 outColor)
{
    // Center UV so (0.5,0.5) is the origin
    float2 p = uv01 - float2(0.5, 0.5);

    // Compute half-size
    float2 halfSize = float2(width * 0.5, height * 0.5);

    // Signed distance
    float sd = sdRectangle(p, halfSize);

    // Anti-aliased mask
    float aa = fwidth(sd);
    float mask = 1.0 - smoothstep(0.0, aa, sd);

    // Final colored output
    outColor = float4(color.rgb, saturate(color.a) * mask);
}

//==========================================================================
//  Procedural Primitives Library – Minimal Color Edition
//  Author: Niloufar Moradijam
//  File: Primitives_RhombusColor.hlsl
//
//  Description
//  ------------------------------------------------------------------------
//  Minimal color-enabled rhombus (diamond) primitive using an exact SDF
//  formulation based on Inigo Quilez’s reference implementation.
//  The rhombus is centered at (0,0) in UV space and parameterized by its
//  half-diagonals (a, b). Outputs a single RGBA color for Shader Graph.
//
//  Shader Graph (Custom Function - File)
//  ------------------------------------------------------------------------
//  Function Name : RhombusColor01_float
//  Inputs  :
//      uv01  (float2) – normalized UV coordinates [0..1]
//      a     (float)  – half of the horizontal diagonal (controls width)
//      b     (float)  – half of the vertical   diagonal (controls height)
//      color (float4) – RGBA fill color
//  Output  :
//      outColor (float4) – RGBA (straight alpha)
//==========================================================================

//--------------------------------------------------------------------------
// Signed Distance Function (SDF) for a Rhombus
//--------------------------------------------------------------------------
inline float sdRhombus(float2 p, float2 halfDiag)
{
    // Work in first quadrant (symmetry)
    p = abs(p);

    float bb = dot(halfDiag, halfDiag);
    float h  = clamp((-2.0 * dot(p, halfDiag) + bb) / bb, -1.0, 1.0);
    float2 q = p - 0.5 * halfDiag * float2(1.0 - h, 1.0 + h);

    // Unsigned distance
    float unsignedDist = length(q);

    // Recover sign (negative inside)
    float s = (p.x * halfDiag.y + p.y * halfDiag.x - halfDiag.x * halfDiag.y) >= 0.0 ? 1.0 : -1.0;
    return unsignedDist * s;
}

//--------------------------------------------------------------------------
// RhombusColor01_float
//--------------------------------------------------------------------------
void RhombusColor01_float(
    float2 uv01,       // 0..1 UV
    float  a,          // half horizontal diagonal
    float  b,          // half vertical diagonal
    float4 color,      // RGBA
    out float4 outColor)
{
    // Center UV to (-0.5..0.5)
    float2 p = uv01 - float2(0.5, 0.5);

    // Signed distance
    float sd = sdRhombus(p, float2(a, b));

    // Anti-aliased edge mask
    float aa = fwidth(sd);
    float mask = 1.0 - smoothstep(0.0, aa, sd);

    // Final RGBA output
    outColor = float4(color.rgb, saturate(color.a) * mask);
}

//==========================================================================
//  Procedural Primitives Library – Minimal Color Edition
//  Author: Niloufar Moradijam
//  File: Primitives_ParallelogramColor.hlsl
//
//  Description
//  ------------------------------------------------------------------------
//  Minimal color-enabled 2D parallelogram primitive defined by one corner
//  and two side vectors. The logic follows the same formulation as
//  Parallelogram01_float, extended with anti-aliasing and color output.
//
//  Geometry Definition
//      P = A + s*u + t*v,    0 ≤ s ≤ 1,  0 ≤ t ≤ 1
//
//  Shader Graph (Custom Function - File)
//  ------------------------------------------------------------------------
//  Function Name : ParallelogramColor01_float
//  Inputs  :
//      uv01 (float2) – normalized UV coordinates [0..1]
//      A    (float2) – corner position (in centered UV space)
//      u    (float2) – side vector 1
//      v    (float2) – side vector 2
//      color (float4) – RGBA fill color
//  Output :
//      outColor (float4) – RGBA (straight alpha)
//==========================================================================

// Helper: 2D determinant
inline float det2(float2 a, float2 b) { return a.x * b.y - a.y * b.x; }

//--------------------------------------------------------------------------
//  ParallelogramColor01_float
//--------------------------------------------------------------------------
void ParallelogramColor01_float(
    float2 uv01,     // 0..1 UV
    float2 A,        // one corner
    float2 u,        // side vector 1
    float2 v,        // side vector 2
    float4 color,    // RGBA fill
    out float4 outColor)
{
    // Center UVs so (0.5,0.5) → (0,0)
    float2 p = uv01 - float2(0.5, 0.5);

    // Solve p = A + s*u + t*v  → find (s,t)
    float2 r = p - A;
    float  D = det2(u, v);
    float  invD = 1.0 / D;

    float s = det2(r, v) * invD;
    float t = det2(u, r) * invD;

    // Continuous mask with anti-aliased edges
    float borderDist = min(min(s, 1.0 - s), min(t, 1.0 - t));
    float aa = fwidth(borderDist);
    float mask = smoothstep(0.0, aa, borderDist);

    // Final colored output
    outColor = float4(color.rgb, saturate(color.a) * mask);
}

//==========================================================================
//  Procedural Primitives Library – Minimal Color Edition
//  Author: Niloufar Moradijam
//  File: Primitives_EllipseColor.hlsl
//
//  Description
//  ------------------------------------------------------------------------
//  Minimal color-enabled, axis-aligned ellipse centered in UV space.
//  Uses a high-quality signed pseudo-distance (F/||∇F||) for stable
//  anti-aliased edges. Outputs a single RGBA color – no extra outputs.
//
//  Shader Graph (Custom Function - File)
//  ------------------------------------------------------------------------
//  Function Name : EllipseColor01_float
//  Inputs  :
//      uv01   (float2) – normalized UV [0..1]
//      width  (float)  – full ellipse width  (normalized units)
//      height (float)  – full ellipse height (normalized units)
//      color  (float4) – RGBA fill color
//  Output :
//      outColor (float4) – RGBA (straight alpha)
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

    // Pseudo-distance with robust fallback at the center
    return (gradLen > 1e-8) ? (F / gradLen) : -min(a, b);
}

void EllipseColor01_float(
    float2 uv01,      // 0..1 UV
    float  width,     // full width
    float  height,    // full height
    float4 color,     // RGBA
    out float4 outColor)
{
    // Center UV so (0.5,0.5) → (0,0)
    float2 p = uv01 - float2(0.5, 0.5);

    // Half-axes
    float2 halfAxes = float2(width * 0.5, height * 0.5);

    // Signed pseudo-distance
    float sd = sdEllipseApprox(p, halfAxes);

    // Anti-aliased coverage
    float aa = fwidth(sd);
    float mask = 1.0 - smoothstep(0.0, aa, sd);

    // Final RGBA (straight alpha)
    outColor = float4(color.rgb, saturate(color.a) * mask);
}

//==========================================================================
//  Procedural Primitives Library – Minimal Color Edition
//  Author: Niloufar Moradijam
//  File: Primitives_TrapezoidColor.hlsl
//
//  Description
//  ------------------------------------------------------------------------
//  Minimal color-enabled, centered isosceles trapezoid (axis-aligned).
//  Uses the same SDF construction as your binary version (convex polygon
//  sign + min distance to edges). Outputs a single RGBA color.
//
//  Shader Graph (Custom Function - File)
//  ------------------------------------------------------------------------
//  Function Name : TrapezoidColor01_float
//  Inputs  :
//      uv01        (float2) – normalized UV [0..1]
//      widthBottom (float)  – full bottom width
//      widthTop    (float)  – full top width
//      height      (float)  – full height
//      color       (float4) – RGBA fill
//  Output :
//      outColor    (float4) – RGBA (straight alpha)
//==========================================================================

inline float2 perpRight(float2 e) { return float2(e.y, -e.x); } // right-hand perp

// Distance from point p to segment [v0, v1] (unsigned)
inline float distPointToSegment(float2 p, float2 v0, float2 v1)
{
    float2 e = v1 - v0;
    float t  = dot(p - v0, e) / max(dot(e, e), 1e-12);
    t = clamp(t, 0.0, 1.0);
    float2 q = v0 + t * e;
    return length(p - q);
}

// Signed distance to centered isosceles trapezoid (axis-aligned)
inline float sdTrapezoid_Centered(float2 p, float widthBottom, float widthTop, float height)
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
// TrapezoidColor01_float  (minimal RGBA output)
//------------------------------------------------------------------------------
void TrapezoidColor01_float(
    float2 uv01,        // 0..1 UV
    float  widthBottom, // full bottom width
    float  widthTop,    // full top width
    float  height,      // full height
    float4 color,       // RGBA
    out float4 outColor)
{
    // Center UV to (0,0)
    float2 p = uv01 - float2(0.5, 0.5);

    // Signed distance
    float sd = sdTrapezoid_Centered(p, widthBottom, widthTop, height);

    // Analytic AA coverage
    float aa = fwidth(sd);
    float mask = 1.0 - smoothstep(0.0, aa, sd);

    // Final RGBA (straight alpha)
    outColor = float4(color.rgb, saturate(color.a) * mask);
}

//==========================================================================
//  Procedural Primitives Library – Minimal Color Edition
//  Author: Niloufar Moradijam
//  File: Primitives_PentagonColor.hlsl
//
//  Description
//  ------------------------------------------------------------------------
//  Minimal color-enabled, centered regular pentagon (upright, no rotation).
//  Uses a convex-polygon SDF approach: inside/outside from half-spaces and
//  magnitude from the minimum distance to edges. Outputs a single RGBA.
//
//  Shader Graph (Custom Function - File)
//  ------------------------------------------------------------------------
//  Function Name : PentagonColor01_float
//  Inputs  :
//      uv01   (float2) – normalized UV [0..1]
//      radius (float)  – circumradius (center → each vertex), e.g., 0.35
//      color  (float4) – RGBA fill color
//  Output :
//      outColor (float4) – RGBA (straight alpha)
//==========================================================================


// Signed distance to centered, upright regular pentagon (circumradius = r)
inline float sdPentagon_Centered(float2 p, float r)
{
    // Build the 5 vertices (CCW), starting from the top vertex
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
        float2 n = normalize(perpRight(e));       // outward for CCW polygon

        // Half-space distance: positive outside
        float di = dot(n, p - v[i]);
        maxHalfSpace = max(maxHalfSpace, di);

        // Unsigned distance to edge
        float du = distPointToSegment(p, v[i], v[j]);
        minEdgeDist = min(minEdgeDist, du);
    }

    // Inside if all half-space distances <= 0
    float sgn = (maxHalfSpace <= 0.0) ? -1.0 : 1.0;
    return minEdgeDist * sgn; // negative inside, positive outside
}

//------------------------------------------------------------------------------
// PentagonColor01_float  (minimal RGBA output)
//------------------------------------------------------------------------------
void PentagonColor01_float(
    float2 uv01,     // 0..1 UV
    float  radius,   // circumradius
    float4 color,    // RGBA
    out float4 outColor)
{
    // Center UV so (0.5,0.5) → (0,0)
    float2 p = uv01 - float2(0.5, 0.5);

    // Signed distance
    float sd = sdPentagon_Centered(p, radius);

    // Analytic AA
    float aa = fwidth(sd);
    float mask = 1.0 - smoothstep(0.0, aa, sd);

    // Final RGBA (straight alpha)
    outColor = float4(color.rgb, saturate(color.a) * mask);
}

//==========================================================================
//  Procedural Primitives Library – Minimal Color Edition
//  Author: Niloufar Moradijam
//  File: Primitives_HexagonColor.hlsl
//
//  Description
//  ------------------------------------------------------------------------
//  Minimal color-enabled, centered regular hexagon (flat top).
//  Uses convex-polygon SDF logic (inside via half-spaces, magnitude via
//  min distance to edges) and returns a single RGBA color for Shader Graph.
//
//  Shader Graph (Custom Function - File)
//  ------------------------------------------------------------------------
//  Function Name : HexagonColor01_float
//  Inputs  :
//      uv01   (float2) – normalized UV [0..1]
//      radius (float)  – circumradius (center → each vertex), e.g., 0.35
//      color  (float4) – RGBA fill color
//  Output :
//      outColor (float4) – RGBA (straight alpha)
//==========================================================================


// Signed distance to centered, flat-top regular hexagon -----------------
inline float sdHexagon_Centered(float2 p, float r)
{
    // Build 6 vertices CCW, flat top (start at 30°)
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
        float2 n = normalize(perpRight(e)); // outward for CCW polygon

        float di = dot(n, p - v[i]);                 // positive outside
        maxHalfSpace = max(maxHalfSpace, di);

        float du = distPointToSegment(p, v[i], v[j]); // unsigned edge distance
        minEdgeDist = min(minEdgeDist, du);
    }

    // Negative inside, positive outside
    float sgn = (maxHalfSpace <= 0.0) ? -1.0 : 1.0;
    return minEdgeDist * sgn;
}

// Minimal color output function for Shader Graph ------------------------
void HexagonColor01_float(
    float2 uv01,       // 0..1 UV
    float  radius,     // circumradius
    float4 color,      // RGBA
    out float4 outColor)
{
    // Center UV so (0.5,0.5) → (0,0)
    float2 p = uv01 - float2(0.5, 0.5);

    // Signed distance
    float sd = sdHexagon_Centered(p, radius);

    // Analytic AA coverage
    float aa = fwidth(sd);
    float mask = 1.0 - smoothstep(0.0, aa, sd);

    // Final RGBA (straight alpha)
    outColor = float4(color.rgb, saturate(color.a) * mask);
}

//==========================================================================
//  Procedural Primitives Library – Minimal Color Edition
//  Author: Niloufar Moradijam
//  File: Primitives_HeptagonColor.hlsl
//
//  Description
//  ------------------------------------------------------------------------
//  Minimal color-enabled, centered regular heptagon (7 sides, upright).
//  Uses convex-polygon SDF logic (half-space max + min edge distance)
//  and outputs a single RGBA color with anti-aliased edges.
//
//  Shader Graph (Custom Function - File)
//  ------------------------------------------------------------------------
//  Function Name : HeptagonColor01_float
//  Inputs  :
//      uv01   (float2) – normalized UV [0..1]
//      radius (float)  – circumradius (center → vertex), e.g. 0.35
//      color  (float4) – RGBA fill color
//  Output :
//      outColor (float4) – RGBA (straight alpha)
//==========================================================================


// Signed distance to centered, upright regular heptagon ------------------
inline float sdHeptagon_Centered(float2 p, float r)
{
    const int N = 7;
    float2 v[N];

    // Build vertices CCW, start at top
    [unroll]
    for (int i = 0; i < N; ++i)
    {
        float angle = PI * 0.5 + (2.0 * PI * i) / (float)N;
        v[i] = r * float2(cos(angle), sin(angle));
    }

    float maxHalfSpace = -1e9;
    float minEdgeDist  =  1e9;

    [unroll]
    for (int i = 0; i < N; ++i)
    {
        int j = (i + 1) % N;
        float2 e = v[j] - v[i];
        float2 n = normalize(perpRight(e));

        float di = dot(n, p - v[i]);
        maxHalfSpace = max(maxHalfSpace, di);

        float du = distPointToSegment(p, v[i], v[j]);
        minEdgeDist = min(minEdgeDist, du);
    }

    float sgn = (maxHalfSpace <= 0.0) ? -1.0 : 1.0;
    return minEdgeDist * sgn;
}

//------------------------------------------------------------------------------
// HeptagonColor01_float  (minimal RGBA output)
//------------------------------------------------------------------------------
void HeptagonColor01_float(
    float2 uv01,     // 0..1 UV
    float  radius,   // circumradius
    float4 color,    // RGBA
    out float4 outColor)
{
    // Center UV so (0.5,0.5) → (0,0)
    float2 p = uv01 - float2(0.5, 0.5);

    // Signed distance
    float sd = sdHeptagon_Centered(p, radius);

    // Analytic AA coverage
    float aa = fwidth(sd);
    float mask = 1.0 - smoothstep(0.0, aa, sd);

    // Final RGBA (straight alpha)
    outColor = float4(color.rgb, saturate(color.a) * mask);
}

//==========================================================================
//  Procedural Primitives Library – Minimal Color Edition
//  Author: Niloufar Moradijam
//  File: Primitives_OctagonColor.hlsl
//
//  Description
//  ------------------------------------------------------------------------
//  Minimal color-enabled, centered regular octagon (8 sides, upright).
//  Uses convex-polygon SDF logic (half-space maximum + edge min-distance)
//  and returns a single RGBA color suitable for Unity Shader Graph.
//
//  Shader Graph (Custom Function - File)
//  ------------------------------------------------------------------------
//  Function Name : OctagonColor01_float
//  Inputs  :
//      uv01   (float2) – normalized UV [0..1]
//      radius (float)  – circumradius (center → vertex), e.g. 0.35
//      color  (float4) – RGBA fill color
//  Output :
//      outColor (float4) – RGBA (straight alpha)
//==========================================================================


// Signed distance to a centered, upright regular octagon -----------------
inline float sdOctagon_Centered(float2 p, float r)
{
    const int N = 8;
    float2 v[N];

    // Build 8 vertices CCW; start at top (+Y)
    [unroll]
    for (int i = 0; i < N; ++i)
    {
        float angle = PI * 0.5 + (2.0 * PI * i) / (float)N;
        v[i] = r * float2(cos(angle), sin(angle));
    }

    float maxHalfSpace = -1e9;
    float minEdgeDist  =  1e9;

    [unroll]
    for (int i = 0; i < N; ++i)
    {
        int j = (i + 1) % N;
        float2 e = v[j] - v[i];
        float2 n = normalize(perpRight(e)); // outward for CCW polygon

        float di = dot(n, p - v[i]);  // positive outside
        maxHalfSpace = max(maxHalfSpace, di);

        float du = distPointToSegment(p, v[i], v[j]); // unsigned edge distance
        minEdgeDist = min(minEdgeDist, du);
    }

    float sgn = (maxHalfSpace <= 0.0) ? -1.0 : 1.0;
    return minEdgeDist * sgn;
}

//------------------------------------------------------------------------------
// OctagonColor01_float  (minimal RGBA output)
//------------------------------------------------------------------------------
void OctagonColor01_float(
    float2 uv01,     // 0..1 UV
    float  radius,   // circumradius
    float4 color,    // RGBA
    out float4 outColor)
{
    // Center UV so (0.5,0.5) → (0,0)
    float2 p = uv01 - float2(0.5, 0.5);

    // Signed distance
    float sd = sdOctagon_Centered(p, radius);

    // Anti-aliased coverage
    float aa = fwidth(sd);
    float mask = 1.0 - smoothstep(0.0, aa, sd);

    // Final RGBA (straight alpha)
    outColor = float4(color.rgb, saturate(color.a) * mask);
}
