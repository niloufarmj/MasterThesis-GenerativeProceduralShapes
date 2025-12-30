#ifndef PI
#define PI 3.14159265359
#endif

// --- Helper Functions ---

// Signed Distance to a Box
float ub_sdBox(float2 p, float2 b) {
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// Signed Distance to a Segment
float ub_sdSegment(float2 p, float2 a, float2 b) {
    float2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}

// Gradient-estimated Signed Distance to an Ellipse
// p: point, r: radii (a, b)
float ub_sdEllipse(float2 p, float2 r) {
    float k0 = length(p/r);
    float k1 = length(p/(r*r));
    return k0 * (k0 - 1.0) / k1;
}

// Main Function: Cartoon Umbrella
// Renders a 2D umbrella with a multi-colored canopy, scallops, and a curved handle
void CartoonUmbrella_float(float2 UV, float CanopyWidth, float CanopyHeight, float HandleLength, float HandleThick, float HookRadius, float PanelCurveDepth, float4 Col1, float4 Col2, float4 Col3, float4 Col4, float4 Col5, float4 HandleCol, float4 OutlineCol, float OutlineWidth, out float4 outColor) {
    // PLAN:
    // 1. Center UV coordinates at (0.5, 0.5) to define the object space.
    // 2. Define Canopy SDF: Intersection of a semi-ellipse (top) and inverted circles (scallops) at the bottom.
    // 3. Define Handle SDF: Union of a vertical shaft segment and a J-shaped arc (semicircle) at the bottom.
    // 4. Compute Panel Colors based on horizontal position within the canopy.
    // 5. Composite the layers (Handle, then Canopy on top) with anti-aliasing and outlines.

    float2 p = UV - 0.5;
    float aa = fwidth(length(p));
    aa = max(aa, 0.0005);

    // --- Parameters Sanitization ---
    float w = max(CanopyWidth, 0.01);
    float h = max(CanopyHeight, 0.01);
    float rDepth = max(PanelCurveDepth, 0.001);
    float hLen = max(HandleLength, 0.0);
    float hThick = max(HandleThick, 0.002);
    float hkRad = max(HookRadius, hThick * 1.5);
    float outW = max(OutlineWidth, 0.0);
    float panelW = w / 5.0;

    // --- Canopy Geometry ---
    // Base Y position where canopy meets handle
    float yBase = 0.1;
    float2 pCanopy = p - float2(0.0, yBase);

    // 1. Top Shape: Semi-Ellipse
    // We use a full ellipse SDF, but the scallop subtraction effectively cuts the bottom.
    // Radii: width/2, height
    float dEllipse = ub_sdEllipse(pCanopy, float2(w * 0.5, h));

    // 2. Bottom Shape: Scallop Cutouts
    // We subtract 5 circles centered along the bottom edge.
    // Scallop radius calculation based on chord (panelW) and sag (rDepth)
    float scallopR = (panelW * panelW * 0.25 + rDepth * rDepth) / (2.0 * rDepth);
    // Center Y is shifted down so the top of the circle touches y=rDepth (relative to base line)
    // Actually, we want the "points" to be at y=0. The arc goes UP to y=rDepth.
    // So the circle passes through (+/- pw/2, 0) and (0, rDepth).
    float scallopCenterY = -(scallopR - rDepth);

    float dScallops = 100.0;
    // 5 Panels -> 5 Scallops. Centers at -2pw, -pw, 0, pw, 2pw
    for(int i = -2; i <= 2; i++) {
        float2 center = float2(float(i) * panelW, scallopCenterY);
        float dCircle = length(pCanopy - center) - scallopR;
        dScallops = min(dScallops, dCircle);
    }

    // Final Canopy SDF: Intersection of Ellipse and NOT Scallops (Holes)
    // Intersection(A, -B) -> max(A, -B)
    // Also ensure we are above the scallop line generally? 
    // The ellipse naturally bounds the top. The scallops bound the bottom.
    float dCanopy = max(dEllipse, -dScallops);

    // --- Handle Geometry ---
    // Shaft: Vertical segment from yBase down to yBase - hLen
    float yShaftBot = yBase - hLen;
    float dShaft = ub_sdSegment(p, float2(0.0, yBase), float2(0.0, yShaftBot)) - hThick * 0.5;

    // Hook: J-shape (Semicircle) at bottom
    // Connects at (0, yShaftBot). Tangent is vertical.
    // Center is (-hkRad, yShaftBot). Arc goes from 0 to -PI (down and left).
    float2 hookCenter = float2(-hkRad, yShaftBot);
    float2 pHook = p - hookCenter;
    
    // Ring distance
    float dRing = abs(length(pHook) - hkRad) - hThick * 0.5;
    // Cap for the left tip of the hook
    float2 leftTip = hookCenter + float2(-hkRad, 0.0);
    float dLeftCap = length(p - leftTip) - hThick * 0.5;
    
    // Cut the ring to keep only the bottom half
    // We use pHook.y > 0 to identify top half. 
    // max(dRing, pHook.y) effectively clips the top half (making it positive/outside).
    float dArc = max(dRing, pHook.y);
    // Union with the left cap (to round it off)
    float dHook = min(dArc, dLeftCap);

    // Combine Shaft and Hook
    float dHandle = min(dShaft, dHook);

    // --- Rendering ---
    
    // 1. Draw Handle
    float handleAlpha = smoothstep(outW + aa, outW - 0.0001, dHandle);
    float handleFillMask = smoothstep(0.0, -aa, dHandle);
    float3 handleRGB = lerp(OutlineCol.rgb, HandleCol.rgb, handleFillMask);
    float4 handleLayer = float4(handleRGB * handleAlpha, handleAlpha);

    // 2. Draw Canopy
    // Determine Panel Index for Coloring
    // pCanopy.x range [-w/2, w/2]. Shift to [0, w]. Divide by panelW.
    float pX = pCanopy.x + w * 0.5;
    float pIdx = floor(pX / panelW);
    pIdx = clamp(pIdx, 0.0, 4.0);

    float4 panelCol = Col1;
    if(pIdx > 0.5) panelCol = Col2;
    if(pIdx > 1.5) panelCol = Col3;
    if(pIdx > 2.5) panelCol = Col4;
    if(pIdx > 3.5) panelCol = Col5;

    // Separator Lines between panels
    // Vertical lines at +/- 0.5pw and +/- 1.5pw relative to center
    float absX = abs(pCanopy.x);
    float distSep = min(abs(absX - panelW * 0.5), abs(absX - panelW * 1.5));
    float sepMask = smoothstep(outW * 0.5 + aa, outW * 0.5 - 0.0001, distSep);

    float canopyAlpha = smoothstep(outW + aa, outW - 0.0001, dCanopy);
    float canopyFillMask = smoothstep(0.0, -aa, dCanopy);
    
    // Composite Panel Color + Separators + Outline
    float3 canopyRGB = lerp(OutlineCol.rgb, panelCol.rgb, canopyFillMask);
    // Apply Separators (only inside fill area)
    canopyRGB = lerp(canopyRGB, OutlineCol.rgb, sepMask * canopyFillMask);

    float4 canopyLayer = float4(canopyRGB * canopyAlpha, canopyAlpha);

    // 3. Final Composite (Canopy Over Handle)
    // Standard Premultiplied Alpha Blending: src + dst * (1 - src.a)
    float3 finalRGB = canopyLayer.rgb + handleLayer.rgb * (1.0 - canopyLayer.a);
    float finalA = canopyLayer.a + handleLayer.a * (1.0 - canopyLayer.a);

    outColor = float4(finalRGB, finalA);
}