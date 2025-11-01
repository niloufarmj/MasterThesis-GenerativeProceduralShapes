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
void Box01_float(float2 UV, out float Inside01)
{
    // Center the coordinates: move (0.5,0.5) to (0,0)
    float2 p = UV - float2(0.5, 0.5);

    // Define half-size of the box (normalized units)
    float2 halfSize = float2(0.3, 0.3);

    // Compute signed distance
    float sd = sdBox(p, halfSize);

    // Binary mask: inside=1, outside=0
    Inside01 = (sd <= 0.0) ? 1.0 : 0.0;
}