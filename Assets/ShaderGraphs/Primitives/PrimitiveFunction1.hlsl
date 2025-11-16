//==========================================================================
//  Procedural Primitives Library
//  Author: Niloufar Moradijam
//  File: Primitives_Circle.hlsl
//
//  Description:
//  ------------------------------------------------------------------------
//  Defines basic Signed Distance Function (SDF) and mask utilities for
//  rendering a 2D circle in shader space. This implementation follows the
//  minimal form introduced by Inigo Quilez:
//  https://iquilezles.org/articles/distfunctions2d/
//
//  The library is designed to be modular: each primitive (circle, box,
//  triangle, etc.) exposes one or more functions compatible with Unity’s
//  Shader Graph Custom Function node.
//
//  Coordinate conventions:
//  - Input coordinates (UV) are assumed to be normalized in the [0..1] range.
//  - The circle’s center is placed at (0.5, 0.5) by default.
//  - The signed distance output is negative inside the shape, positive outside.
//
//==========================================================================


//--------------------------------------------------------------------------
//  Signed Distance Function (SDF) for a circle
//--------------------------------------------------------------------------
//  Parameters:
//      p : float2  →  The 2D point to evaluate, in any coordinate space.
//      r : float   →  Circle radius, in the same units as 'p'.
//
//  Returns:
//      float       →  Signed distance from 'p' to the circle boundary.
//                     < 0 → inside the circle
//                     = 0 → exactly on the border
//                     > 0 → outside the circle
//
//  Notes:
//      This is the most compact SDF representation of a circle.
//      It computes the Euclidean distance from the point to the origin
//      (length(p)) and subtracts the desired radius.
//--------------------------------------------------------------------------
float sdCircle(float2 p, float r)
{
    return length(p) - r;
}



//--------------------------------------------------------------------------
//  Circle01_float
//--------------------------------------------------------------------------
//  Description:
//      Generates a binary mask (0 or 1) for a filled circle centered in UV space.
//
//  Parameters:
//      UV        : float2  →  Normalized texture coordinates [0..1].
//      Inside01  : out float → Output mask value:
//                                1.0 → inside the circle
//                                0.0 → outside the circle
//
//  Implementation details:
//      1. Shift UV so that the center of the texture (0.5, 0.5) becomes (0,0).
//      2. Compute signed distance using sdCircle() with radius = 0.30.
//      3. Return 1 if the signed distance is <= 0 (point inside),
//         otherwise 0.
//
//  Typical usage in Shader Graph:
//      - Create a Custom Function node.
//      - Source File: this HLSL file.
//      - Function Name: "Circle01_float".
//      - Inputs:  UV (Vector2).
//      - Outputs: Inside01 (Float).
//      - Connect Inside01 to Base Color or Alpha to visualize the shape.
//
//--------------------------------------------------------------------------
void Circle01_float(float2 UV, float r, out float Inside01)
{
    // Center UV around (0.5, 0.5)
    float2 p = UV - float2(0.5, 0.5);

    // Compute signed distance to a circle of radius r (normalized units)
    float sd = sdCircle(p, r);

    // Convert signed distance to binary mask:
    // 1.0 inside the circle, 0.0 outside.
    Inside01 = (sd <= 0.0) ? 1.0 : 0.0;
}


//==========================================================================
//  Procedural Primitives Library
//  Primitive: Box (Square)
//  Author: Niloufar Moradijam
//
//  Description:
//  ------------------------------------------------------------------------
//  Computes the Signed Distance Function (SDF) for an axis-aligned 2D box
//  (or square). This is one of the most common SDF primitives, derived
//  from Inigo Quilez’s formulation:
//  https://iquilezles.org/articles/distfunctions2d/
//
//  The output distance is negative inside the box, zero on the boundary,
//  and positive outside.
//
//==========================================================================


//--------------------------------------------------------------------------
//  Signed Distance Function for a Box
//--------------------------------------------------------------------------
//  Parameters:
//      p : float2  →  The 2D point to evaluate, relative to box center.
//      b : float2  →  The half-size of the box along each axis
//                     (b.x = half width, b.y = half height).
//
//  Returns:
//      float       →  Signed distance from 'p' to the box boundary.
//                     < 0 → inside the box
//                     = 0 → on the boundary
//                     > 0 → outside the box
//
//  Reference:
//      float sdBox(vec2 p, vec2 b)
//      {
//          vec2 d = abs(p) - b;
//          return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
//      }
//
//--------------------------------------------------------------------------
float sdBox(float2 p, float2 b)
{
    float2 d = abs(p) - b;
    // Outside distance (corner regions use Euclidean length)
    float outside = length(max(d, 0.0));
    // Inside correction (negative distance for inside)
    float inside = min(max(d.x, d.y), 0.0);
    return outside + inside;
}



//--------------------------------------------------------------------------
//  Box01_float
//--------------------------------------------------------------------------
//  Description:
//      Returns a binary mask (0 or 1) for a filled square centered in UV space.
//      This is designed for Shader Graph Custom Function integration.
//
//  Parameters:
//      UV        : float2  →  Normalized texture coordinates [0..1].
//      Inside01  : out float → 1.0 inside the box, 0.0 outside.
//
//--------------------------------------------------------------------------
void Box01_float(float2 UV, float width, out float Inside01)
{
    // Center the coordinates: move (0.5,0.5) to (0,0)
    float2 p = UV - float2(0.5, 0.5);

    // Define half-size of the box (normalized units)
    float2 halfSize = float2(width/2, width/2);

    // Compute signed distance
    float sd = sdBox(p, halfSize);

    // Binary mask: inside=1, outside=0
    Inside01 = (sd <= 0.0) ? 1.0 : 0.0;
}

