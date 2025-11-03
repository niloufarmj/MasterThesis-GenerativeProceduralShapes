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


//==========================================================================
//  Procedural Primitive – Rectangle (Rounded) + Color + Outline + Rotation
//  Author: Niloufar Moradijam
//  File: RectangleRoundedColorOutlineCenteredRotated.hlsl
//
//  Description
//  ------------------------------------------------------------------------
//  Color-enabled, rotatable **rounded-rectangle** (uniform corner radius)
//  with solid fill + outline via SDF and analytic AA. Corner radius changes
//  the rectangle silhouette itself (NOT the stroke).
//
//  Minimal Shader Graph Interface (single RGBA output)
//  ------------------------------------------------------------------------
//  Function Name : RectangleRoundedColorOutlineCenteredRotated01_float
//  Inputs  :
//      uv01         (float2) – UV in 0..1
//      width        (float)  – full width in 0..1 UV units
//      height       (float)  – full height in 0..1 UV units
//      cornerRadius (float)  – shape corner radius in UV units
//      center01     (float2) – rectangle center in 0..1 UV
//      angleRad     (float)  – rotation in radians (CCW). 0 = axis-aligned
//      fillColor    (float4) – RGBA fill
//      strokeColor  (float4) – RGBA outline
//      strokeWidth  (float)  – outline thickness in UV units (total)
//  Output :
//      outColor     (float4) – RGBA (straight alpha; A = coverage)
//
//  Shader Graph (Custom Function - File)
//  ------------------------------------------------------------------------
//  • Source File  : this HLSL
//  • Function Name: RectangleRoundedColorOutlineCenteredRotated01_float
//  • Wire UV→uv01, Vector2→center01, Floats→width/height/cornerRadius/
//    angleRad/strokeWidth, and Colors→fillColor/strokeColor.
//  • Use Unlit/Transparent; plug RGB→BaseColor and A→Alpha.
//
//  Notes
//  ------------------------------------------------------------------------
//  • We rotate the sampling point by -angle so the shape appears rotated by +angle.
//  • Corner radius is clamped to [0, min(width,height)/2].
//  • Stroke is composited OVER the fill.
//==========================================================================

