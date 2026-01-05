#ifndef PI
#define PI 3.14159265359
#endif

// --- Helpers ---

// Signed distance to a box
float sdBox(float2 p, float2 b) {
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// Signed distance to a line segment
float sdSegment(float2 p, float2 a, float2 b) {
    float2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}

// --- Main Function ---
// User Request: A cartoon umbrella with adjustable domed canopy, radial segments, scalloped edges, and J-shaped handle.
void CartoonUmbrella_float(float2 UV, float Width, float Height, float DomePower, float Segments, float WaveAmp, float ShaftLength, float ShaftThick, float HandleRadius, float StrokeWidth, float FerruleSize, float4 Color1, float4 Color2, float4 HandleColor, float4 OutlineColor, out float4 outColor) {
    // PLAN:
    // 1) Center UVs. define SDF variables.
    // 2) Build Shaft & Handle SDF (Vertical segment + Hook/J-curve).
    // 3) Build Canopy SDF (Superellipse approximation + Scalloped Wave cut).
    // 4) Calculate Panel Pattern based on pseudo-3D mapping (asin).
    // 5) Build Ferrule SDF (Box on top).
    // 6) Composite layers (Stem -> Canopy -> Ferrule) with outlines.
    
    float2 p = UV - 0.5;
    float aa = fwidth(length(p)); // Anti-aliasing factor
    if (aa == 0) aa = 0.001;

    // --- 1. SHAFT & HANDLE ---
    // Shaft starts inside canopy (y > 0) and goes down
    float shaftTopY = Height * 0.5;
    float shaftBottomY = -ShaftLength;
    
    // Vertical part of shaft
    float dShaft = sdSegment(p, float2(0.0, shaftTopY), float2(0.0, shaftBottomY)) - ShaftThick;
    
    // Handle (J-Curve) attached at the bottom of the shaft
    // Logic: A semi-circle arc curving to the left, plus a small tip.
    // Center of curve is offset to the left by HandleRadius
    float2 hCenter = float2(-HandleRadius, shaftBottomY);
    float2 hp = p - hCenter;
    
    // Basic ring distance
    float dRing = abs(length(hp) - HandleRadius) - ShaftThick;
    
    // Clip the ring to form a J (bottom half, 180 degrees)
    // We want the arc where local y < 0. For y > 0, we cap the ends.
    // One end connects to shaft (x=HandleRadius, y=0), the other is the tip (x=-HandleRadius, y=0).
    float dHandle;
    if (hp.y < 0.0) {
        dHandle = dRing;
    } else {
        // Distance to the tip endpoint (the shaft endpoint is covered by dShaft)
        // We only calculate distance to the free tip (-HandleRadius, 0)
        dHandle = length(hp - float2(-HandleRadius, 0.0)) - ShaftThick;
    }
    
    // Combine Shaft and Handle
    float dStem = min(dShaft, dHandle);

    // --- 2. CANOPY ---
    // Coordinate mapping for panels (Simulate 3D dome curvature)
    // Map linear x to angular phi using asin
    float xNorm = clamp(p.x / Width, -1.0, 1.0);
    float phi = asin(xNorm); // Returns -PI/2 to PI/2
    float t = (phi / PI) + 0.5; // 0 to 1 mapping across width
    
    // Panel Pattern
    float effectiveSegments = max(1.0, Segments);
    float panelID = floor(t * effectiveSegments);
    float4 panelFill = (fmod(panelID, 2.0) == 0.0) ? Color1 : Color2;
    
    // Scalloped Edge Wave
    // Wave should align with segments. We use cos(phi * Segments) to get peaks/valleys.
    // Use abs(cos) to make sharp cusps for the scallops
    float wavePhase = phi * effectiveSegments;
    float waveY = WaveAmp * abs(cos(wavePhase)); 
    
    // Base Dome Shape (Superellipse approx)
    // (x/W)^n + (y/H)^n = 1 -> We approximate SDF for drawing
    // We scale p to unit space to calculate generalized distance
    float2 pScaled = float2(abs(p.x) / Width, p.y / Height);
    // Power function for curvature (2.0 = Ellipse, <2 = Pointy, >2 = Boxy)
    float k = max(0.5, DomePower);
    // Approx distance: (Length^k - 1) * scale
    // Note: This isn't Euclidean but good enough for outline width if aspect ratio isn't extreme
    float lenPow = pow(pScaled.x, k) + pow(max(0.0, pScaled.y), k); // max(y) to clip bottom half later
    float dDome = (pow(lenPow, 1.0/k) - 1.0) * min(Width, Height);
    
    // Bottom Cutoff Plane with Wave
    // We want p.y > (0 + waveY). The base of the canopy is at y=0.
    // SDF for 'below plane': y - level. 
    float canopyBaseY = 0.0;
    float dBottom = -(p.y - (canopyBaseY + waveY)); // Negative inside (i.e. above wave)
    
    // Intersection: Max(dDome, dBottom)
    // We want inside dome (dDome < 0) AND above wave (dBottom < 0)
    float dCanopy = max(dDome, dBottom);

    // --- 3. FERRULE ---
    // Small box sitting at the top apex (0, Height)
    float dFerrule = sdBox(p - float2(0.0, Height), float2(FerruleSize * 0.5, FerruleSize * 0.8)) - 0.002;

    // --- 4. COMPOSITING ---
    // Helper to mix layers with outlines
    
    // Stem Layer
    // Outline is where dStem < StrokeWidth. Fill is where dStem < 0.
    // But simpler: Draw outline (Stroke Color) then Fill (Handle Color) inside.
    float stemMask = 1.0 - smoothstep(0.0, aa, dStem - StrokeWidth);
    float stemFillMask = 1.0 - smoothstep(0.0, aa, dStem);
    float4 lStem = lerp(float4(0,0,0,0), OutlineColor, stemMask);
    lStem = lerp(lStem, HandleColor, stemFillMask);

    // Canopy Layer
    float canopyMask = 1.0 - smoothstep(0.0, aa, dCanopy - StrokeWidth);
    float canopyFillMask = 1.0 - smoothstep(0.0, aa, dCanopy);
    float4 lCanopy = lerp(float4(0,0,0,0), OutlineColor, canopyMask);
    lCanopy = lerp(lCanopy, panelFill, canopyFillMask);
    
    // Ferrule Layer
    float ferruleMask = 1.0 - smoothstep(0.0, aa, dFerrule - StrokeWidth);
    float ferruleFillMask = 1.0 - smoothstep(0.0, aa, dFerrule);
    float4 lFerrule = lerp(float4(0,0,0,0), OutlineColor, ferruleMask);
    lFerrule = lerp(lFerrule, HandleColor, ferruleFillMask);
    
    // Blend Layers (Painters Algorithm: Back to Front)
    // Order: Stem -> Canopy -> Ferrule
    // Use premultiplied alpha blending logic: out = src + dst * (1 - src.a)
    
    float4 final = lStem;
    final = lCanopy + final * (1.0 - lCanopy.a);
    final = lFerrule + final * (1.0 - lFerrule.a);
    
    outColor = final;
}