//==========================================================================
//  Procedural Primitives Library
//  Primitive: Equilateral Triangle
//  Author: Niloufar Moradijam
//
//  Description:
//  ------------------------------------------------------------------------
//  Computes the Signed Distance Function (SDF) for a centered equilateral
//  triangle in 2D space. The implementation is based on Inigo Quilez’s
//  canonical SDF formulation for a regular triangle:
//
//      https://iquilezles.org/articles/distfunctions2d/
//
//  The output is a signed distance value:
//      < 0 → inside the triangle
//      = 0 → on the triangle edges
//      > 0 → outside the triangle
//
//  Coordinate conventions:
//  - The triangle is centered at the origin (0,0).
//  - Side length is normalized by the 'size' parameter.
//  - When used with UV coordinates [0..1], the triangle is placed at
//    the center of the texture (0.5, 0.5).
//
//==========================================================================


//--------------------------------------------------------------------------
//  Signed Distance Function (SDF) for an Equilateral Triangle
//--------------------------------------------------------------------------
//  Parameters:
//      p : float2  →  Point to evaluate (relative to the triangle center).
//      size : float →  Half of the triangle’s height. Controls overall scale.
//
//  Returns:
//      float → Signed distance from 'p' to the triangle boundary.
//              Negative values = inside, positive = outside.
//
//  Reference Implementation (by Inigo Quilez):
//      float sdEquilateralTriangle(vec2 p)
//      {
//          const float k = sqrt(3.0);
//          p.x = abs(p.x) - 1.0;
//          p.y = p.y + 1.0/k;
//          if (p.x + k*p.y > 0.0)
//              p = float2((p.x - k*p.y)/2.0, (-k*p.x - p.y)/2.0);
//          p.x -= clamp(p.x, -2.0, 0.0);
//          return -length(p) * sign(p.y);
//      }
//
//  Notes:
//      The math rotates and clips the coordinate system so the triangle’s
//      edges are aligned at 60° increments. The returned signed distance is
//      smooth and continuous.
//--------------------------------------------------------------------------
float sdEquilateralTriangle(float2 p, float size)
{
    // Normalize the point by desired triangle size
    p /= size;

    // Constant for equilateral geometry (tan(60°))
    const float k = 1.73205080757; // sqrt(3)

    // Fold horizontally (symmetry)
    p.x = abs(p.x) - 1.0;
    p.y = p.y + 1.0 / k;

    // Reflect across top-left edge if necessary
    if (p.x + k * p.y > 0.0)
        p = float2((p.x - k * p.y) / 2.0, (-k * p.x - p.y) / 2.0);

    // Clip bottom part (ensures the base is flat)
    p.x -= clamp(p.x, -2.0, 0.0);

    // Final signed distance (negative = inside)
    return -length(p) * sign(p.y) * size;
}



//--------------------------------------------------------------------------
//  Triangle01_float
//--------------------------------------------------------------------------
//  Description:
//      Produces a binary (0 or 1) mask for a filled equilateral triangle,
//      centered in normalized UV space. Designed for use in Unity Shader Graph.
//
//  Parameters:
//      UV        : float2  →  Normalized texture coordinates [0..1].
//      size      : float   →  Controls the overall triangle scale
//                             (in normalized units; 0.4 is typical).
//      Inside01  : out float →  Output binary mask value:
//                               1.0 → inside triangle
//                               0.0 → outside triangle.
//
//  Implementation steps:
//      1. Translate UV so that the center (0.5, 0.5) becomes the origin.
//      2. Evaluate signed distance using sdEquilateralTriangle().
//      3. Return a binary mask based on the sign of the distance.
//
//  Typical usage in Shader Graph:
//      - Create a Custom Function node.
//      - Source File: this HLSL file.
//      - Function Name: "Triangle01_float".
//      - Inputs:  UV (Vector2), size (Float).
//      - Outputs: Inside01 (Float).
//      - Connect Inside01 to Base Color or Alpha channel.
//
//--------------------------------------------------------------------------
void Triangle01_float(float2 UV, float size, out float Inside01)
{
    // Step 1: Center UV coordinates so (0.5,0.5) → (0,0)
    float2 p = UV - float2(0.5, 0.5);

    // Step 2: Compute signed distance to the equilateral triangle
    float sd = sdEquilateralTriangle(p, size);

    // Step 3: Binary mask → 1 inside, 0 outside
    Inside01 = (sd <= 0.0) ? 1.0 : 0.0;
}


//==========================================================================
//  Procedural Primitives Library
//  Primitive: Rectangle
//  Author: Niloufar Moradijam
//
//  Description:
//  ------------------------------------------------------------------------
//  Computes the Signed Distance Function (SDF) for an axis-aligned 2D
//  rectangle with independently adjustable width and height.
//
//  This is a generalization of the square (box) primitive. The code is based
//  on Inigo Quilez’s canonical formulation for rectangular SDFs:
//
//      https://iquilezles.org/articles/distfunctions2d/
//
//  Output interpretation:
//      < 0 → inside the rectangle
//      = 0 → on the rectangle edges
//      > 0 → outside the rectangle
//
//  Coordinate conventions:
//  - The rectangle is centered at the origin (0,0).
//  - Width and height are normalized in the same units as the input point.
//  - When used with UV coordinates [0..1], the rectangle will be centered
//    at (0.5, 0.5) by default.
//==========================================================================