// SDF for an axis-aligned rectangle centered at origin.
// halfSize = (width/2, height/2) in the same units as p.
inline float sdRectangle(float2 p, float2 halfSize)
{
    float2 d = abs(p) - halfSize;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// Rounded rectangle via SDF offset:
// d_round = sdRectangle(p, halfSize - r) - r;  (caller clamps r)
inline float sdRoundRectangle(float2 p, float2 halfSize, float r)
{
    return sdRectangle(p, halfSize - r) - r;
}

// --- Main -----------------------------------------------------------------
void RectangleRoundedColorOutlineCenteredRotated01_float(
    float2 uv01, // 0..1 UV
    float width, // full width in UV units
    float height, // full height in UV units
    float cornerRadius, // UV units (shape radius)
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

    // 3) Rounded-rectangle SDF
    float2 halfSize = 0.5 * float2(max(width, 0.0), max(height, 0.0));
    float rClamp = clamp(cornerRadius, 0.0, min(halfSize.x, halfSize.y));
    float d = sdRoundRectangle(pr, halfSize, rClamp); // d<0 inside

    // 4) Analytic AA width
    float aa = fwidth(d);

    // 5) Fill coverage
    float fillMask = 1.0 - smoothstep(0.0, aa, d);
    float4 fillOut = float4(fillColor.rgb, saturate(fillColor.a) * fillMask);

    // 6) Stroke coverage (uniform band around rounded edge)
    float halfW = 0.5 * max(strokeWidth, 0.0);
    float edge = abs(d) - halfW;
    float strokeMask = 1.0 - smoothstep(0.0, aa, edge);
    float4 strokeOut = float4(strokeColor.rgb, saturate(strokeColor.a) * strokeMask);

    // 7) Composite: stroke OVER fill
    outColor = over(strokeOut, fillOut);
}

//==========================================================================
//  Procedural Primitive – Rhombus (Rounded) + Color + Outline + Rotation
//  Author: Niloufar Moradijam
//  File: RhombusRoundedColorOutlineCenteredRotated.hlsl
//
//  Description
//  ------------------------------------------------------------------------
//  Centered, rotatable **rounded rhombus** (diamond with uniform corner
//  radius) with solid fill + outline via SDF and analytic AA. Corner
//  rounding affects the shape's silhouette (NOT the stroke).
//
//  Minimal Shader Graph Interface (single RGBA output)
//  ------------------------------------------------------------------------
//  Function Name : RhombusRoundedColorOutlineCenteredRotated01_float
//  Inputs  :
//      uv01         (float2) – UV in 0..1
//      a            (float)  – half horizontal diagonal (UV units)
//      b            (float)  – half vertical   diagonal (UV units)
//      cornerRadius (float)  – shape corner radius in UV units
//      center01     (float2) – rhombus center in 0..1 UV
//      angleRad     (float)  – rotation in radians (CCW). 0 = upright
//      fillColor    (float4) – RGBA fill
//      strokeColor  (float4) – RGBA outline
//      strokeWidth  (float)  – outline thickness in UV units (total)
//  Output :
//      outColor     (float4) – RGBA (straight alpha; A = coverage)
//
//  Shader Graph (Custom Function - File)
//  ------------------------------------------------------------------------
//  • Source File  : this HLSL
//  • Function Name: RhombusRoundedColorOutlineCenteredRotated01_float
//  • Wire: UV→uv01, Vector2→center01, Floats→a/b/cornerRadius/angleRad/
//    strokeWidth, Colors→fillColor/strokeColor.
//  • Use Unlit/Transparent; plug RGB→BaseColor and A→Alpha.
//
//  Notes
//  ------------------------------------------------------------------------
//  • We rotate the *sampling point* by -angle so the shape appears rotated
//    by +angle (standard SDF trick).
//  • Corner radius is clamped to stay valid for the rhombus dimensions.
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
void RhombusRoundedColorOutlineCenteredRotated01_float(
    float2 uv01, // 0..1 UV
    float a, // half horizontal diagonal (UV units)
    float b, // half vertical   diagonal (UV units)
    float cornerRadius, // UV units (shape corner radius)
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

    // 3) Clamp corner radius to valid range
    // For a rhombus, the maximum corner radius is limited by the edge lengths
    // Calculate the edge length of the rhombus (distance between adjacent vertices)
    float edgeLength = sqrt(a * a + b * b);
    // Max radius is approximately half the shortest edge
    float maxRadius = min(a, b) * 0.5;
    float r = clamp(cornerRadius, 0.0, maxRadius);

    // 4) Shrink rhombus vertices inward to create rounded effect
    // Scale the diagonals down by the corner radius factor
    float scaleFactor = max(1.0 - r / max(min(a, b), 0.001), 0.0);
    float aInset = a * scaleFactor;
    float bInset = b * scaleFactor;

    // Rhombus vertices (CCW) in rotated space - inset for rounding
    float2 v0 = float2(aInset, 0.0);
    float2 v1 = float2(0.0, bInset);
    float2 v2 = float2(-aInset, 0.0);
    float2 v3 = float2(0.0, -bInset);

    // 5) True Euclidean signed distance with rounding offset
    float d = sdConvexPoly4(pr, v0, v1, v2, v3) - r;
    float aa = fwidth(d);

    // 6) Fill coverage (inside polygon)
    float fillMask = 1.0 - smoothstep(0.0, aa, d);
    float4 fillOut = float4(fillColor.rgb, saturate(fillColor.a) * fillMask);

    // 7) Stroke coverage (uniform band around edge)
    float halfW = 0.5 * max(strokeWidth, 0.0);
    float edge = abs(d) - halfW;
    float strokeMask = 1.0 - smoothstep(0.0, aa, edge);
    float4 strokeOut = float4(strokeColor.rgb, saturate(strokeColor.a) * strokeMask);

    // 8) Composite: stroke OVER fill
    outColor = nm_over(strokeOut, fillOut);
}

//==========================================================================
//  Procedural Primitive – Trapezoid (Rounded) + Color + Outline + Rotation
//  Author: Niloufar Moradijam
//  File: TrapezoidRoundedColorOutlineCenteredRotated.hlsl
//
//  Description
//  ------------------------------------------------------------------------
//  **Rotatable**, centered **rounded isosceles trapezoid** with solid fill +
//  uniform outline, using exact convex-polygon SDF + analytic AA. The
//  **cornerRadius** fillets the polygon corners (it changes the geometry,
//  not the stroke).
//
//  Minimal Shader Graph Interface (single RGBA output)
//  ------------------------------------------------------------------------
//  Function Name : TrapezoidRoundedColorOutlineCenteredRotated01_float
//  Inputs  :
//      uv01         (float2) – UV in 0..1
//      widthBottom  (float)  – full bottom width  (UV units)
//      widthTop     (float)  – full top width     (UV units)
//      height       (float)  – full height        (UV units)
//      cornerRadius (float)  – shape corner radius (UV units)
//      center01     (float2) – trapezoid center in 0..1 UV
//      angleRad     (float)  – rotation in radians (CCW). 0 = upright
//      fillColor    (float4) – RGBA fill
//      strokeColor  (float4) – RGBA outline
//      strokeWidth  (float)  – outline thickness in UV units (total)
//  Output :
//      outColor     (float4) – RGBA (straight alpha; A = coverage)
//
//  Notes
//  ------------------------------------------------------------------------
//  • Exact rounding: build an inset polygon by shifting every edge inward by r
//    (parallel offset); inset-vertex positions come from adjacent offset-line
//    intersections. Final SDF: sdConvexPoly(insetVerts) - r.
//  • Maximum valid r is limited by the trapezoid inradius; we clamp for safety.
//  • Stroke is composited OVER the fill.
//==========================================================================

#ifndef NM_OVER_HELPER
#define NM_OVER_HELPER
inline float4 nm_over(float4 src, float4 dst)
{
    float a  = src.a + dst.a * (1.0 - src.a);
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-8);
    return float4(c, a);
}
#endif

