#ifndef PI
#define PI 3.14159265359
#endif

// --- Helper Functions ---

// Signed distance to a circle
// p: position relative to center
// r: radius
float sdCircle(float2 p, float r) {
    return length(p) - r;
}

// Signed distance to a box with rounded corners
// p: position relative to center
// b: half-extents (width/2, height/2)
// r: corner radius
float sdRoundedBox(float2 p, float2 b, float r) {
    float2 q = abs(p) - b + r;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

// Smooth union of two SDFs (k controls the smoothness of the blend)
float opSmoothUnion(float d1, float d2, float k) {
    float h = clamp(0.5 + 0.5 * (d2 - d1) / max(k, 0.001), 0.0, 1.0);
    return lerp(d2, d1, h) - k * h * (1.0 - h);
}

// Alpha compositing: Source Over Destination
// src: Top layer (Color + Alpha)
// dst: Bottom layer (Color + Alpha)
// Returns composite color
float4 compositeOver(float4 src, float4 dst) {
    float outA = src.a + dst.a * (1.0 - src.a);
    float3 outRGB = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(outA, 0.0001);
    return float4(outRGB, outA);
}

// --- Main Function ---
// PLAN:
// 1) Center and scale UV coordinates based on Center and Size parameters.
// 2) Define trunk SDF (rounded box) anchored near the bottom.
// 3) Define foliage SDF as a smooth union of 3 circles (top, left, right).
// 4) Compute anti-aliased masks for both shapes.
// 5) Composite Foliage OVER Trunk to ensure leaves cover the branch connection.

void PuffyTreeShape_float(
    float2 UV,
    float Size,
    float TrunkWidth,
    float TrunkHeight,
    float2 Center,
    float4 FoliageColor,
    float4 TrunkColor,
    out float4 outColor)
{
    // 1. Setup Space
    // Map UV (0..1) to centered coords (-1..1) then scale by Size
    // Size=1 means the shape fits comfortably in the view.
    float2 p = (UV - Center) * 2.0;
    p /= max(Size, 0.001);

    // 2. Trunk SDF
    // Position trunk so it sits below the foliage center.
    // We calculate a vertical offset so the trunk connects nicely to the leaves.
    float trunkHalfW = TrunkWidth * 0.5;
    float trunkHalfH = TrunkHeight * 0.5;
    // Trunk center Y: positioned so top is around y=-0.1 overlapping leaves
    float trunkCenterY = -0.2 - trunkHalfH + 0.1;
    float2 trunkPos = p - float2(0.0, trunkCenterY);
    float dTrunk = sdRoundedBox(trunkPos, float2(trunkHalfW, trunkHalfH), 0.02);

    // 3. Foliage SDF
    // Compose 3 circles for a puffy tree look
    // Top Circle
    float dTop = sdCircle(p - float2(0.0, 0.3), 0.45);
    // Left Circle
    float dLeft = sdCircle(p - float2(-0.35, -0.05), 0.35);
    // Right Circle
    float dRight = sdCircle(p - float2(0.35, -0.05), 0.35);

    // Smoothly blend them
    float blendK = 0.15;
    float dFoliage = opSmoothUnion(dTop, dLeft, blendK);
    dFoliage = opSmoothUnion(dFoliage, dRight, blendK);

    // 4. Masks & AA
    // Use fwidth of the SDF for consistent crisp edges
    float aaTrunk = fwidth(dTrunk);
    float aaFoliage = fwidth(dFoliage);

    // Compute alpha masks (0 = transparent, 1 = opaque)
    float maskTrunk = 1.0 - smoothstep(-aaTrunk, aaTrunk, dTrunk);
    float maskFoliage = 1.0 - smoothstep(-aaFoliage, aaFoliage, dFoliage);

    // 5. Coloring & Composite
    // Prepare RGBA layers (Straight alpha for mixing)
    float4 layerTrunk = float4(TrunkColor.rgb, TrunkColor.a * maskTrunk);
    float4 layerFoliage = float4(FoliageColor.rgb, FoliageColor.a * maskFoliage);

    // Composite: Foliage sits ON TOP of Trunk
    outColor = compositeOver(layerFoliage, layerTrunk);
}

// ------------------------------------------------------------------------
//  Visual Result (High-level, parameter-invariant description)
// ------------------------------------------------------------------------
//  This function generates a **stylized 2D tree-like primitive with soft,
//  rounded foliage** using Signed Distance Functions (SDFs).
//
//  The shape is composed of a rounded canopy formed from multiple smoothly
//  blended circular elements, combined with a simple vertical trunk.
//  The relative proportions, scale, placement, and coloring of the foliage
//  and trunk are fully controlled by input parameters and are not fixed by
//  the function itself.
//
//  The output is an anti-aliased RGBA color suitable for icons,
//  decorative UI elements, environmental symbols, and expressive
//  procedural 2D graphics.
// ------------------------------------------------------------------------