//--------------------------------------------------------------------------
//  Signed Distance Function (SDF) for a Rectangle
//--------------------------------------------------------------------------
//  Parameters:
//      p : float2  →  The 2D point to evaluate (relative to the rectangle center).
//      halfSize : float2 → Half-dimensions of the rectangle
//                          (x = half width, y = half height).
//
//  Returns:
//      float → Signed distance from 'p' to the rectangle boundary.
//              Negative values → inside the rectangle
//              Zero → on the border
//              Positive → outside the rectangle
//
//  Reference function:
//      float sdBox(vec2 p, vec2 b)
//      {
//          vec2 d = abs(p) - b;
//          return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
//      }
//
//--------------------------------------------------------------------------
float sdRectangle(float2 p, float2 halfSize)
{
    // Measure how far the point is beyond each edge
    float2 d = abs(p) - halfSize;

    // Outside distance: Euclidean length of overflow beyond edges
    float outside = length(max(d, 0.0));

    // Inside correction: negative distance when point is inside the box
    float inside = min(max(d.x, d.y), 0.0);

    // Combine inside and outside components
    return outside + inside;
}



//--------------------------------------------------------------------------
//  Rectangle01_float
//--------------------------------------------------------------------------
//  Description:
//      Produces a binary mask (0 or 1) for a filled rectangle centered in
//      normalized UV space. Designed for Shader Graph integration.
//
//  Parameters:
//      UV        : float2  →  Normalized texture coordinates [0..1].
//      width     : float   →  Full rectangle width (normalized units).
//      height    : float   →  Full rectangle height (normalized units).
//      Inside01  : out float → Binary mask value
//                               (1 = inside rectangle, 0 = outside).
//
//  Implementation steps:
//      1. Translate UV so (0.5, 0.5) → (0,0).
//      2. Compute halfSize = (width/2, height/2).
//      3. Evaluate SDF.
//      4. Output 1 when sd ≤ 0, otherwise 0.
//
//  Typical usage in Shader Graph:
//      - Create a Custom Function node.
//      - Source File: this HLSL file.
//      - Function Name: "Rectangle01_float".
//      - Inputs:  UV (Vector2), width (Float), height (Float).
//      - Output:  Inside01 (Float).
//      - Connect Inside01 → Base Color or Alpha.
//--------------------------------------------------------------------------
void Rectangle01_float(float2 UV, float width, float height, out float Inside01)
{
    // Step 1: Center UV so that (0.5, 0.5) becomes origin
    float2 p = UV - float2(0.5, 0.5);

    // Step 2: Define half-size vector
    float2 halfSize = float2(width * 0.5, height * 0.5);

    // Step 3: Compute signed distance
    float sd = sdRectangle(p, halfSize);

    // Step 4: Convert to binary mask
    Inside01 = (sd <= 0.0) ? 1.0 : 0.0;
}

//==========================================================================
//  Procedural Primitives Library
//  Primitive: Rhombus (Diamond)
//  Author: Niloufar Moradijam
//
//  Description:
//  ------------------------------------------------------------------------
//  Signed Distance Function (SDF) for an axis-aligned rhombus (a.k.a.
//  diamond/lozenge). The rhombus is centered at the origin, with half
//  diagonals (a, b): 2a horizontally and 2b vertically.
//
//  Reference:
//  Based on Inigo Quilez’s exact rhombus SDF.
//  https://iquilezles.org/articles/distfunctions2d/
//
//  Output of SDF:
//      < 0 → inside the rhombus
//      = 0 → on the border
//      > 0 → outside
//
//  Coordinate conventions:
//  - p is expressed relative to the rhombus center (0,0).
//  - halfDiag = (a, b) where:
//        a = half of the horizontal diagonal (controls width)
//        b = half of the vertical   diagonal (controls height)
//==========================================================================


//--------------------------------------------------------------------------
//  sdRhombus
//--------------------------------------------------------------------------
//  Parameters:
//      p        : float2  →  point to evaluate (relative to center)
//      halfDiag : float2  →  (a, b) = half diagonals
//
//  Returns:
//      float → signed Euclidean distance to rhombus boundary
//
//  Notes:
//  The math folds the point to the first quadrant, computes the closest
//  point on the rhombus boundary using a clamped linear parameter h, and
//  then restores the sign to indicate inside/outside.
//--------------------------------------------------------------------------
float sdRhombus(float2 p, float2 halfDiag)
{
    // Work in first quadrant (use symmetry)
    p = abs(p);

    // Precompute dot products
    float bb = dot(halfDiag, halfDiag);

    // Param that slides along the two slanted edges (clamped to [-1, 1])
    float h = clamp( (-2.0 * dot(p, halfDiag) + bb) / bb, -1.0, 1.0 );

    // Closest point on the boundary in the folded space
    float2 q = p - 0.5 * halfDiag * float2(1.0 - h, 1.0 + h);

    // Unsigned distance in folded space; sign fixes inside/outside
    float unsignedDist = length(q);

    // Recover sign: negative inside, positive outside
    float s = (p.x * halfDiag.y + p.y * halfDiag.x - halfDiag.x * halfDiag.y) >= 0.0 ? 1.0 : -1.0;

    return unsignedDist * s;
}