// Distance to a segment (Euclidean)
inline float nm_distPointToSegment(float2 p, float2 a, float2 b)
{
    float2 e = b - a;
    float ee = max(dot(e, e), 1e-12);
    float t = clamp(dot(p - a, e) / ee, 0.0, 1.0);
    float2 q = a + t * e;
    return length(p - q);
}

// Exact SDF to a convex quad (CCW)
inline float nm_sdConvexPoly4(float2 p, float2 v0, float2 v1, float2 v2, float2 v3)
{
    float2 v[4] = { v0, v1, v2, v3 };

    float d2 = 1e20;
    float s = -1e20;

    [unroll]
    for (int i = 0; i < 4; ++i)
    {
        float2 a = v[i];
        float2 b = v[(i + 1) & 3];

        // outward normal for CCW (right-hand perp)
        float2 e = b - a;
        float2 n = normalize(float2(e.y, -e.x));

        d2 = min(d2, nm_distPointToSegment(p, a, b) * nm_distPointToSegment(p, a, b));
        s = max(s, dot(p - a, n));
    }
    return (s > 0.0) ? sqrt(d2) : -sqrt(d2);
}

// Intersect two lines given by dot(nA, x) = cA and dot(nB, x) = cB
inline float2 nm_intersectLines(float2 nA, float cA, float2 nB, float cB)
{
    float det = nA.x * nB.y - nA.y * nB.x;
    det = (abs(det) < 1e-8) ? (det < 0.0 ? -1e-8 : 1e-8) : det; // guard
    float x = (cA * nB.y - nA.y * cB) / det;
    float y = (-cA * nB.x + nA.x * cB) / det;
    return float2(x, y);
}

