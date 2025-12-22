#ifndef PI
#define PI 3.14159265359
#endif

// Helper: Smooth minimum for organic blending of shapes
float help_smin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / max(k, 1e-5), 0.0, 1.0);
    return lerp(b, a, h) - k * h * (1.0 - h);
}

// Helper: Signed distance to a line segment
float help_sdSegment(float2 p, float2 a, float2 b) {
    float2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}

// Helper: Distance to an upper semicircle (arc) centered at origin
// Spans from angle PI (left) to 0 (right)
float help_udArcUpper(float2 p, float r) {
    // Symmetry across Y axis to simplify calculation
    p.x = abs(p.x);
    // If in upper quadrant, distance to circle edge
    if (p.y > 0.0) return abs(length(p) - r);
    // Else distance to the endpoint (r, 0)
    return length(p - float2(r, 0.0));
}

void HelpSymbol_float(float2 UV, float CircleRadius, float CircleThickness, float SymbolScale, float SymbolThickness, float4 CircleColor, float4 SymbolColor, out float4 outColor) {
    // PLAN:
    // 1) Center UV coordinates to (0,0).
    // 2) Compute Outer Circle SDF (Ring).
    // 3) Construct 'Question Mark' SDF:
    //    - Upper Hook: Semicircle arc.
    //    - Stem: Segment connecting hook end to center-bottom.
    //    - Dot: Circle at the bottom.
    // 4) Combine shape parts using smooth minimum for rounded organic look.
    // 5) Render with smoothstep AA and alpha blending.

    // 1) Center UVs
    float2 p = UV - 0.5;
    float aa = 0.01; // Anti-aliasing width

    // 2) Outer Circle (Ring)
    // abs(dist) - thickness/2 creates a ring
    float dCircle = abs(length(p) - CircleRadius) - (CircleThickness * 0.5);
    float circleAlpha = smoothstep(aa, -aa, dCircle);
    
    // 3) Symbol Construction
    // Shift symbol slightly down to visual center
    float2 pSym = p - float2(0.0, 0.05 * SymbolScale);
    
    // Dimensions
    float rHook = 0.25 * SymbolScale;
    float2 centerHook = float2(0.0, 0.25 * SymbolScale);
    
    // Part A: Upper Arc (The rainbow shape of the hook)
    // We calculate distance to the skeleton (centerline) of the arc
    float dArc = help_udArcUpper(pSym - centerHook, rHook);
    
    // Part B: Stem (Connecting right side of hook to center)
    // Starts at the right end of the arc (rHook, 0) relative to hook center
    // Ends closer to the center line to create the '?' shape
    float2 stemStart = centerHook + float2(rHook, 0.0);
    float2 stemEnd = centerHook + float2(0.0, -0.45 * SymbolScale);
    float dStem = help_sdSegment(pSym, stemStart, stemEnd);
    
    // Combine Arc and Stem smoothly
    float dHookShape = help_smin(dArc, dStem, 0.05 * SymbolScale) - (SymbolThickness * 0.5);
    
    // Part C: The Dot
    float2 dotPos = stemEnd - float2(0.0, 0.15 * SymbolScale + SymbolThickness);
    // Dot radius scales with thickness to keep proportions
    float dotRadius = SymbolThickness * 0.6;
    float dDot = length(pSym - dotPos) - dotRadius;
    
    // Final Symbol SDF
    float dSymbol = min(dHookShape, dDot);
    float symbolAlpha = smoothstep(aa, -aa, dSymbol);

    // 4) Composition
    // Composite Symbol OVER Circle
    // We use standard alpha blending: out = src * srcA + dst * (1-srcA)
    
    float4 colCircle = float4(CircleColor.rgb, 1.0) * circleAlpha * CircleColor.a;
    float4 colSymbol = float4(SymbolColor.rgb, 1.0) * symbolAlpha * SymbolColor.a;
    
    // Simple blend: Max alpha for opacity, Lerp for color
    // Since shapes might overlap, we blend symbol over circle
    float finalAlpha = max(colCircle.a, colSymbol.a);
    
    // Result blending
    float3 finalRGB = lerp(colCircle.rgb, colSymbol.rgb, colSymbol.a / max(finalAlpha, 1e-5));
    
    outColor = float4(finalRGB * finalAlpha, finalAlpha);
}