/*
  PLAN:
  1) Define SDF helpers: sdRoundBox (rounded rectangle), sdConvexPoly4 (quadrilateral).
  2) Recenter UVs to (0,0) and apply rotation for the entire icon.
  3) Construct the Battery Shell:
     - Calculate outer rounded box (Body).
     - Calculate inner rounded box (Hollow) by shrinking size by BorderThickness.
     - Subtract Hollow from Body to create the shell frame.
  4) Construct the Battery Tip:
     - Create a small rounded box positioned on top of the body.
     - Union Tip with Shell.
  5) Construct the Lightning Bolt:
     - Define two convex quadrilaterals (Upper and Lower segments) arranged in a zigzag pattern.
     - These vertices are defined to form a classic lightning shape, scaled by BoltScale.
  6) Combine Battery and Lightning:
     - Union the Lightning SDF with the Battery SDF.
  7) Apply smoothstep anti-aliasing based on fwidth for a crisp edge.
  8) Output final Color with alpha transparency.

  User Request: A battery icon with a lightning symbol inside, adjustable size/proportions.
*/

#ifndef PI
#define PI 3.14159265359
#endif

// --- Helper Functions ---

// Signed distance to a 2D segment
float sdSegment(float2 p, float2 a, float2 b)
{
    float2 pa = p - a, ba = b - a;
    float h = saturate(dot(pa, ba) / dot(ba, ba));
    return length(pa - ba * h);
}

// Exact SDF to a convex quadrilateral (CCW order)
float sdConvexPoly4(float2 p, float2 v0, float2 v1, float2 v2, float2 v3)
{
    float2 v[4] = { v0, v1, v2, v3 };
    float d2 = 1e20;
    float s = -1e20;
    [unroll]
    for (int i = 0; i < 4; ++i) {
        float2 a = v[i];
        float2 b = v[(i + 1) & 3];
        float sdE = sdSegment(p, a, b);
        d2 = min(d2, sdE * sdE);
        float2 e = b - a;
        float2 n = normalize(float2(e.y, -e.x)); // outward normal
        s = max(s, dot(p - a, n));
    }
    return (s > 0.0) ? sqrt(d2) : -sqrt(d2);
}

// Signed distance to a rounded box
// b = half-extents, r = corner radius
float sdRoundBox(float2 p, float2 b, float r)
{
    float2 q = abs(p) - b + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

// --- Main Function ---
void BatteryIconWithLightning_float(
    float2 UV,
    float Width,
    float Height,
    float BorderThickness,
    float TipWidth,
    float TipHeight,
    float CornerRadius,
    float BoltScale,
    float Rotation,
    float4 Color,
    out float4 outColor)
{
    // 1. Center and Rotate Coordinates
    float2 p = UV - 0.5;
    float c = cos(Rotation);
    float s = sin(Rotation);
    p = float2(c * p.x + s * p.y, -s * p.x + c * p.y);

    // 2. Battery Shell Construction
    float2 bodySize = float2(Width, Height) * 0.5;
    // Ensure corner radius doesn't exceed dimensions
    float r = min(CornerRadius, min(bodySize.x, bodySize.y));
    float border = max(BorderThickness, 0.001);

    // Outer body SDF
    float dOuter = sdRoundBox(p, bodySize, r);
    
    // Inner body (void) SDF - subtracted to make outline
    // Shrink by border thickness
    float rInner = max(0.0, r - border);
    float2 innerSize = bodySize - border;
    float dInner = sdRoundBox(p, innerSize, rInner);
    
    // Shell = Outer - Inner (Intersection of Outer and negated Inner)
    float dShell = max(dOuter, -dInner);

    // 3. Battery Tip Construction
    // Positioned on top of the main body
    float2 tipSize = float2(TipWidth, TipHeight) * 0.5;
    // Offset y to place it exactly on top of the body half-height
    // Overlap slightly (0.002) to ensure smooth union
    float2 tipOffset = float2(0.0, bodySize.y + tipSize.y - 0.002);
    float dTip = sdRoundBox(p - tipOffset, tipSize, max(0.0, min(tipSize.x, tipSize.y) * 0.2));

    // Combine Shell and Tip
    float dBattery = min(dShell, dTip);

    // 4. Lightning Bolt Construction
    // Defined by two convex quads (Upper and Lower segments)
    // We define base coordinates that look good, then apply BoltScale
    float sc = max(BoltScale, 0.01);
    
    // Upper Segment Vertices (Zigzag top)
    // Top-Right, Top-Left, Bottom-Left, Bottom-Right
    // Coordinates relative to center, unscaled
    float2 u0 = float2( 0.12,  0.30) * sc;
    float2 u1 = float2(-0.06,  0.30) * sc;
    float2 u2 = float2(-0.16, -0.05) * sc;
    float2 u3 = float2( 0.04, -0.05) * sc;
    float dUpper = sdConvexPoly4(p, u0, u1, u2, u3);

    // Lower Segment Vertices (Zigzag bottom)
    // Starts slightly higher than Upper ends for overlap
    float2 l0 = float2( 0.14,  0.05) * sc;
    float2 l1 = float2(-0.04,  0.05) * sc;
    float2 l2 = float2(-0.10, -0.30) * sc;
    float2 l3 = float2( 0.10, -0.30) * sc;
    float dLower = sdConvexPoly4(p, l0, l1, l2, l3);

    // Union of upper and lower bolt segments
    float dBolt = min(dUpper, dLower);

    // 5. Final Combination
    // Union of the battery frame and the lightning bolt
    float dFinal = min(dBattery, dBolt);

    // 6. Anti-aliasing and Color Output
    float aa = fwidth(dFinal);
    float mask = 1.0 - smoothstep(-aa, aa, dFinal);

    outColor = float4(Color.rgb * mask, mask);
}

// ------------------------------------------------------------------------
//  Visual Result (High-level, parameter-invariant description)
// ------------------------------------------------------------------------
//  This function generates a **stylized 2D battery icon with an internal
//  lightning-bolt symbol** using Signed Distance Functions (SDFs).
//
//  The shape consists of a rounded rectangular battery body with a small
//  terminal protrusion on one side, rendered as an outlined shell, and a
//  sharp, angular lightning-bolt form positioned inside the battery
//  interior. The proportions of the battery, border thickness, corner
//  roundness, terminal size, bolt scale, rotation, placement, and color
//  are fully controlled by input parameters and are not fixed by the
//  function itself.
//
//  The output is an anti-aliased RGBA color suitable for energy indicators,
//  charging status icons, power symbols, and analytic procedural 2D
//  graphics.
// ------------------------------------------------------------------------
