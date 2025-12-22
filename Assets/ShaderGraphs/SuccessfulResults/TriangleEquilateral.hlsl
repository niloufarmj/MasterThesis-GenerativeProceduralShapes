#ifndef PI
#define PI 3.14159265359
#endif

// Signed Distance Function for an Equilateral Triangle
// p: centered coordinates
// r: circumradius (distance from center to vertex)
float sdEquilateralTriangle(float2 p, float r) {
    const float k = 1.73205080757;
    p.x = abs(p.x) - r;
    p.y = p.y + r / k;
    if (p.x + k * p.y > 0.0)
        p = float2(p.x - k * p.y, -k * p.x - p.y) * 0.5;
    p.x -= clamp(p.x, -2.0 * r, 0.0);
    return -length(p) * sign(p.y);
}

void TriangleEquilateral_float(float2 UV, float Size, float Rotation, float4 Color, out float4 outColor) {
    // PLAN:
    // 1) Center UV coordinates (0.5, 0.5 becomes 0,0).
    // 2) Apply rotation to the coordinate system.
    // 3) Calculate Signed Distance Field (SDF) for equilateral triangle.
    // 4) Apply anti-aliasing using smoothstep and fwidth.
    // 5) Output final RGBA color.

    // 1) Center UV
    float2 p = UV - 0.5;

    // 2) Rotate coordinates
    // We rotate the sampling point by -Rotation to rotate the shape by +Rotation
    float c = cos(Rotation);
    float s = sin(Rotation);
    p = float2(c * p.x + s * p.y, -s * p.x + c * p.y);

    // 3) Calculate SDF
    // Size acts as the circumradius
    float dist = sdEquilateralTriangle(p, Size);

    // 4) Anti-aliasing
    // fwidth computes the derivative of the distance field for sharp, clean edges
    float aa = fwidth(dist);
    aa = max(aa, 0.001); // Safety clamp to prevent division by zero or artifacts
    
    // Calculate alpha mask: 1.0 inside, 0.0 outside
    // dist is negative inside the shape
    float mask = 1.0 - smoothstep(-aa, aa, dist);

    // 5) Output final color
    // Apply mask to both RGB (premultiplied) and Alpha
    outColor = float4(Color.rgb * mask, Color.a * mask);
}

// ------------------------------------------------------------------------
//  Visual Result (High-level, parameter-invariant description)
// ------------------------------------------------------------------------
//  This function generates a **2D equilateral triangle primitive**
//  using a Signed Distance Function (SDF).
//
//  The shape is a three-sided polygon with all sides and internal angles
//  equal, forming a symmetric equilateral triangle silhouette. The size,
//  rotation, placement, fill, and outline appearance are fully controlled
//  by input parameters and are not fixed by the function itself.
//
//  The output is an anti-aliased RGBA color suitable for geometric icons,
//  directional indicators, UI elements, and analytic procedural 2D graphics.
// ------------------------------------------------------------------------
