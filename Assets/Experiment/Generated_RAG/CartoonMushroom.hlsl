#ifndef PI
#define PI 3.14159265359
#endif

// --- Helper Functions ---

// Straight-alpha composite (Source Over Destination)
inline float4 blend_over(float4 src, float4 dst) {
    float a = src.a + dst.a * (1.0 - src.a);
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-8);
    return float4(c, a);
}

// Smooth Maximum for blending intersections (rounds outward corners)
float smax(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (a - b) / k, 0.0, 1.0);
    return lerp(b, a, h) + k * h * (1.0 - h);
}

// Exact SDF for a line segment
float sdSegment(float2 p, float2 a, float2 b) {
    float2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-5), 0.0, 1.0);
    return length(pa - ba * h);
}

// --- Main Function ---

void CartoonMushroom_float(
    float2 UV,
    float CapWidth,
    float CapHeight,
    float4 CapColor,
    float SpotCount,
    float SpotSize,
    float4 SpotColor,
    float StalkWidth,
    float StalkHeight,
    float4 StalkColor,
    float StrokeWidth,
    float4 StrokeColor,
    out float4 outColor
) {
    // 1. Coordinate setup: Center at (0.5, 0.5), map to [-1, 1]
    float2 p = (UV - 0.5) * 2.0;
    
    // Screen-space analytical anti-aliasing
    float aa = length(fwidth(p)) * 0.5;
    // Fallback in case fwidth is 0
    aa = max(aa, 0.005);
    
    // Safety clamping for parameters to prevent broken geometry
    float cW = max(CapWidth, 0.1);
    float cH = max(CapHeight, 0.1);
    float sW = max(StalkWidth, 0.05);
    float sH = max(StalkHeight, 0.1);
    float stroke = max(StrokeWidth, 0.0);
    
    // Base Y offset to vertically center the shape in the [-1, 1] domain
    float CapOffsetY = -0.05; 
    
    // --- Geometry SDFs ---
    
    // A. Cap SDF (Perfect Dome with flat bottom and rounded corners)
    // Calculate the circle radius and center offset to perfectly hit width and height
    float Y_offset = (cW * cW * 0.25 - cH * cH) / max(2.0 * cH, 0.001);
    float capRadius = cH + Y_offset;
    float2 capCenter = float2(0.0, CapOffsetY - Y_offset);
    
    float dCircle = length(p - capCenter) - capRadius;
    float dFlat = -(p.y - CapOffsetY); // Bottom flat edge
    
    // Intersect the circle and the flat half-plane, applying a smooth corner blend
    float dCap = smax(dCircle, dFlat, 0.08);
    
    // B. Stalk SDF (Vertical capsule segment)
    float2 stalkTop = float2(0.0, CapOffsetY);
    // The capsule radius expands downwards by sW*0.5, so we adjust the end point
    float2 stalkBottom = float2(0.0, CapOffsetY - sH + sW * 0.5);
    float dStalk = sdSegment(p, stalkTop, stalkBottom) - sW * 0.5;
    
    // C. Spots SDF
    int nSpots = (int)clamp(round(SpotCount), 0.0, 3.0);
    float dSpots = 100.0;
    
    if (nSpots == 1 || nSpots == 3) {
        // Center Spot
        float2 spotCenter = float2(0.0, CapOffsetY + cH * 0.45);
        dSpots = min(dSpots, length(p - spotCenter) - SpotSize);
    }
    if (nSpots >= 2) {
        // Left and Right Spots
        float yOff = CapOffsetY + cH * 0.25;
        float xOff = cW * 0.28;
        float dLeftSpot = length(p - float2(-xOff, yOff)) - SpotSize;
        float dRightSpot = length(p - float2(xOff, yOff)) - SpotSize;
        dSpots = min(dSpots, min(dLeftSpot, dRightSpot));
    }
    
    // --- Rendering & Compositing ---
    
    // Initialize with transparent background
    outColor = float4(0.0, 0.0, 0.0, 0.0);
    
    // Layer 1: Stalk Outline
    // dStalk - stroke places the boundary stroke outwards
    float stalkOutA = smoothstep(aa, -aa, dStalk - stroke);
    float4 stalkOutLayer = float4(StrokeColor.rgb, StrokeColor.a * stalkOutA);
    outColor = blend_over(stalkOutLayer, outColor);
    
    // Layer 2: Stalk Fill
    float stalkFillA = smoothstep(aa, -aa, dStalk);
    float4 stalkFillLayer = float4(StalkColor.rgb, StalkColor.a * stalkFillA);
    outColor = blend_over(stalkFillLayer, outColor);
    
    // Layer 3: Cap Outline
    // Layering this on top gives the cartoon overlap effect over the stalk
    float capOutA = smoothstep(aa, -aa, dCap - stroke);
    float4 capOutLayer = float4(StrokeColor.rgb, StrokeColor.a * capOutA);
    outColor = blend_over(capOutLayer, outColor);
    
    // Layer 4: Cap Fill
    float capFillA = smoothstep(aa, -aa, dCap);
    float4 capFillLayer = float4(CapColor.rgb, CapColor.a * capFillA);
    outColor = blend_over(capFillLayer, outColor);
    
    // Layer 5: Spots Fill
    float spotsA = smoothstep(aa, -aa, dSpots);
    // Mask spots so they never bleed into the cap's outline if they get too large
    float capMask = smoothstep(aa, -aa, dCap + 0.01);
    float4 spotsLayer = float4(SpotColor.rgb, SpotColor.a * spotsA * capMask);
    outColor = blend_over(spotsLayer, outColor);
    
    // Final safety clamp
    outColor = saturate(outColor);
}