//--------------------------------------------------------------------------
//  Rhombus01_float
//--------------------------------------------------------------------------
//  Description:
//      Binary mask (0/1) for a filled rhombus centered in UV space.
//      Designed for Unity Shader Graph Custom Function.
//
//  Parameters:
//      UV        : float2  → normalized texture coordinates [0..1]
//      a         : float   → half horizontal diagonal (controls width)
//      b         : float   → half vertical   diagonal (controls height)
//      Inside01  : out float → 1.0 inside, 0.0 outside
//
//  Usage in Shader Graph:
//      - Source File: this HLSL
//      - Function:    "Rhombus01_float"
//      - Inputs:      UV (Vector2), a (Float), b (Float)
//      - Output:      Inside01 (Float)
//      - Wire Inside01 to BaseColor/Alpha as desired.
//--------------------------------------------------------------------------
void Rhombus01_float(float2 UV, float a, float b, out float Inside01)
{
    // Center UV so (0.5,0.5) → (0,0)
    float2 p = UV - float2(0.5, 0.5);

    // Signed distance to rhombus
    float sd = sdRhombus(p, float2(a, b));

    // Binary mask
    Inside01 = (sd <= 0.0) ? 1.0 : 0.0;
}

//==========================================================================
//  Procedural Primitives Library
//  Primitive: Parallelogram
//  Author: Niloufar Moradijam
//
//  Description
//  ------------------------------------------------------------------------
//  Binary and anti-aliased masks for a 2D parallelogram defined by one
//  corner and two side vectors. Matches the Desmos construction:
//
//      P = A + s*u + t*v,    0 ≤ s ≤ 1,  0 ≤ t ≤ 1
//
//  Coordinate conventions
//  - All inputs are in the same 2D space (e.g., centered UVs or world).
//  - Typical UV usage: UV in [0..1]; center with (UV - 0.5) so A,u,v live
//    in a centered, normalized space.
//==========================================================================

inline float det2(float2 a, float2 b) { return a.x*b.y - a.y*b.x; }

//--------------------------------------------------------------------------
//  Parallelogram01_float  (exact binary mask)
//--------------------------------------------------------------------------
//  Parameters:
//      UV       : float2 → input point (e.g., normalized UVs).
//      A        : float2 → one corner of the parallelogram (same space as UV).
//      u, v     : float2 → side vectors spanning the shape.
//      Inside01 : out float → 1.0 inside, 0.0 outside.
//
//  Notes:
//  - For UV use, first center: p = UV - (0.5, 0.5), then pass A,u,v in that
//    same centered space. If you prefer, bake the centering into 'A' itself.
//--------------------------------------------------------------------------
void Parallelogram01_float(float2 UV, float2 A, float2 u, float2 v, out float Inside01)
{
    // Evaluate at point p (center UV if you want a centered layout)
    float2 p = UV - float2(0.5, 0.5);

    // Solve p = A + s*u + t*v  →  find (s,t) via 2x2 inverse using determinants
    float2 r = p - A;
    float  D = det2(u, v);      // parallelogram area scale (must be non-zero)
    float  invD = 1.0 / D;

    float  s = det2(r, v) * invD;
    float  t = det2(u, r) * invD;

    // Exact inside test: 0≤s≤1 and 0≤t≤1
    Inside01 = (s >= 0.0 && s <= 1.0 && t >= 0.0 && t <= 1.0) ? 1.0 : 0.0;
}


//==========================================================================
//  Procedural Primitives Library
//  Primitive: Ellipse (axis-aligned, centered)
//  Author: Niloufar Moradijam
//
//  Description
//  ------------------------------------------------------------------------
//  Axis-aligned ellipse centered at the origin with full size (width, height).
//  We provide a *signed pseudo-distance* based on the implicit ellipse:
//      F(x,y) = (x^2/a^2) + (y^2/b^2) - 1
//  and the gradient magnitude:
//      ||∇F|| = 2 * sqrt( (x^2/a^4) + (y^2/b^4) )
//
//  Signed pseudo-distance:
//      sd ≈ F / ||∇F||
//  This yields correct sign (inside<0, outside>0) and near-uniform AA.
//  (Exact Euclidean distance to an ellipse is expensive; this is the
//   standard high-quality approximation used in real-time SDF work.)
//
//  Output meanings:
//    sd < 0  → inside ellipse
//    sd = 0  → on the boundary
//    sd > 0  → outside
//==========================================================================


//--------------------------------------------------------------------------
//  sdEllipseApprox
//--------------------------------------------------------------------------
//  Parameters:
//      p        : float2  → point to evaluate, relative to ellipse center
//      halfAxes : float2  → (a,b) = (width/2, height/2)
//
//  Returns:
//      float → signed pseudo-distance to the ellipse boundary
//--------------------------------------------------------------------------
float sdEllipseApprox(float2 p, float2 halfAxes)
{
    // Half-axes
    float a = max(halfAxes.x, 1e-8); // avoid division by zero
    float b = max(halfAxes.y, 1e-8);

    // Implicit function F = (x^2/a^2) + (y^2/b^2) - 1
    float x = p.x, y = p.y;
    float aa = a * a, bb = b * b;

    float F  = (x * x) / aa + (y * y) / bb - 1.0;

    // ||∇F|| = 2 * sqrt( (x^2/a^4) + (y^2/b^4) )
    float gradLen = 2.0 * sqrt( (x * x) / (aa * aa) + (y * y) / (bb * bb) );

    // Pseudo-distance; fall back to signed F when very close to center
    // to avoid 0/0 if p == (0,0)
    float sd = (gradLen > 1e-8) ? (F / gradLen) : -min(a, b);

    return sd;
}


