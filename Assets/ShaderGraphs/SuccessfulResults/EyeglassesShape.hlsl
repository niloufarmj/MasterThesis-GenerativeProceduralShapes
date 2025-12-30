#ifndef PI
#define PI 3.14159265359
#endif

// --- Helper Functions ---

// Signed distance to a box
float sdBox(float2 p, float2 b) {
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// Signed distance to a rounded box
// b: half-extents, r: corner radius
float sdRoundBox(float2 p, float2 b, float r) {
    return sdBox(p, b - r) - r;
}

// Alpha blending helper (Src Over Dst)
float4 blend(float4 src, float4 dst) {
    float finalA = src.a + dst.a * (1.0 - src.a);
    float3 finalRGB = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(finalA, 1e-6);
    return float4(finalRGB, finalA);
}

// --- Main Shape Function ---
void EyeglassesShape_float(float2 UV, float LensWidth, float LensHeight, float LensRoundness, float BridgeWidth, float BridgeHeight, float FrameThickness, float OutlineThickness, float4 FrameColor, float4 LensColor, float4 OutlineColor, out float4 outColor) {
    // PLAN:
    // 1. Center UVs at (0.5, 0.5) and apply x-axis symmetry to model both sides.
    // 2. Calculate dimensions for lens, frame, and bridge based on inputs.
    // 3. Compute SDF for the Lens (inner hole).
    // 4. Compute SDF for the Frame Body (union of lens rim and bridge).
    // 5. Compute AA masks for Lens Fill, Frame Fill, and Outlines.
    // 6. Composite layers in order: Lens -> Frame -> Outlines.

    // 1. Center and Symmetry
    float2 p = UV - 0.5;
    p.x = abs(p.x); // Mirror right side to left

    // 2. Safe Parameters
    float2 lensHalfSize = max(float2(LensWidth, LensHeight), 0.001) * 0.5;
    float bridgeHalfW = max(BridgeWidth, 0.0) * 0.5;
    float bridgeHalfH = max(BridgeHeight, 0.0) * 0.5;
    float fThick = max(FrameThickness, 0.0);
    float oThick = max(OutlineThickness, 0.0);
    
    // Determine Lens Position
    // The bridge defines the gap, so the lens starts at x = bridgeHalfW
    float2 lensCenter = float2(bridgeHalfW + lensHalfSize.x, 0.0);

    // 3. Lens SDF (Inner Hole)
    // Clamp roundness so it doesn't exceed the size
    float validLensR = clamp(LensRoundness, 0.0, min(lensHalfSize.x, lensHalfSize.y));
    float dLens = sdRoundBox(p - lensCenter, lensHalfSize, validLensR);

    // 4. Frame SDF
    // The frame wraps around the lens. We expand the lens box by FrameThickness.
    float2 frameHalfSize = lensHalfSize + fThick;
    float frameR = validLensR + fThick;
    float dLensFrame = sdRoundBox(p - lensCenter, frameHalfSize, frameR);

    // Bridge SDF
    // A simple box connecting the two sides. 
    // Width covers from center (0) to overlap the frame slightly.
    // Height is parameterized.
    float dBridge = sdBox(p, float2(bridgeHalfW + fThick, bridgeHalfH));

    // Combine Frame and Bridge (Union)
    float dFrameBody = min(dLensFrame, dBridge);

    // 5. Anti-Aliasing and Masks
    // Use fwidth for analytic AA, with a small epsilon fallback
    float aa = length(fwidth(p));
    aa = max(aa, 0.001);

    // Lens Mask: Solid inside dLens
    float lensMask = 1.0 - smoothstep(-aa, 0.0, dLens);

    // Frame Mask: Solid inside dFrameBody, but excluding the Lens hole
    // We perform a boolean subtraction (Intersection of Frame and Not Lens)
    float dFrameFinal = max(dFrameBody, -dLens);
    float frameMask = 1.0 - smoothstep(-aa, 0.0, dFrameFinal);

    // Outline Masks (Centered stroke)
    // Outline 1: Around the outer frame body
    float dOutlineOuter = abs(dFrameBody) - oThick * 0.5;
    float outlineOuterMask = 1.0 - smoothstep(-aa, 0.0, dOutlineOuter);

    // Outline 2: Around the inner lens hole
    float dOutlineInner = abs(dLens) - oThick * 0.5;
    float outlineInnerMask = 1.0 - smoothstep(-aa, 0.0, dOutlineInner);

    // Combine outlines
    float totalOutlineMask = max(outlineOuterMask, outlineInnerMask);

    // 6. Composition (Painter's Algorithm)
    // Start with transparent background
    float4 col = float4(0.0, 0.0, 0.0, 0.0);

    // Layer 1: Lenses
    float4 layerLens = float4(LensColor.rgb, LensColor.a * lensMask);
    col = blend(layerLens, col);

    // Layer 2: Frame
    float4 layerFrame = float4(FrameColor.rgb, FrameColor.a * frameMask);
    col = blend(layerFrame, col);

    // Layer 3: Outlines (Top)
    float4 layerOutline = float4(OutlineColor.rgb, OutlineColor.a * totalOutlineMask);
    col = blend(layerOutline, col);

    outColor = col;
}