// Build inset (offset by +r inward) vertices for an isosceles trapezoid
inline void nm_trapezoidInsetVerts(
    float a, float b, float h, float r,
    out float2 iv0, out float2 iv1, out float2 iv2, out float2 iv3)
{
    // Base vertices (CCW): bottom-left, bottom-right, top-right, top-left
    float2 v0 = float2(-b, -h);
    float2 v1 = float2(b, -h);
    float2 v2 = float2(a, h);
    float2 v3 = float2(-a, h);

    // Edge directions (v_i -> v_{i+1})
    float2 e0 = v1 - v0; // bottom
    float2 e1 = v2 - v1; // right slanted
    float2 e2 = v3 - v2; // top
    float2 e3 = v0 - v3; // left slanted

    // CCW outward unit normals
    float2 n0 = normalize(float2(e0.y, -e0.x)); // bottom
    float2 n1 = normalize(float2(e1.y, -e1.x)); // right
    float2 n2 = normalize(float2(e2.y, -e2.x)); // top
    float2 n3 = normalize(float2(e3.y, -e3.x)); // left

    // Line constants: dot(n_i, x) = c_i  (through v_i)
    float c0 = dot(n0, v0);
    float c1 = dot(n1, v1);
    float c2 = dot(n2, v2);
    float c3 = dot(n3, v3);

    // Inset (move each line inward by r along its inward normal, i.e., -n)
    float c0i = c0 - r;
    float c1i = c1 - r;
    float c2i = c2 - r;
    float c3i = c3 - r;

    // Inset vertices are intersections of adjacent inset lines (CCW order)
    iv0 = nm_intersectLines(n3, c3i, n0, c0i); // between left & bottom
    iv1 = nm_intersectLines(n0, c0i, n1, c1i); // between bottom & right
    iv2 = nm_intersectLines(n1, c1i, n2, c2i); // between right & top
    iv3 = nm_intersectLines(n2, c2i, n3, c3i); // between top & left
}

//------------------------------------------------------------------------------
// TrapezoidRoundedColorOutlineCenteredRotated01_float
//------------------------------------------------------------------------------
void TrapezoidRoundedColorOutlineCenteredRotated01_float(
    float2 uv01, // 0..1 UV
    float widthBottom, // full bottom width  (UV units)
    float widthTop, // full top width     (UV units)
    float height, // full height        (UV units)
    float cornerRadius, // UV units (shape rounding)
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

    // 3) Half-sizes
    float a = 0.5 * max(widthTop, 0.0);
    float b = 0.5 * max(widthBottom, 0.0);
    float h = 0.5 * max(height, 0.0);

    // 4) Compute a conservative inradius for clamping r
    //    Inradius = min distance from center to any edge (exact for isosceles)
    //    Bottom/top: h; sides: distance from origin to the side lines.
    float2 v1 = float2(b, -h);
    float2 v2 = float2(a, h);
    float2 e1 = v2 - v1;
    float2 n1 = normalize(float2(e1.y, -e1.x));
    float c1 = dot(n1, v1);
    float inrSide = max(c1, 0.0); // distance from origin to side (origin is center)
    float inradius = max(0.0, min(min(h, h), inrSide)); // min of {top,bottom,side}

    float r = clamp(cornerRadius, 0.0, inradius - 1e-5);

    // 5) Build inset polygon (edges shifted inward by r), then round
    float2 iv0, iv1p, iv2, iv3;
    nm_trapezoidInsetVerts(a, b, h, r, iv0, iv1p, iv2, iv3);

    float d = nm_sdConvexPoly4(pr, iv0, iv1p, iv2, iv3) - r; // d<0 inside rounded trap

    // 6) Analytic AA
    float aa = fwidth(d);

    // 7) Fill coverage
    float fillMask = 1.0 - smoothstep(0.0, aa, d);
    float4 fillOut = float4(fillColor.rgb, saturate(fillColor.a) * fillMask);

    // 8) Stroke coverage (uniform band around rounded edge)
    float halfW = 0.5 * max(strokeWidth, 0.0);
    float edge = abs(d) - halfW;
    float strokeMask = 1.0 - smoothstep(0.0, aa, edge);
    float4 strokeOut = float4(strokeColor.rgb, saturate(strokeColor.a) * strokeMask);

    // 9) Composite: stroke OVER fill
    outColor = nm_over(strokeOut, fillOut);
}