//--------------------------------------------------------------------------
//  Ellipse01_float  (binary mask)
//--------------------------------------------------------------------------
//  Description:
//      Produces a binary 0/1 mask for a filled ellipse centered in UV space.
//
//  Parameters:
//      UV        : float2 → normalized texture coordinates [0..1]
//      width     : float  → full width  of the ellipse (normalized units)
//      height    : float  → full height of the ellipse (normalized units)
//      Inside01  : out float → 1 inside, 0 outside
//
//  Shader Graph wiring:
//      - Function: "Ellipse01_float"
//      - Inputs :  UV (Vector2), width (Float), height (Float)
//      - Output :  Inside01 (Float)
//--------------------------------------------------------------------------
void Ellipse01_float(float2 UV, float width, float height, out float Inside01)
{
    // Center UV: (0.5,0.5) → (0,0)
    float2 p = UV - float2(0.5, 0.5);

    float2 halfAxes = float2(width * 0.5, height * 0.5);

    float sd = sdEllipseApprox(p, halfAxes);

    Inside01 = (sd <= 0.0) ? 1.0 : 0.0;
}


//==========================================================================
//  Procedural Primitives Library
//  Primitive: Trapezoid (centered, isosceles, axis-aligned)
//  Author: Niloufar Moradijam
//
//  Description
//  ------------------------------------------------------------------------
//  Signed distance for a centered trapezoid with independent top/bottom
//  widths. The SDF is computed using a general convex-polygon method:
//  - Build the 4 vertices in CCW order.
//  - For sign: take the maximum of outward half-space distances.
//  - For magnitude: take the minimum Euclidean distance to any edge segment.
//
//  Output:
//      < 0 → inside trapezoid
//      = 0 → on the border
//      > 0 → outside
//
//  Coordinate conventions
//  - The shape is centered at (0,0).
//  - Top edge is at y = +height/2 with half-width a = widthTop/2.
//  - Bottom edge is at y = −height/2 with half-width b = widthBottom/2.
//  - Vertices are CCW to make outward normals well-defined.
//==========================================================================

inline float2 perpRight(float2 e) { return float2(e.y, -e.x); } // right-hand perp

// Distance from point p to segment [v0,v1] (unsigned)
float distPointToSegment(float2 p, float2 v0, float2 v1)
{
    float2 e  = v1 - v0;
    float  t  = dot(p - v0, e) / max(dot(e,e), 1e-12);
    t = clamp(t, 0.0, 1.0);
    float2 q = v0 + t * e;
    return length(p - q);
}

//--------------------------------------------------------------------------
//  sdTrapezoid_Centered
//--------------------------------------------------------------------------
//  Parameters:
//      p           : float2 → point to evaluate (relative to trapezoid center)
//      widthBottom : float  → full width at bottom  (y = -height/2)
//      widthTop    : float  → full width at top     (y = +height/2)
//      height      : float  → full height
//
//  Returns:
//      float → signed distance to trapezoid boundary
//--------------------------------------------------------------------------
float sdTrapezoid_Centered(float2 p, float widthBottom, float widthTop, float height)
{
    // Half-dimensions
    float a = 0.5 * widthTop;      // half top width
    float b = 0.5 * widthBottom;   // half bottom width
    float h = 0.5 * height;        // half height

    // CCW vertices:   v0 → v1 → v2 → v3 → v0
    // bottom-left, bottom-right, top-right, top-left
    float2 v0 = float2(-b, -h);
    float2 v1 = float2( b, -h);
    float2 v2 = float2( a,  h);
    float2 v3 = float2(-a,  h);

    // Edges
    float2 E0 = v1 - v0;
    float2 E1 = v2 - v1;
    float2 E2 = v3 - v2;
    float2 E3 = v0 - v3;

    // Outward unit normals (for CCW polygon, right-hand perpendiculars point outward)
    float2 n0 = normalize(perpRight(E0));
    float2 n1 = normalize(perpRight(E1));
    float2 n2 = normalize(perpRight(E2));
    float2 n3 = normalize(perpRight(E3));

    // Signed half-space distances (positive outside, ~0 on edge, negative inside)
    float d0 = dot(n0, p - v0);
    float d1 = dot(n1, p - v1);
    float d2 = dot(n2, p - v2);
    float d3 = dot(n3, p - v3);

    // Inside test for convex polygon: max(d_i) ≤ 0
    float sgn = (max(max(d0, d1), max(d2, d3)) <= 0.0) ? -1.0 : 1.0;

    // Unsigned distance to boundary: min distance to any edge segment
    float du = min(
                   min(distPointToSegment(p, v0, v1),
                       distPointToSegment(p, v1, v2)),
                   min(distPointToSegment(p, v2, v3),
                       distPointToSegment(p, v3, v0))
                 );

    return du * sgn;
}


