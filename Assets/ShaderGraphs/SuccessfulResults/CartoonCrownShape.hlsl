/* 
  PLAN:
  1. Define helpers: sdBox, sdSegment, sdTriangle, opSmoothUnion.
  2. Setup Crown dimensions: Band is bottom 25%, Body is middle, Peaks are top.
  3. Construct SDF for Band (Rounded Box).
  4. Construct SDF for Body: 
     - Base Rectangle for the lower body part.
     - 3 Triangles for the peaks (Center, Left, Right).
     - Use opSmoothUnion to blend peaks and body for rounded valleys.
     - Subtract Roundness from the result to round the tips.
  5. Construct SDF for Jewels: 3 Circles at the tip locations.
  6. Compute masks using smoothstep (AA).
  7. Composite Colors: Band over Body, Jewels over everything.
*/

#ifndef PI
#define PI 3.14159265359
#endif

// --- Helpers ---

float sdBox(float2 p, float2 b) {
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

float sdCircle(float2 p, float r) {
    return length(p) - r;
}

float sdSegment(float2 p, float2 a, float2 b) {
    float2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}

// Isosceles Triangle: Width w, Height h, centered at base (0,0), tip at (0,h)
float sdTriangle(float2 p, float w, float h) {
    float2 a = float2(0.0, h);       // Tip
    float2 b = float2(w * 0.5, 0.0); // Right corner
    float2 c = float2(-w * 0.5, 0.0);// Left corner

    float d1 = sdSegment(p, a, b);
    float d2 = sdSegment(p, b, c);
    float d3 = sdSegment(p, c, a);

    // Signed Distance (Negative Inside)
    // Outward Normals:
    // Right Slope: (h, w/2)
    // Left Slope: (-h, w/2)
    // Bottom: (0, -1)
    float2 nRight = normalize(float2(h, w * 0.5));
    float2 nLeft  = normalize(float2(-h, w * 0.5));
    
    // Distance to planes
    float s1 = dot(p - a, nRight);
    float s2 = dot(p - a, nLeft);
    float s3 = -p.y; // Bottom plane passing through 0
    
    // Max of plane distances gives the signed distance approximation for sign
    float s = max(max(s1, s2), s3);
    
    return min(min(d1, d2), d3) * (s > 0.0 ? 1.0 : -1.0);
}

float opSmoothUnion(float d1, float d2, float k) {
    float h = clamp(0.5 + 0.5 * (d2 - d1) / max(k, 0.0001), 0.0, 1.0);
    return lerp(d2, d1, h) - k * h * (1.0 - h);
}

// --- Main Function ---

void CartoonCrownShape_float(
    float2 UV,
    float Width,
    float Height,
    float PeakHeight,
    float Roundness,
    float JewelSize,
    float4 BandColor,
    float4 BodyColor,
    float4 JewelColor,
    out float4 outColor
) {
    // Center UVs
    float2 p = UV - 0.5;
    
    // Dimensions
    float halfW = Width * 0.5;
    float halfH = Height * 0.5;
    
    // Vertical Segments
    // Band is bottom 25% of total height
    float bandH = Height * 0.25;
    // Peak area is top 'PeakHeight' portion of the body
    // The solid body fills the gap between band and peaks
    
    float yBottom = -halfH;
    float yBandTop = yBottom + bandH;
    float yTop = halfH;
    float yPeakBase = yTop - PeakHeight;
    
    // --- 1. Band SDF ---
    float2 bandPos = float2(0.0, yBottom + bandH * 0.5);
    float2 bandSize = float2(halfW, bandH * 0.5);
    // Shrink by Roundness for sdBox then subtract Roundness to round corners
    float dBand = sdBox(p - bandPos, bandSize - Roundness) - Roundness;
    
    // --- 2. Body SDF ---
    // Rectangular lower part of body (between band and peaks)
    // Ensure it overlaps band slightly downwards for continuity
    float rectBottom = yBandTop - 0.01;
    float rectH = max(0.0, yPeakBase - rectBottom);
    float2 rectPos = float2(0.0, rectBottom + rectH * 0.5);
    float2 rectSize = float2(halfW, rectH * 0.5);
    float dBodyRect = sdBox(p - rectPos, rectSize);
    
    // Peaks (3 Triangles)
    // Spacing: peaks at Center, Left, Right
    float peakOffset = Width * 0.35; // Position of side peaks
    float peakW = Width * 0.45;      // Width of each triangle base (overlap is good)
    float peakH = PeakHeight + Roundness; // Add roundness to height to compensate erosion
    
    // Base of triangles is at yPeakBase
    float2 pTri = p - float2(0.0, yPeakBase);
    
    float dPeakC = sdTriangle(pTri, peakW, peakH);
    float dPeakL = sdTriangle(pTri - float2(-peakOffset, 0.0), peakW, peakH);
    float dPeakR = sdTriangle(pTri - float2(peakOffset, 0.0), peakW, peakH);
    
    // Smoothly merge peaks
    float dPeaks = opSmoothUnion(dPeakC, dPeakL, Roundness);
    dPeaks = opSmoothUnion(dPeaks, dPeakR, Roundness);
    
    // Merge Peaks with Body Rect
    float dBodyRaw = opSmoothUnion(dBodyRect, dPeaks, Roundness);
    
    // Apply Roundness to the whole body silhouette (erodes sharp tips)
    // We used a slightly larger peak height to compensate
    float dBody = dBodyRaw - Roundness;
    
    // --- 3. Jewels SDF ---
    // Jewels sit on the tips. Tips are at yTop.
    // X locations are 0, -peakOffset, +peakOffset
    float yJewel = yTop;
    float dJewelC = sdCircle(p - float2(0.0, yJewel), JewelSize);
    float dJewelL = sdCircle(p - float2(-peakOffset, yJewel), JewelSize);
    float dJewelR = sdCircle(p - float2(peakOffset, yJewel), JewelSize);
    
    float dJewels = min(dJewelC, min(dJewelL, dJewelR));
    
    // --- 4. Composition ---
    // Anti-aliasing edge
    float aa = 0.005;
    // Masks (0 = Transparent, 1 = Opaque)
    float maskBand   = smoothstep(aa, -aa, dBand);
    float maskBody   = smoothstep(aa, -aa, dBody);
    float maskJewels = smoothstep(aa, -aa, dJewels);
    
    // Layering (Painter's Algorithm)
    // Initialize with transparent
    float4 color = float4(0, 0, 0, 0);
    
    // Draw Body
    color = lerp(color, BodyColor, maskBody);
    
    // Draw Band (on top of body)
    color = lerp(color, BandColor, maskBand);
    
    // Draw Jewels (on top of everything)
    color = lerp(color, JewelColor, maskJewels);
    
    outColor = color;
}

// ------------------------------------------------------------------------
//  Visual Result (High-level, parameter-invariant description)
// ------------------------------------------------------------------------
//  This function generates a **stylized 2D cartoon crown primitive**
//  using Signed Distance Functions (SDFs).
//
//  The visual result is a crown-like silhouette composed of three main
//  components: a rounded horizontal band at the bottom, a central body
//  with multiple upward peaks, and small circular jewel elements placed
//  near the tips of the peaks. The peaks are smoothly blended into the
//  body, producing rounded valleys and softened tips for a playful,
//  cartoon-style appearance.
//
//  The crown’s overall width and height, peak height, corner roundness,
//  band thickness, jewel size and placement, color composition, scale,
//  and positioning are fully controlled by input parameters and are not
//  fixed by the function itself.
//
//  The output is an anti-aliased RGBA color suitable for icons, badges,
//  achievement symbols, game UI elements, and expressive procedural
//  2D graphics.
// ------------------------------------------------------------------------