//==========================================================================
//  Procedural Primitive – Pentagon (Rounded) + Color + Outline + Rotation
//  Author: Niloufar Moradijam
//  File: PentagonRoundedColorOutlineCenteredRotated.hlsl
//
//  Description
//  ------------------------------------------------------------------------
//  **Rotatable** regular pentagon (5 sides) with uniform **corner radius**
//  that affects the shape's silhouette (NOT the stroke). Uses convex polygon
//  SDF (exact Euclidean distance + half-space sign) with analytic AA.
//
//  Minimal Shader Graph Interface (single RGBA output)
//  ------------------------------------------------------------------------
//  Function Name : PentagonRoundedColorOutlineCenteredRotated01_float
//  Inputs  :
//      uv01         (float2) – UV in 0..1
//      radius       (float)  – circumradius (center→vertex) in UV units
//      cornerRadius (float)  – shape corner radius in UV units
//      center01     (float2) – pentagon center in 0..1 UV
//      angleRad     (float)  – rotation in radians (CCW). 0 = upright
//      fillColor    (float4) – RGBA fill
//      strokeColor  (float4) – RGBA outline
//      strokeWidth  (float)  – outline thickness (total) in UV units
//  Output :
//      outColor     (float4) – RGBA (straight alpha; A = coverage)
//
//  Notes
//  ------------------------------------------------------------------------
//  • Implements true geometric rounding by building an inset polygon (offset
//    inward by cornerRadius) and subtracting r from its SDF.
//  • Corner radius is clamped to avoid overlap of edges.
//  • Stroke is composited OVER the fill.
//==========================================================================


// --- Helper: perpendicular (right-hand)
inline float2 nm_perpRight(float2 e)
{
    return float2(e.y, -e.x);
}

// --- Convex polygon SDF (for N=5)
inline float nm_sdConvexPoly5(float2 p, float2 v[5])
{
    float d2 = 1e20;
    float s = -1e20;
    [unroll]
    for (int i = 0; i < 5; ++i)
    {
        float2 a = v[i];
        float2 b = v[(i + 1) % 5];
        float2 e = b - a;
        float2 n = normalize(nm_perpRight(e)); // outward normal (CCW)
        d2 = min(d2, nm_distPointToSegment(p, a, b) * nm_distPointToSegment(p, a, b));
        s = max(s, dot(p - a, n)); // max half-space
    }
    return (s > 0.0) ? sqrt(d2) : -sqrt(d2);
}

// --- Main -----------------------------------------------------------------
void PentagonRoundedColorOutlineCenteredRotated01_float(
    float2 uv01, // 0..1 UV
    float radius, // circumradius (UV units)
    float cornerRadius, // shape corner radius (UV units)
    float2 center01, // 0..1 center
    float angleRad, // radians (CCW)
    float4 fillColor, // RGBA
    float4 strokeColor, // RGBA
    float strokeWidth, // UV units (total thickness)
    out float4 outColor)
{
    // 1) Center UV space
    float2 p = uv01 - center01;

    // 2) Rotate sampling point by -angle so the shape appears rotated by +angle
    float c = cos(angleRad);
    float s = sin(angleRad);
    float2 pr = float2(c * p.x + s * p.y,
                       -s * p.x + c * p.y);

    // 3) Base pentagon vertices (CCW, upright)
    float2 v[5];
    [unroll]
    for (int i = 0; i < 5; ++i)
    {
        float ang = 0.5 * PI + (2.0 * PI * i) / 5.0;
        v[i] = radius * float2(cos(ang), sin(ang));
    }

    // 4) Clamp corner radius
    // Approximate max rounding = apothem * 0.6 (safe range for pentagon)
    float apothem = radius * cos(PI / 5.0);
    float r = clamp(cornerRadius, 0.0, apothem * 0.6);

    // 5) Compute inset vertices (move each vertex toward center by r / apothem)
    float insetFactor = (apothem - r) / apothem;
    float2 vi[5];
    [unroll]
    for (int i = 0; i < 5; ++i)
    {
        vi[i] = v[i] * insetFactor;
    }

    // 6) Rounded pentagon SDF
    float d = nm_sdConvexPoly5(pr, vi) - r;

    // 7) Analytic AA
    float aa = fwidth(d);

    // 8) Fill coverage
    float fillMask = 1.0 - smoothstep(0.0, aa, d);
    float4 fillOut = float4(fillColor.rgb, saturate(fillColor.a) * fillMask);

    // 9) Stroke coverage (uniform band)
    float halfW = 0.5 * max(strokeWidth, 0.0);
    float edge = abs(d) - halfW;
    float strokeMask = 1.0 - smoothstep(0.0, aa, edge);
    float4 strokeOut = float4(strokeColor.rgb, saturate(strokeColor.a) * strokeMask);

    // 10) Composite: stroke OVER fill
    outColor = nm_over(strokeOut, fillOut);
}