//--------------------------------------------------------------------------
//  Trapezoid01_float  (Shader Graph binary mask)
//--------------------------------------------------------------------------
//  Description:
//      Produces a 0/1 mask for a centered trapezoid in UV space.
//      Centering: we subtract (0.5,0.5) from UV so the shape is at the origin.
//
//  Parameters:
//      UV          : float2 → normalized [0..1] texture coordinates
//      widthBottom : float  → full bottom width  (UV units)
//      widthTop    : float  → full top width     (UV units)
//      height      : float  → full height        (UV units)
//      Inside01    : out float → 1 inside, 0 outside
//
//  Shader Graph wiring:
//      - Function: "Trapezoid01_float"
//      - Inputs :  UV (Vector2), widthBottom (Float), widthTop (Float), height (Float)
//      - Output :  Inside01 (Float)
//--------------------------------------------------------------------------
void Trapezoid01_float(float2 UV, float widthBottom, float widthTop, float height, out float Inside01)
{
    float2 p = UV - float2(0.5, 0.5);
    float sd = sdTrapezoid_Centered(p, widthBottom, widthTop, height);
    Inside01 = (sd <= 0.0) ? 1.0 : 0.0;
}


//--------------------------------------------------------------------------
//  TrapezoidAA_float  (anti-aliased mask)
//--------------------------------------------------------------------------
//  Description:
//      Smooth (feathered) mask using screen-space derivatives on the SDF.
//
//  Parameters:
//      UV          : float2
//      widthBottom : float
//      widthTop    : float
//      height      : float
//      edgeSoft    : float   → minimum feather (e.g., 0.001)
//      Mask        : out float → smooth mask (~1 inside, ~0 outside)
//--------------------------------------------------------------------------
void TrapezoidAA_float(float2 UV, float widthBottom, float widthTop, float height, float edgeSoft, out float Mask)
{
    float2 p = UV - float2(0.5, 0.5);
    float sd = sdTrapezoid_Centered(p, widthBottom, widthTop, height);

    float aa = max(edgeSoft, fwidth(sd));      // adaptive AA
    Mask = 1.0 - smoothstep(0.0, aa, sd);      // sd=0 is the border
}


//==========================================================================
//  Procedural Primitives Library
//  Primitive: Regular Pentagon (centered, no rotation)
//  Author: Niloufar Moradijam
//
//  Description
//  ------------------------------------------------------------------------
//  Signed distance for a centered, upright regular pentagon.
//  The pentagon is built symmetrically around the Y-axis with one vertex
//  pointing upward (flat base at the bottom).
//
//  Output:
//      < 0 → inside
//      = 0 → on border
//      > 0 → outside
//
//  Coordinate conventions
//  - Centered at origin (0,0).
//  - Circumradius = radius (distance from center to each vertex).
//  - In UV space: subtract (0.5,0.5) to center the shape.
//==========================================================================

#ifndef PI
#define PI 3.14159265359
#endif


