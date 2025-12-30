#ifndef PI
#define PI 3.14159265359
#endif

// --- Helper Functions (SDF Primitives) ---

// Signed Distance to a Box
float sdBox(float2 p, float2 b) {
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// Signed Distance to a Line Segment
float sdSegment(float2 p, float2 a, float2 b) {
    float2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}

// Signed Distance to an Ellipse (approx)
float sdEllipse(float2 p, float2 r) {
    float k0 = length(p/r);
    float k1 = length(p/(r*r));
    return k0 * (k0 - 1.0) / k1;
}

// Main Function: Cartoon Umbrella
// Renders an open umbrella with a semi-circular canopy, scalloped bottom edge, and Persian L-shaped hook.
void CartoonUmbrellaSDF_float(float2 UV, float CanopyWidth, float CanopyHeight, float HandleLength, float HandleThick, float HookRadius, float PanelCurveDepth, float4 Col1, float4 Col2, float4 Col3, float4 Col4, float4 Col5, float4 HandleCol, float4 OutlineCol, float OutlineWidth, out float4 outColor) {
    // PLAN:
    // 1. Center UVs. Define yBase for the junction of handle and canopy.
    // 2. Canopy SDF:
    //    - Start with a Semi-Ellipse (cut off at y=0 relative to base).
    //    - Subtract 5 "scallop" circles from the bottom edge to create the inward curves.
    // 3. Handle SDF:
    //    - Vertical shaft segment descending from canopy.
    //    - 90-degree arc (quarter circle) for the L-bend.
    //    - Short horizontal segment for the Persian hook tip.
    // 4. Panel Coloring: Determine horizontal index (0-4) and assign colors.
    // 5. Rendering: Combine SDFs, apply outlines, ribs, and anti-aliasing.

    float2 p = UV - 0.5;
    float aa = fwidth(length(p));
    aa = max(aa, 0.0005);

    // -- Parameters --
    float w = max(CanopyWidth, 0.05);
    float h = max(CanopyHeight, 0.05);
    float hLen = max(HandleLength, 0.0);
    float hThick = max(HandleThick, 0.002);
    float hkRad = max(HookRadius, hThick * 2.0);
    float depth = max(PanelCurveDepth, 0.001);
    float outW = max(OutlineWidth, 0.0);
    float panelW = w / 5.0;
    
    // Y-coordinate where canopy meets handle
    float yBase = 0.1;

    // ----------------------
    // 1. Canopy Construction
    // ----------------------
    float2 pCan = p - float2(0.0, yBase);
    
    // A. Main Dome: Semi-Ellipse
    // Intersection of Ellipse and upper half-plane (y > 0)
    float dEllipse = sdEllipse(pCan, float2(w * 0.5, h));
    float dDome = max(dEllipse, -pCan.y); // Cut off the bottom half

    // B. Scallops (Subtraction)
    // Calculate radius of cutting circles based on panel width and curve depth
    // The circle passes through (pw/2, 0) and (0, depth) relative to its local frame bottom
    // Math: R^2 = (pw/2)^2 + (R-depth)^2  =>  R = ( (pw/2)^2 + depth^2 ) / (2*depth)
    float pwHalf = panelW * 0.5;
    float scR = (pwHalf * pwHalf + depth * depth) / (2.0 * depth);
    float scOffsetY = scR - depth;

    // Compute distance to the union of 5 scallop circles
    float dScallops = 100.0;
    for(int i = -2; i <= 2; i++) {
        // Centers are at x = i * panelW
        // The cutting circle center is ABOVE the baseline by (scR - depth) so the bottom of the circle is at 'depth'??
        // Wait, we want to remove the "air" coming from below. The air shape is a circle.
        // Its top vertex is at y = depth. Its side vertices are at y = 0.
        // So the circle center must be at y = depth - scR.
        // Let's verify: Top of circle = (depth - scR) + scR = depth. Correct.
        // Side of circle at dx=pw/2: (depth - scR)^2 + (pw/2)^2 = scR^2. Correct.
        float2 center = float2(float(i) * panelW, -(scR - depth));
        float dCirc = length(pCan - center) - scR;
        dScallops = min(dScallops, dCirc);
    }

    // Final Canopy SDF: Dome minus Scallops
    // max(A, -B) removes B from A
    float dCanopy = max(dDome, -dScallops);

    // ----------------------
    // 2. Handle Construction
    // ----------------------
    // Handle logic: Vertical Shaft -> 90 deg Turn Left -> Small Horizontal Tip
    float yShaftTop = yBase;
    float yShaftBot = yBase - hLen;
    
    // Shaft
    float dShaft = sdSegment(p, float2(0.0, yShaftTop), float2(0.0, yShaftBot)) - hThick * 0.5;

    // L-Hook
    // The arc connects (0, yShaftBot) to (-hkRad, yShaftBot - hkRad)
    // Center of the arc is (-hkRad, yShaftBot)
    float2 hookCenter = float2(-hkRad, yShaftBot);
    float2 pHook = p - hookCenter;
    // Distance to circle ring
    float dRing = abs(length(pHook) - hkRad) - hThick * 0.5;
    // Mask for the Quarter Circle (Bottom-Right quadrant relative to center)
    // Relative coords: Start point (0, yBot) -> local (hkRad, 0)
    // End point (-hkRad, yBot - hkRad) -> local (0, -hkRad)
    // This is the quadrant where x > 0 and y < 0.
    bool inQuadrant = (pHook.x >= 0.0 && pHook.y <= 0.0);
    // To be robust with SDFs, we use a specialized arc or simply trim the ring.
    // Trim: max(dRing, max(-pHook.x, pHook.y)); 
    // We want x > 0 (so -x < 0) and y < 0 (so y < 0). 
    // If we take max(dRing, -pHook.x), we cut left half. 
    // If we take max(..., pHook.y), we cut top half.
    float dArc = max(dRing, max(-pHook.x, pHook.y));

    // Horizontal Tip (Persian style)
    // Extends left from the bottom of the arc (-hkRad, yShaftBot - hkRad)
    float tipLen = hkRad * 0.5; // Short distinctive tip
    float2 tipStart = float2(-hkRad, yShaftBot - hkRad);
    float2 tipEnd = tipStart + float2(-tipLen, 0.0);
    float dTip = sdSegment(p, tipStart, tipEnd) - hThick * 0.5;

    // Combine Handle parts
    float dHandle = min(dShaft, min(dArc, dTip));

    // ----------------------
    // 3. Coloring & Output
    // ----------------------

    // Calculate Panel Index for coloring
    // x range is [-w/2, w/2]. Shift to [0, w].
    float pX = pCan.x + w * 0.5;
    // Add small epsilon to avoid flickering on exact edges
    float pIdx = floor((pX + 0.0001) / panelW);
    pIdx = clamp(pIdx, 0.0, 4.0);

    float4 fillCol = Col1;
    if(pIdx > 0.5) fillCol = Col2;
    if(pIdx > 1.5) fillCol = Col3;
    if(pIdx > 2.5) fillCol = Col4;
    if(pIdx > 3.5) fillCol = Col5;

    // Ribs (lines between panels)
    // Distance to nearest vertical grid line
    // Grid lines at x = -1.5pw, -0.5pw, 0.5pw, 1.5pw
    // We can compute distance of pCan.x to these specific values
    float distRib = 1.0;
    for(int j=-2; j<=2; j++) {
         if (j == 0) continue; // No rib in the center? Usually ribs are at panel boundaries. 
         // Panels: [-2.5, -1.5], [-1.5, -0.5], [-0.5, 0.5], [0.5, 1.5], [1.5, 2.5]
         // Boundaries are at -1.5, -0.5, 0.5, 1.5. (Index j=-2 boundary is left edge? No)
         // Let's explicitly check boundaries.
         float ribX = (float(j) + 0.5) * panelW; // -1.5, -0.5, 0.5, 1.5
         distRib = min(distRib, abs(pCan.x - ribX));
    }
    float ribMask = smoothstep(outW * 0.5 + aa, outW * 0.5 - 0.0001, distRib);

    // --- Composite ---
    
    // Handle Layer
    float handleAlpha = smoothstep(aa, -aa, dHandle);
    float handleOutline = smoothstep(outW + aa, outW - aa, dHandle);
    float3 handleFinal = lerp(OutlineCol.rgb, HandleCol.rgb, handleAlpha); 
    // Note: handleOutline includes the fill. dHandle is 0 at surface, negative inside. 
    // To outline: Draw OutlineCol where d < outW, Draw HandleCol where d < 0.
    // Proper blending: Background -> Outline -> Fill.
    // Or simply: mix(Outline, Fill, fillMask) inside the outline shape.
    
    // Canopy Layer
    float canopyAlpha = smoothstep(0.0, -aa, dCanopy); // Fill mask
    float canopyOutlineMask = smoothstep(outW + aa, outW - aa, dCanopy); // Total shape mask
    
    float3 canopyFill = fillCol.rgb;
    // Apply Ribs to Fill
    canopyFill = lerp(canopyFill, OutlineCol.rgb, ribMask);
    
    float3 canopyFinal = lerp(OutlineCol.rgb, canopyFill, canopyAlpha);
    
    // Combine Handle and Canopy
    // Handle is BEHIND canopy.
    // 1. Start with transparency
    float4 col = float4(0,0,0,0);
    
    // 2. Add Handle
    // Only visible where handleOutline is 1
    col = float4(handleFinal * handleOutline, handleOutline);
    
    // 3. Blend Canopy Over
    // Standard Over operator: Out = Src + Dst * (1 - SrcA)
    float4 src = float4(canopyFinal * canopyOutlineMask, canopyOutlineMask);
    
    col.rgb = src.rgb + col.rgb * (1.0 - src.a);
    col.a = src.a + col.a * (1.0 - src.a);

    outColor = col;
}