//==========================================================================
//  Procedural Primitive – Hexagon (Rounded) + Color + Outline + Rotation
//  Author: Niloufar Moradijam
//  File: HexagonRoundedColorOutlineCenteredRotated.hlsl
//
//  Description
//  ------------------------------------------------------------------------
//  **Rotatable** flat-top regular hexagon with uniform **corner radius**
//  that rounds the shape silhouette (NOT the stroke). Uses a convex-polygon
//  SDF with analytic AA. Parameters are in 0..1 UV units.
//
//  Minimal Shader Graph Interface (single RGBA output)
//  ------------------------------------------------------------------------
//  Function Name : HexagonRoundedColorOutlineCenteredRotated01_float
//  Inputs  :
//      uv01         (float2) – UV in 0..1
//      radius       (float)  – circumradius (center→vertex), UV units
//      cornerRadius (float)  – geometric corner radius, UV units
//      center01     (float2) – hexagon center in 0..1 UV
//      angleRad     (float)  – rotation in radians (CCW). 0 = flat-top
//      fillColor    (float4) – RGBA fill
//      strokeColor  (float4) – RGBA outline
//      strokeWidth  (float)  – outline thickness (total), UV units
//  Output :
//      outColor     (float4) – RGBA (straight alpha; A = coverage)
//
//  Notes
//  ------------------------------------------------------------------------
//  • True rounding via **parallel edge offset**: in a regular N-gon, moving
//    all edges inward by r reduces the apothem by r. For a hexagon:
//        apothem = R * cos(pi/6);  R_inset = (apothem - r) / cos(pi/6)
//    Final SDF uses:  d = sdHexagon(p, R_inset) - r.
//  • cornerRadius is clamped to [0, apothem] to stay valid.
//  • Stroke is composited OVER the fill.
//==========================================================================


// Signed distance to an origin-centered **flat-top** regular hexagon (circumradius = r)
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
void HexagonRoundedColorOutlineCenteredRotated01_float(
    float2 uv01, // 0..1 UV
    float radius, // circumradius (UV units)
    float cornerRadius, // geometric corner radius (UV units)
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

    // 3) Clamp r to apothem; compute inset circumradius for true rounding
    float R = max(radius, 0.0);
    const float cos30 = 0.8660254037844386; // cos(pi/6)
    float apothem = R * cos30;
    float r = clamp(cornerRadius, 0.0, apothem);
    float Rinset = (apothem - r) / cos30; // == R - r / cos30

    // 4) Rounded hexagon SDF
    float d = nm_sdHexagon(pr, max(Rinset, 0.0)) - r; // d<0 inside

    // 5) Analytic AA
    float aa = fwidth(d);

    // 6) Fill coverage
    float fillMask = 1.0 - smoothstep(0.0, aa, d);
    float4 fillOut = float4(fillColor.rgb, saturate(fillColor.a) * fillMask);

    // 7) Stroke coverage (uniform band around the rounded edge)
    float halfW = 0.5 * max(strokeWidth, 0.0);
    float edge = abs(d) - halfW;
    float strokeMask = 1.0 - smoothstep(0.0, aa, edge);
    float4 strokeOut = float4(strokeColor.rgb, saturate(strokeColor.a) * strokeMask);

    // 8) Composite: stroke OVER fill
    outColor = nm_over(strokeOut, fillOut);
}

//==========================================================================
//  Procedural Primitive – Heptagon (Rounded) + Color + Outline + Rotation
//  Author: Niloufar Moradijam
//  File: HeptagonRoundedColorOutlineCenteredRotated.hlsl
//
//  Description
//  ------------------------------------------------------------------------
//  **Rotatable** regular heptagon (7 sides) with uniform **corner radius**
//  that rounds the shape’s silhouette (NOT the stroke). Uses convex polygon
//  SDF with analytic AA. All parameters in 0..1 UV units.
//
//  Minimal Shader Graph Interface (single RGBA output)
//  ------------------------------------------------------------------------
//  Function Name : HeptagonRoundedColorOutlineCenteredRotated01_float
//  Inputs  :
//      uv01         (float2) – UV in 0..1
//      radius       (float)  – circumradius (center→vertex), UV units
//      cornerRadius (float)  – geometric corner radius, UV units
//      center01     (float2) – heptagon center in 0..1 UV
//      angleRad     (float)  – rotation in radians (CCW). 0 = upright
//      fillColor    (float4) – RGBA fill
//      strokeColor  (float4) – RGBA outline
//      strokeWidth  (float)  – outline thickness (UV units, total)
//  Output :
//      outColor     (float4) – RGBA (straight alpha; A = coverage)
//
//  Notes
//  ------------------------------------------------------------------------
//  • True rounding via edge offset: for a regular N-gon, the apothem shrinks
//    by r when all edges are offset inward by r.
//    Apothem = R * cos(π/N)
//    So inset circumradius = (Apothem – r) / cos(π/N)
//  • Valid range: cornerRadius ∈ [0, apothem].
//  • Stroke composited OVER fill.
//==========================================================================