//--------------------------------------------------------------------------
//  sdPentagon_Centered
//--------------------------------------------------------------------------
//  Parameters:
//      p      : float2 → point to evaluate (relative to center)
//      radius : float  → distance from center to each vertex
//
//  Returns:
//      float → signed distance to pentagon boundary
//--------------------------------------------------------------------------
float sdPentagon_Centered(float2 p, float radius)
{
    // Compute the five vertices (CCW), upright orientation (flat base at bottom)
    float2 v[5];
    [unroll]
    for (int i = 0; i < 5; ++i)
    {
        float angle = PI * 0.5 + (2.0 * PI * i) / 5.0; // start at top vertex
        v[i] = radius * float2(cos(angle), sin(angle));
    }

    float maxHalfSpace = -1e9;
    float minEdgeDist  =  1e9;

    [unroll]
    for (int i = 0; i < 5; ++i)
    {
        int j = (i + 1) % 5;
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



//--------------------------------------------------------------------------
//  Pentagon01_float (Shader Graph binary mask)
//--------------------------------------------------------------------------
//  Description:
//      Binary 0/1 mask for a centered, upright regular pentagon.
//
//  Parameters:
//      UV       : float2 → normalized [0..1] texture coordinates
//      radius   : float  → circumradius (e.g., 0.35)
//      Inside01 : out float → 1.0 inside, 0.0 outside
//
//--------------------------------------------------------------------------
void Pentagon01_float(float2 UV, float radius, out float Inside01)
{
    float2 p = UV - float2(0.5, 0.5);
    float sd = sdPentagon_Centered(p, radius);
    Inside01 = (sd <= 0.0) ? 1.0 : 0.0;
}



//--------------------------------------------------------------------------
//  PentagonAA_float (anti-aliased mask)
//--------------------------------------------------------------------------
//  Description:
//      Smooth 0–1 mask for a centered upright pentagon, with screen-space AA.
//
//  Parameters:
//      UV       : float2 → normalized [0..1]
//      radius   : float  → circumradius (e.g., 0.35)
//      edgeSoft : float  → minimum feather width (e.g., 0.001)
//      Mask     : out float → 1 inside, 0 outside (smooth edges)
//
//--------------------------------------------------------------------------
void PentagonAA_float(float2 UV, float radius, float edgeSoft, out float Mask)
{
    float2 p = UV - float2(0.5, 0.5);
    float sd = sdPentagon_Centered(p, radius);

    float aa = max(edgeSoft, fwidth(sd));
    Mask = 1.0 - smoothstep(0.0, aa, sd);
}

//==========================================================================
//  Procedural Primitives Library
//  Primitive: Regular Hexagon (centered, no rotation)
//  Author: Niloufar Moradijam
//
//  Description
//  ------------------------------------------------------------------------
//  Signed distance for a centered, upright regular hexagon (flat top).
//  The hexagon is built symmetrically around the Y-axis and centered at
//  the origin (0,0).
//
//  Output:
//      < 0 → inside the hexagon
//      = 0 → on the border
//      > 0 → outside
//
//  Coordinate conventions
//  - Centered at origin (0,0).
//  - Circumradius = radius (distance from center to each vertex).
//  - In UV space: subtract (0.5,0.5) to center the shape.
//
//==========================================================================



//--------------------------------------------------------------------------
//  sdHexagon_Centered
//--------------------------------------------------------------------------
//  Parameters:
//      p      : float2 → point to evaluate (relative to center)
//      radius : float  → distance from center to each vertex (circumradius)
//
//  Returns:
//      float → signed distance to hexagon boundary
//--------------------------------------------------------------------------
float sdHexagon_Centered(float2 p, float radius)
{
    // Build 6 vertices CCW (flat top orientation)
    float2 v[6];
    [unroll]
    for (int i = 0; i < 6; ++i)
    {
        float angle = PI / 6.0 + (PI / 3.0) * i; // starts at 30° to make top flat
        v[i] = radius * float2(cos(angle), sin(angle));
    }

    float maxHalfSpace = -1e9;
    float minEdgeDist  =  1e9;

    [unroll]
    for (int i = 0; i < 6; ++i)
    {
        int j = (i + 1) % 6;
        float2 e = v[j] - v[i];
        float2 n = normalize(perpRight(e)); // outward normal
        float di = dot(n, p - v[i]);
        maxHalfSpace = max(maxHalfSpace, di);
        float du = distPointToSegment(p, v[i], v[j]);
        minEdgeDist = min(minEdgeDist, du);
    }

    float sgn = (maxHalfSpace <= 0.0) ? -1.0 : 1.0;
    return minEdgeDist * sgn;
}



//--------------------------------------------------------------------------
//  Hexagon01_float (Shader Graph binary mask)
//--------------------------------------------------------------------------
//  Description:
//      Binary 0/1 mask for a centered, upright regular hexagon.
//
//  Parameters:
//      UV       : float2 → normalized [0..1] texture coordinates
//      radius   : float  → circumradius (e.g., 0.35)
//      Inside01 : out float → 1.0 inside, 0.0 outside
//
//--------------------------------------------------------------------------
void Hexagon01_float(float2 UV, float radius, out float Inside01)
{
    float2 p = UV - float2(0.5, 0.5);
    float sd = sdHexagon_Centered(p, radius);
    Inside01 = (sd <= 0.0) ? 1.0 : 0.0;
}



//--------------------------------------------------------------------------
//  HexagonAA_float (Shader Graph anti-aliased mask)
//--------------------------------------------------------------------------
//  Description:
//      Smooth 0–1 mask for a centered, upright regular hexagon,
//      with screen-space anti-aliasing.
//
//  Parameters:
//      UV       : float2 → normalized [0..1]
//      radius   : float  → circumradius (e.g., 0.35)
//      edgeSoft : float  → minimum feather width (e.g., 0.001)
//      Mask     : out float → 1 inside, 0 outside (smooth edges)
//
//--------------------------------------------------------------------------
void HexagonAA_float(float2 UV, float radius, float edgeSoft, out float Mask)
{
    float2 p = UV - float2(0.5, 0.5);
    float sd = sdHexagon_Centered(p, radius);

    float aa = max(edgeSoft, fwidth(sd));
    Mask = 1.0 - smoothstep(0.0, aa, sd);
}

//==========================================================================
//  Procedural Primitives Library
//  Primitive: Regular Heptagon (centered, no rotation)
//  Author: Niloufar Moradijam
//
//  Description
//  ------------------------------------------------------------------------
//  Signed distance for a centered, upright regular heptagon (7-sided polygon).
//  The shape is built symmetrically around the Y-axis and centered at the
//  origin (0,0).
//
//  Output:
//      < 0 → inside the heptagon
//      = 0 → on the border
//      > 0 → outside
//
//  Coordinate conventions
//  - Centered at origin (0,0).
//  - Circumradius = radius (distance from center to each vertex).
//  - In UV space: subtract (0.5,0.5) to center the shape.
//==========================================================================

//--------------------------------------------------------------------------
//  sdHeptagon_Centered
//--------------------------------------------------------------------------
//  Parameters:
//      p      : float2 → point to evaluate (relative to center)
//      radius : float  → distance from center to each vertex (circumradius)
//
//  Returns:
//      float → signed distance to heptagon boundary
//--------------------------------------------------------------------------
float sdHeptagon_Centered(float2 p, float radius)
{
    const int N = 7;
    float2 v[N];

    // Build vertices CCW; start at top (vertex on +Y axis)
    [unroll]
    for (int i = 0; i < N; ++i)
    {
        float angle = PI * 0.5 + (2.0 * PI * i) / (float)N;
        v[i] = radius * float2(cos(angle), sin(angle));
    }

    float maxHalfSpace = -1e9;
    float minEdgeDist  =  1e9;

    [unroll]
    for (int i = 0; i < N; ++i)
    {
        int j = (i + 1) % N;
        float2 e = v[j] - v[i];
        float2 n = normalize(perpRight(e)); // outward normal
        float di = dot(n, p - v[i]);
        maxHalfSpace = max(maxHalfSpace, di);
        float du = distPointToSegment(p, v[i], v[j]);
        minEdgeDist = min(minEdgeDist, du);
    }

    float sgn = (maxHalfSpace <= 0.0) ? -1.0 : 1.0;
    return minEdgeDist * sgn;
}



//--------------------------------------------------------------------------
//  Heptagon01_float (Shader Graph binary mask)
//--------------------------------------------------------------------------
//  Description:
//      Binary 0/1 mask for a centered, upright regular heptagon.
//
//  Parameters:
//      UV       : float2 → normalized [0..1] texture coordinates
//      radius   : float  → circumradius (e.g., 0.35)
//      Inside01 : out float → 1.0 inside, 0.0 outside
//-------------------------------------------------------------------------- 
void Heptagon01_float(float2 UV, float radius, out float Inside01)
{
    float2 p = UV - float2(0.5, 0.5);
    float sd = sdHeptagon_Centered(p, radius);
    Inside01 = (sd <= 0.0) ? 1.0 : 0.0;
}



//--------------------------------------------------------------------------
//  HeptagonAA_float (Shader Graph anti-aliased mask)
//--------------------------------------------------------------------------
//  Description:
//      Smooth 0–1 mask for a centered, upright regular heptagon,
//      with screen-space anti-aliasing.
//
//  Parameters:
//      UV       : float2 → normalized [0..1]
//      radius   : float  → circumradius (e.g., 0.35)
//      edgeSoft : float  → minimum feather width (e.g., 0.001)
//      Mask     : out float → 1 inside, 0 outside (smooth edges)
//--------------------------------------------------------------------------
void HeptagonAA_float(float2 UV, float radius, float edgeSoft, out float Mask)
{
    float2 p = UV - float2(0.5, 0.5);
    float sd = sdHeptagon_Centered(p, radius);

    float aa = max(edgeSoft, fwidth(sd));
    Mask = 1.0 - smoothstep(0.0, aa, sd);
}

//==========================================================================
//  Procedural Primitives Library
//  Primitive: Regular Octagon (centered, no rotation)
//  Author: Niloufar Moradijam
//
//  Description
//  ------------------------------------------------------------------------
//  Signed distance for a centered, upright regular octagon (8-sided).
//  The shape is symmetric about the Y-axis and centered at the origin.
//  Output:  sd < 0 → inside,  sd = 0 → on border,  sd > 0 → outside.
//
//  Conventions
//  - Center at (0,0).
//  - 'radius' = circumradius (center → each vertex).
//  - In UV space: subtract (0.5,0.5) to center.
//==========================================================================


//--------------------------------------------------------------------------
//  sdOctagon_Centered
//--------------------------------------------------------------------------
//  Parameters:
//      p      : float2 → point to evaluate (relative to center)
//      radius : float  → circumradius (distance center → vertex)
//
//  Returns:
//      float → signed distance to octagon boundary
//--------------------------------------------------------------------------
float sdOctagon_Centered(float2 p, float radius)
{
    const int N = 8;
    float2 v[N];

    // Build vertices CCW; start at top (vertex on +Y axis) → upright octagon
    [unroll]
    for (int i = 0; i < N; ++i)
    {
        float angle = PI * 0.5 + (2.0 * PI * i) / (float)N;
        v[i] = radius * float2(cos(angle), sin(angle));
    }

    float maxHalfSpace = -1e9;
    float minEdgeDist  =  1e9;

    [unroll]
    for (int i = 0; i < N; ++i)
    {
        int j = (i + 1) % N;
        float2 e = v[j] - v[i];
        float2 n = normalize(perpRight(e));   // outward normal for CCW polygon
        float di = dot(n, p - v[i]);          // >0 outside that edge
        maxHalfSpace = max(maxHalfSpace, di);

        float du = distPointToSegment(p, v[i], v[j]); // unsigned edge distance
        minEdgeDist = min(minEdgeDist, du);
    }

    // Inside if all half-space distances ≤ 0
    float sgn = (maxHalfSpace <= 0.0) ? -1.0 : 1.0;
    return minEdgeDist * sgn;
}



//--------------------------------------------------------------------------
//  Octagon01_float  (Shader Graph binary mask)
//--------------------------------------------------------------------------
//  Description:
//      Binary 0/1 mask for a centered upright regular octagon.
//
//  Parameters:
//      UV       : float2 → normalized [0..1] texture coordinates
//      radius   : float  → circumradius (e.g., 0.35)
//      Inside01 : out float → 1.0 inside, 0.0 outside
//--------------------------------------------------------------------------
void Octagon01_float(float2 UV, float radius, out float Inside01)
{
    float2 p = UV - float2(0.5, 0.5);
    float sd = sdOctagon_Centered(p, radius);
    Inside01 = (sd <= 0.0) ? 1.0 : 0.0;
}



//--------------------------------------------------------------------------
//  OctagonAA_float  (Shader Graph anti-aliased mask)
//--------------------------------------------------------------------------
//  Description:
//      Smooth 0–1 mask for the centered upright octagon using screen-space AA.
//
//  Parameters:
//      UV       : float2 → normalized [0..1]
//      radius   : float  → circumradius (e.g., 0.35)
//      edgeSoft : float  → minimum feather width (e.g., 0.001)
//      Mask     : out float → ~1 inside, ~0 outside (feathered edges)
//--------------------------------------------------------------------------
void OctagonAA_float(float2 UV, float radius, float edgeSoft, out float Mask)
{
    float2 p = UV - float2(0.5, 0.5);
    float sd = sdOctagon_Centered(p, radius);

    float aa = max(edgeSoft, fwidth(sd));
    Mask = 1.0 - smoothstep(0.0, aa, sd);   // sd=0 is the border
}

