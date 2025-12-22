/* 
  PLAN:
  1. Define SDF helpers: sdRoundedBox, sdCircle, sdSegment, smin.
  2. Center UVs to (0,0) and handle sizing.
  3. Generate SDF for the square Box container.
  4. Generate SDF for the Question Mark symbol:
     - Construct the 'hook' using smooth-min combined segments (Bezier-like approximation).
     - Construct the 'dot' using a circle.
     - Combine hook and dot.
  5. Calculate anti-aliased masks for both Box and Symbol.
  6. Composite the Symbol color OVER the Box color using standard alpha blending.
  7. Output final color.
*/

#ifndef PI
#define PI 3.14159265359
#endif

// --- Helpers ---

// SDF for a box with rounded corners
float sdRoundedBox(float2 p, float2 b, float4 r) {
    r.xy = (p.x > 0.0) ? r.xy : r.zw;
    r.x  = (p.y > 0.0) ? r.x  : r.y;
    float2 q = abs(p) - b + r.x;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r.x;
}

// SDF for a line segment
float sdSegment(float2 p, float2 a, float2 b) {
    float2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}

// SDF for a circle
float sdCircle(float2 p, float r) {
    return length(p) - r;
}

// Polynomial Smooth Min (for blending shapes organically)
float smin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return lerp(b, a, h) - k * h * (1.0 - h);
}

// Alpha compositing: Source Over Destination
float4 compositeColors(float4 src, float4 dst) {
    float outA = src.a + dst.a * (1.0 - src.a);
    float3 outRGB = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(outA, 0.0001);
    return float4(outRGB, outA);
}

// --- Main Function ---
void QuestionMarkBoxIcon_float(float2 UV, float Size, float SymbolScale, float4 BoxColor, float4 SymbolColor, out float4 outColor) {
    // 1. Center coordinates
    float2 p = UV - 0.5;
    
    // 2. Box Logic
    // Size represents half-extent (0.5 = full size)
    float boxSize = max(Size, 0.001);
    float radius = boxSize * 0.2; // 20% corner radius
    float dBox = sdRoundedBox(p, float2(boxSize, boxSize), float4(radius, radius, radius, radius));
    
    // 3. Question Mark Logic
    // Normalize coordinates for the symbol so blending/thickness works consistently
    // SymbolScale controls size relative to the box
    float scaleFactor = boxSize * SymbolScale * 2.0;
    float2 q = p / max(scaleFactor, 0.001);
    
    float thickness = 0.08; 
    
    // A. The Hook (constructed from 3 segments smoothed together)
    // Points approximate a '?' curve
    float2 p1 = float2(-0.18, 0.18); // Start (Left-Mid)
    float2 p2 = float2(0.0, 0.35);   // Peak (Top-Center)
    float2 p3 = float2(0.20, 0.18);  // Turn (Right-Mid)
    float2 p4 = float2(0.0, -0.12);  // Stem Bottom (Center-Low)
    
    float dS1 = sdSegment(q, p1, p2);
    float dS2 = sdSegment(q, p2, p3);
    float dS3 = sdSegment(q, p3, p4);
    
    // Smoothly blend segments to create a continuous curve
    float dHook = smin(dS1, dS2, 0.08);
    dHook = smin(dHook, dS3, 0.08);
    dHook -= thickness; // Expand line to thickness
    
    // B. The Dot
    float dDot = sdCircle(q - float2(0.0, -0.35), thickness);
    
    // Combine Hook and Dot
    float dSymbolUnscaled = min(dHook, dDot);
    float dSymbol = dSymbolUnscaled * scaleFactor; // Scale distance back to world space
    
    // 4. Anti-Aliasing
    float aa = 0.005; // Standard smoothness width
    
    // Compute Coverage Masks
    float boxMask = smoothstep(aa, -aa, dBox);
    float symbolMask = smoothstep(aa, -aa, dSymbol);
    
    // 5. Coloring & Compositing
    // Prepare Source (Symbol) and Destination (Box)
    float4 src = float4(SymbolColor.rgb, SymbolColor.a * symbolMask);
    float4 dst = float4(BoxColor.rgb, BoxColor.a * boxMask);
    
    // Composite Symbol OVER Box
    outColor = compositeColors(src, dst);
}