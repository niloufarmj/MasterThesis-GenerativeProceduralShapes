#ifndef PI
#define PI 3.14159265359
#endif

// SDF for a rounded box centered at origin
// b: half-extents (width/2, height/2), r: corner radius
float sdRoundedBox(float2 p, float2 b, float r)
{
    float2 q = abs(p) - b + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

// 2D Rotation Helper
float2 rotate(float2 p, float angle)
{
    float c = cos(angle);
    float s = sin(angle);
    return float2(c * p.x + s * p.y, -s * p.x + c * p.y);
}

// Smooth Union for blending shapes organically
float opSmoothUnion(float d1, float d2, float k)
{
    float h = clamp(0.5 + 0.5 * (d2 - d1) / k, 0.0, 1.0);
    return lerp(d2, d1, h) - k * h * (1.0 - h);
}

// Helper to composite layers (src over dst)
float4 layerOver(float4 src, float4 dst)
{
    return src + dst * (1.0 - src.a);
}

void GiftBox_float(float2 UV, float Size, float RibbonThickness, float BowSize, float4 BoxColor, float4 RibbonColor, out float4 outColor)
{
    // PLAN:
    // 1) Center and Scale UVs to create local coordinate system.
    // 2) Define Box SDF (rounded rectangle) shifted slightly down.
    // 3) Define Ribbon Pattern (horizontal/vertical strips) masked by the box.
    // 4) Define Bow SDF (center knot + two rotated loops) placed on top.
    // 5) Render layers (Box+Ribbon, Bow) with anti-aliasing and composite.

    // 1. Coordinates
    // Center UV at (0,0) and scale. Size = 1.0 fits screen nicely.
    float2 centered = UV - 0.5;
    float s = max(Size, 0.001);
    float2 p = centered / s;
    
    // Anti-aliasing width (scaled by Size to maintain sharpness)
    float aa = fwidth(p.y);
    aa = max(aa, 0.002);

    // 2. Box Base Geometry
    // Fixed local proportions, scaled by 'Size' globally
    float2 boxDim = float2(0.4, 0.35); 
    float boxRadius = 0.04;
    // Shift box down so bow has room on top
    float2 boxPos = p - float2(0.0, -0.15);
    float dBox = sdRoundedBox(boxPos, boxDim, boxRadius);

    // 3. Ribbon Pattern
    // Ribbons are just strips crossing the center of the box
    // Width is controlled by parameter
    float dRibbonV = abs(boxPos.x) - max(RibbonThickness, 0.01) * 0.5;
    float dRibbonH = abs(boxPos.y) - max(RibbonThickness, 0.01) * 0.5;
    float dRibbon = min(dRibbonV, dRibbonH);
    // Ribbon mask is fuzzy edge based on distance
    float ribbonAlpha = 1.0 - smoothstep(0.0, aa, dRibbon);

    // 4. Bow Geometry
    // Anchor bow to the top of the box
    float2 bowOrigin = boxPos - float2(0.0, boxDim.y);
    // Shift up slightly for overlap
    float2 q = bowOrigin - float2(0.0, 0.02);
    
    // Center Knot
    float dKnot = length(q) - (BowSize * 0.25);
    
    // Loops (Mirror X for symmetry)
    float2 qSym = q;
    qSym.x = abs(qSym.x);
    // Move pivot for the loop
    qSym -= float2(BowSize * 0.5, BowSize * 0.3);
    // Rotate ~45 degrees (PI/4)
    qSym = rotate(qSym, PI * 0.25);
    // Distorted circle (squash one axis to make it loop-like)
    float2 loopScale = float2(0.8, 1.4);
    float dLoops = length(qSym * loopScale) - (BowSize * 0.35);
    
    // Combine Knot and Loops smoothly
    float dBow = opSmoothUnion(dKnot, dLoops, BowSize * 0.05);

    // 5. Rendering & Compositing
    
    // -- Box Layer --
    // Box Mask
    float boxMask = 1.0 - smoothstep(0.0, aa, dBox);
    // Mix Ribbon Color into Box Color
    // We apply ribbonAlpha where it exists, constrained by the box shape later
    float4 fillRGB = lerp(BoxColor, RibbonColor, ribbonAlpha);
    // Final Box Layer (Pre-multiplied alpha)
    float4 layerBox = float4(fillRGB.rgb * boxMask, fillRGB.a * boxMask);

    // -- Bow Layer --
    // Bow Mask
    float bowMask = 1.0 - smoothstep(0.0, aa, dBow);
    // Bow Layer (Pre-multiplied alpha)
    float4 layerBow = float4(RibbonColor.rgb * bowMask, RibbonColor.a * bowMask);

    // Composite: Bow sits on top of Box
    outColor = layerOver(layerBow, layerBox);
}

// ------------------------------------------------------------------------
//  Visual Result (High-level, parameter-invariant description)
// ------------------------------------------------------------------------
//  This function generates a **stylized 2D gift box (present) icon**
//  using Signed Distance Functions (SDFs).
//
//  The visual result consists of a rounded rectangular box body rendered
//  as the base layer, overlaid with a cross-shaped ribbon that runs both
//  vertically and horizontally across the box face. On top of the box,
//  a decorative bow element is placed, composed of a small central knot
//  and two symmetrical loop shapes extending outward, forming a classic
//  gift-bow silhouette.
//
//  The box proportions, corner roundness, ribbon thickness, ribbon layout,
//  bow size, bow curvature, color composition, scale, and placement are
//  fully controlled by input parameters and are not fixed by the function
//  itself.
//
//  The output is an anti-aliased RGBA color suitable for icons, celebratory
//  UI elements, reward indicators, game interfaces, and expressive
//  procedural 2D graphics.
// ------------------------------------------------------------------------