// Signed distance to origin-centered upright regular heptagon (circumradius = r)
inline float nm_sdHeptagon(float2 p, float r)
{
    const int N = 7;
    float2 v[N];
    [unroll]
    for (int i = 0; i < N; ++i)
    {
        float ang = 0.5 * PI + (2.0 * PI * i) / (float) N; // start at top
        v[i] = r * float2(cos(ang), sin(ang));
    }

    float maxHalf = -1e9;
    float minEdge = 1e9;

    [unroll]
    for (int i = 0; i < N; ++i)
    {
        int j = (i + 1) % N;
        float2 a = v[i], b = v[j];
        float2 e = b - a;
        float2 n = normalize(nm_perpRight(e)); // outward normal
        maxHalf = max(maxHalf, dot(p - a, n));
        minEdge = min(minEdge, nm_distPointToSegment(p, a, b));
    }

    float sgn = (maxHalf <= 0.0) ? -1.0 : 1.0;
    return minEdge * sgn;
}

// --- Main -----------------------------------------------------------------
void HeptagonRoundedColorOutlineCenteredRotated01_float(
    float2 uv01, // 0..1 UV
    float radius, // circumradius (UV units)
    float cornerRadius, // shape corner radius (UV units)
    float2 center01, // 0..1 center
    float angleRad, // radians (CCW)
    float4 fillColor, // RGBA
    float4 strokeColor, // RGBA
    float strokeWidth, // UV units (total)
    out float4 outColor)
{
    // 1) Recenter in UV
    float2 p = uv01 - center01;

    // 2) Rotate sampling point by –angle (so shape appears +angle)
    float c = cos(angleRad);
    float s = sin(angleRad);
    float2 pr = float2(c * p.x + s * p.y,
                       -s * p.x + c * p.y);

    // 3) Compute insetting for true rounding
    const float N = 7.0;
    float R = max(radius, 0.0);
    float cosTerm = cos(PI / N); // for N-gon apothem
    float apothem = R * cosTerm;
    float r = clamp(cornerRadius, 0.0, apothem);
    float Rinset = (apothem - r) / cosTerm;

    // 4) Rounded heptagon SDF
    float d = nm_sdHeptagon(pr, max(Rinset, 0.0)) - r;

    // 5) Analytic AA width
    float aa = fwidth(d);

    // 6) Fill coverage (inside)
    float fillMask = 1.0 - smoothstep(0.0, aa, d);
    float4 fillOut = float4(fillColor.rgb, saturate(fillColor.a) * fillMask);

    // 7) Stroke coverage (uniform band)
    float halfW = 0.5 * max(strokeWidth, 0.0);
    float edge = abs(d) - halfW;
    float strokeMask = 1.0 - smoothstep(0.0, aa, edge);
    float4 strokeOut = float4(strokeColor.rgb, saturate(strokeColor.a) * strokeMask);

    // 8) Composite: stroke OVER fill
    outColor = nm_over(strokeOut, fillOut);
}

