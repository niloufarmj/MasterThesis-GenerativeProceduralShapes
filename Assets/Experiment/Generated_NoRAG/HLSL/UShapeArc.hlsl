#ifndef PI
#define PI 3.14159265359
#endif

// User request: a U-shaped thick arc with two parallel straight arms and a rounded bottom, open at the top, filled by default with dark shade of colors (not white or too bright)

// SDF for a circle
inline float sdCircle(float2 p, float r)
{
    return length(p) - r;
}

// SDF for an axis-aligned box centered at origin
inline float sdBox(float2 p, float2 b)
{
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// SDF union: min of two distances
inline float opUnion(float dA, float dB)
{
    return min(dA, dB);
}

// SDF subtraction: subtract shape B from shape A (A minus B)
inline float opSubtract(float dA, float dB)
{
    return max(dA, -dB);
}

void UShapeArc_float(
    float2 UV,
    float Size,
    float Thickness,
    float ArmHeight,
    float4 Color,
    out float4 outColor)
{
    // PLAN:
    // 1) Center UV to p in UV space around (0.5, 0.5).
    // 2) Build the U shape using SDF operations:
    //    a) Outer shape = union of:
    //       - A semicircle (bottom half of outer circle)
    //       - Two outer rectangles for the arms (left and right)
    //    b) Inner cutout = union of:
    //       - A semicircle (bottom half of inner circle)
    //       - Two inner rectangles (hole between arms)
    //    c) U shape = outer shape minus inner cutout
    //    d) Subtract the top half (y > 0 region) to keep only bottom+arms
    // 3) Anti-alias and output color.

    // 1) Center the UV coords
    float2 p = UV - float2(0.5, 0.5);

    // Shape parameters derived from Size and Thickness
    float outerRadius = Size;                      // outer radius of the rounded bottom
    float innerRadius = max(outerRadius - Thickness, 0.001); // inner radius
    float halfArmWidth = Thickness * 0.5;          // half-width of each arm
    float armCenterX = (outerRadius + innerRadius) * 0.5; // center x of each arm
    float armHalfHeight = ArmHeight * 0.5;         // half height of the arm rectangles
    float armBottomY = 0.0;                        // arms start at y=0 (center)
    float armTopY = ArmHeight;                     // arms extend upward
    float armCenterY = armBottomY + armHalfHeight; // center y of arm box

    // --- Build outer U boundary ---
    // Outer filled circle (only bottom half: y <= 0)
    // We use a large box to cut the top off
    float dOuterCircle = sdCircle(p, outerRadius);
    // Box to keep only y <= 0 region: box centered at (0, -bigVal) with big height
    // Actually: cut by y > 0 plane -> keep only region where p.y <= 0
    // Use a half-plane: distance to half-plane y>0 is (p.y - 0)
    // To keep y<=0: we use a large rect cutting from above
    float cutTopOuter = p.y; // positive above y=0, negative below -> cut top means max(dCircle, -cutTop) would keep bottom
    // dBottomCircleFilled: inside the full outer circle AND below y=0
    // = intersection of circle and lower half-plane
    float dOuterSemi = max(dOuterCircle, cutTopOuter); // negative only in bottom half of circle

    // Outer arm rectangles: left arm centered at (-armCenterX, armCenterY)
    // right arm centered at (+armCenterX, armCenterY)
    float2 armHalfSize = float2(halfArmWidth, armHalfHeight);
    float2 pLeftArm  = p - float2(-armCenterX,  armCenterY);
    float2 pRightArm = p - float2( armCenterX,  armCenterY);
    float dLeftArmOuter  = sdBox(pLeftArm,  armHalfSize);
    float dRightArmOuter = sdBox(pRightArm, armHalfSize);

    // Union all outer parts
    float dOuter = opUnion(dOuterSemi, opUnion(dLeftArmOuter, dRightArmOuter));

    // --- Build inner cutout ---
    float dInnerCircle = sdCircle(p, innerRadius);
    float dInnerSemi = max(dInnerCircle, cutTopOuter); // bottom half of inner circle

    // Inner gap between arms: box that fills the space between the two arms, above y=0
    float innerGapHalfWidth = innerRadius;
    float2 pGap = p - float2(0.0, armCenterY);
    float dInnerGap = sdBox(pGap, float2(innerGapHalfWidth, armHalfHeight));

    // Union of inner cutout regions
    float dInner = opUnion(dInnerSemi, dInnerGap);

    // --- Final U shape = outer minus inner ---
    float dU = opSubtract(dOuter, dInner);

    // --- Anti-aliased mask ---
    float aa = fwidth(dU);
    float mask = 1.0 - smoothstep(0.0, aa, dU);

    // --- Output ---
    outColor = float4(Color.rgb * mask, mask);
}
