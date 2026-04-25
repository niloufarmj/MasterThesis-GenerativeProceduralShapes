/*
  SDF Star5PointSimple
  Generates a simple, solid 5-pointed star.

  This function uses a standard mathematical formula to calculate the distance
  from any point to the nearest edge of a 5-pointed star shape. This allows
  for a procedurally drawn star with adjustable outer and inner radii, rotation,
  and position. The edges are anti-aliased using fwidth for a smooth appearance.

  The core logic is adapted from standard SDF primitives, optimized for this
  specific polygonal shape by using vector projections and reflections to fold
  the 2D space, simplifying the distance calculation to a single segment.
*/

#ifndef PI
#define PI 3.14159265359
#endif

// Helper: Signed Distance Function for a 5-point Star
// A common and efficient implementation for a star SDF.
// p: centered & rotated sampling point
// r: outer radius
// rf: inner radius as a ratio of the outer radius (internal parameter)
#ifndef SD_STAR5_HELPER
#define SD_STAR5_HELPER
inline float sdStar5(float2 p, float r, float rf)
{
    // These constants are pre-calculated sines and cosines for a pentagon/star
    const float2 k1 = float2(0.809016994375, -0.587785252292);
    const float2 k2 = float2(-k1.x, k1.y);
    p.x = abs(p.x);
    // Fold the space to reduce the problem to a single edge calculation
    p -= 2.0 * max(dot(k1, p), 0.0) * k1;
    p -= 2.0 * max(dot(k2, p), 0.0) * k2;
    p.x = abs(p.x);
    p.y -= r;
    float2 ba = rf * float2(-k1.y, k1.x) - float2(0, 1);
    float h = clamp( dot(p,ba)/dot(ba,ba), 0.0, r );
    return length(p-ba*h) * sign(p.y*ba.x-p.x*ba.y);
}
#endif

void Star5PointSimple_float(
    float2 UV,
    float Radius,
    float InnerRadius,
    float2 Center,
    float Rotation,
    float4 Color,
    out float4 outColor
)
{
    // 1. Coordinate Preparation
    // Recenter UV coordinates to the specified Center point.
    float2 p = UV - Center;

    // Apply rotation. We rotate the coordinate system in the opposite direction
    // of the desired shape rotation.
    float sinR = sin(Rotation);
    float cosR = cos(Rotation);
    p = float2(p.x * cosR + p.y * sinR, p.y * cosR - p.x * sinR);

    // 2. Calculate Signed Distance
    // Use the helper function to get the distance to the star's edge.
    // Clamp radii to prevent visual artifacts or inversion.
    float r_outer = max(Radius, 0.001);
    float r_inner = clamp(InnerRadius, 0.0, r_outer);
    float d = sdStar5(p, r_outer, r_inner);

    // 3. Anti-aliasing and Masking
    // Use the screen-space derivative of the distance to create a smooth edge.
    float aa = fwidth(d);
    // The mask is 1 inside the shape (d < 0) and 0 outside (d > 0),
    // with a smooth transition between them.
    float mask = 1.0 - smoothstep(0.0, aa, d);

    // 4. Final Output
    // Combine the color with the calculated mask for transparency.
    outColor = float4(Color.rgb, Color.a * mask);
}