//==========================================================================
//  Procedural Primitive – Octagon (Rounded) + Color + Outline + Rotation
//  Author: Niloufar Moradijam
//  File: OctagonRoundedColorOutlineCenteredRotated.hlsl
//
//  Description
//  ------------------------------------------------------------------------
//  **Rotatable** regular octagon (8 sides) with uniform **corner radius**
//  that rounds the geometric silhouette (NOT the stroke). Uses convex polygon
//  SDF and analytic AA. All parameters are in 0..1 UV units.
//
//  Minimal Shader Graph Interface (single RGBA output)
//  ------------------------------------------------------------------------
//  Function Name : OctagonRoundedColorOutlineCenteredRotated01_float
//  Inputs  :
//      uv01         (float2) – UV in 0..1
//      radius       (float)  – circumradius (center→vertex), UV units
//      cornerRadius (float)  – geometric corner radius, UV units
//      center01     (float2) – octagon center in 0..1 UV
//      angleRad     (float)  – rotation in radians (CCW). 0 = upright
//      fillColor    (float4) – RGBA fill
//      strokeColor  (float4) – RGBA outline
//      strokeWidth  (float)  – outline thickness (UV units, total)
//  Output :
//      outColor     (float4) – RGBA (straight alpha; A = coverage)
//
//  Notes
//  ------------------------------------------------------------------------
//  • True geometric rounding: for a regular N-gon, apothem = R * cos(π/N).
//    Inset circumradius = (Apothem - r) / cos(π/N).
//    For N=8 → cos(π/8) ≈ 0.9239.
//  • cornerRadius is clamped to [0, apothem].
//  • Stroke is composited OVER the fill.
//==========================================================================


// Signed distance to an origin-centered upright regular octagon (circumradius = r)
inline float nm_sdOctagon(float2 p, float r)
{
    const int N = 8;
    float2 v[N];

    [unroll]
    for (int i = 0; i < N; ++i)
    {
        float ang = 0.5 * PI + (2.0 * PI * i) / (float) N; // start at top
        v[i] = r * float2(cos(ang), sin(ang));
    }

    float maxHalf = -1e9;
    float minEdge = 1e9;

    [unroll]
    for (int i = 0; i < N; ++i)
    {
        int j = (i + 1) % N;
        float2 a = v[i], b = v[j];
        float2 e = b - a;
        float2 n = normalize(nm_perpRight(e)); // outward normal
        maxHalf = max(maxHalf, dot(p - a, n));
        minEdge = min(minEdge, nm_distPointToSegment(p, a, b));
    }

    float sgn = (maxHalf <= 0.0) ? -1.0 : 1.0;
    return minEdge * sgn; // d<0 inside
}

// --- Main -----------------------------------------------------------------
void OctagonRoundedColorOutlineCenteredRotated01_float(
    float2 uv01, // 0..1 UV
    float radius, // circumradius (UV units)
    float cornerRadius, // shape corner radius (UV units)
    float2 center01, // 0..1 center
    float angleRad, // radians (CCW)
    float4 fillColor, // RGBA
    float4 strokeColor, // RGBA
    float strokeWidth, // UV units (total)
    out float4 outColor)
{
    // 1) Center in UV
    float2 p = uv01 - center01;

    // 2) Rotate sampling point by -angle so shape appears rotated by +angle
    float c = cos(angleRad);
    float s = sin(angleRad);
    float2 pr = float2(c * p.x + s * p.y,
                       -s * p.x + c * p.y);

    // 3) Compute insetting for rounded edges
    const float N = 8.0;
    float R = max(radius, 0.0);
    float cosTerm = cos(PI / N); // cos(π/8)
    float apothem = R * cosTerm;
    float r = clamp(cornerRadius, 0.0, apothem);
    float Rinset = (apothem - r) / cosTerm;

    // 4) Rounded octagon SDF
    float d = nm_sdOctagon(pr, max(Rinset, 0.0)) - r;

    // 5) Analytic AA
    float aa = fwidth(d);

    // 6) Fill coverage
    float fillMask = 1.0 - smoothstep(0.0, aa, d);
    float4 fillOut = float4(fillColor.rgb, saturate(fillColor.a) * fillMask);

    // 7) Stroke coverage (uniform band)
    float halfW = 0.5 * max(strokeWidth, 0.0);
    float edge = abs(d) - halfW;
    float strokeMask = 1.0 - smoothstep(0.0, aa, edge);
    float4 strokeOut = float4(strokeColor.rgb, saturate(strokeColor.a) * strokeMask);

    // 8) Composite: stroke OVER fill
    outColor = nm_over(strokeOut, fillOut);
}
