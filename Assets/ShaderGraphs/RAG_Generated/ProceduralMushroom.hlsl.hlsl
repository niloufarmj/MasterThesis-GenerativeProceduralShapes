#ifndef PI
#define PI 3.14159265359
#endif

// --- Helper Functions ---

// Pseudo-random hash for spot generation
float2 mush_hash22(float2 p) {
    float3 p3 = frac(float3(p.xyx) * float3(.1031, .1030, .0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return frac((p3.xx + p3.yz) * p3.zy);
}

// Smooth Maximum for shape intersection
float mush_smax(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (a - b) / k, 0.0, 1.0);
    return lerp(b, a, h) + k * h * (1.0 - h);
}

// Standard Alpha Compositing (Source Over Destination)
float4 mush_blend(float4 top, float4 bottom) {
    float a = top.a + bottom.a * (1.0 - top.a);
    float3 rgb = (top.rgb * top.a + bottom.rgb * bottom.a * (1.0 - top.a)) / max(a, 1e-6);
    return float4(rgb, a);
}

// Layer Generator: Automatically applies antialiased fill and stroke
float4 mush_layer(float d, float4 fillCol, float4 strokeCol, float strokeW, float aa) {
    float strokeMask = 1.0 - smoothstep(-aa, aa, d - strokeW);
    float fillMask = 1.0 - smoothstep(-aa, aa, d);
    
    float4 sCol = float4(strokeCol.rgb, strokeCol.a * strokeMask);
    float4 fCol = float4(fillCol.rgb, fillCol.a * fillMask);
    return mush_blend(fCol, sCol);
}

// Grass Blade SDF Helper
float mush_blade(float2 p, float2 offset, float h, float w, float bend, float2 gPos) {
    float2 bp = p - (gPos + offset);
    bp.x -= bend * bp.y * bp.y;
    float d = max(abs(bp.x) - w * clamp(1.0 - bp.y / h, 0.0, 1.0), max(-bp.y, bp.y - h));
    return d - 0.005; // Subtract slightly to round off the tips
}

// --- Main Shader Function ---
void ProceduralMushroom_float(
    float2 UV,
    float2 CapSize, 
    float CapCurve, 
    float CapFlatness,
    float2 InnerCapSize, 
    float InnerCapOffset,
    float2 StemSize, 
    float StemBulge,
    float SpotDensity, 
    float SpotRadius,
    float4 CapColor, 
    float4 SpotColor, 
    float4 InnerCapColor,
    float4 StemColor, 
    float4 GrassColor, 
    float4 StrokeColor,
    float StrokeWidth,
    out float4 outColor
) {
    // 1. Setup Base Coordinates
    float2 center = float2(0.5, 0.5);
    float2 p = UV - center;
    
    float aa = fwidth(length(p));
    if (aa == 0) aa = 0.005;

    // 2. Define Spatial Anchors
    float2 capPos = float2(0.0, 0.1);
    float2 innerPos = float2(capPos.x, capPos.y - CapFlatness - InnerCapOffset);
    float2 stemPos = float2(capPos.x, innerPos.y - StemSize.y + 0.05);
    float2 gPos = float2(stemPos.x, stemPos.y - StemSize.y + 0.02);

    // --- SHAPE 1: GRASS BASE ---
    float2 groundP = p - float2(stemPos.x, gPos.y + 0.01);
    float dGround = (length(groundP * float2(1.0, 3.0)) - 0.3) * 0.33;
    
    float dBlades = 100.0;
    dBlades = min(dBlades, mush_blade(p, float2(-0.20, 0.0), 0.15, 0.025,  2.0, gPos));
    dBlades = min(dBlades, mush_blade(p, float2(-0.13, 0.0), 0.10, 0.020,  3.0, gPos));
    dBlades = min(dBlades, mush_blade(p, float2(-0.26, 0.0), 0.07, 0.015,  4.0, gPos));
    dBlades = min(dBlades, mush_blade(p, float2( 0.20, 0.0), 0.15, 0.025, -2.0, gPos));
    dBlades = min(dBlades, mush_blade(p, float2( 0.13, 0.0), 0.10, 0.020, -3.0, gPos));
    dBlades = min(dBlades, mush_blade(p, float2( 0.26, 0.0), 0.07, 0.015, -4.0, gPos));
    
    float dGrassTotal = min(dGround, dBlades);

    // Grass Shading
    float grassShadow = smoothstep(-0.4, -0.2, p.y);
    float4 finalGrassColor = lerp(GrassColor * 0.6, GrassColor, grassShadow);

    // --- SHAPE 2: INNER CAP ---
    float dInnerCap = length((p - innerPos) / max(InnerCapSize, 0.001)) - 1.0;
    dInnerCap *= min(InnerCapSize.x, InnerCapSize.y);

    // Inner Cap Shading (Gills)
    float angle = atan2(p.y - innerPos.y, abs(p.x - capPos.x)); 
    float gills = sin(angle * 50.0);
    float gillLines = smoothstep(0.9, 1.0, gills);
    float gillMaskInside = 1.0 - smoothstep(-aa, aa, dInnerCap + 0.02);
    gillLines *= gillMaskInside;
    float4 finalInnerCapColor = lerp(InnerCapColor, float4(InnerCapColor.rgb * 0.6, InnerCapColor.a), gillLines * 0.6);

    // --- SHAPE 3: STEM ---
    float t = clamp((p.y - stemPos.y) / max(StemSize.y, 0.001), -1.0, 1.0);
    float norm = 0.5 - 0.5 * t; // 0 at top, 1 at bottom
    float w = StemSize.x * (1.0 + StemBulge * norm * norm);
    float2 qStem = float2(abs(p.x) - w, abs(p.y - stemPos.y) - StemSize.y);
    float dStem = length(max(qStem, 0.0)) + min(max(qStem.x, qStem.y), 0.0) - 0.05;

    // Stem Crease Details
    float2 c1p = p - float2(stemPos.x - 0.03, stemPos.y - StemSize.y + 0.06);
    float c1d = length(float2(c1p.x + 2.0 * c1p.y * c1p.y, max(0.0, abs(c1p.y) - 0.03))) - 0.005;
    float2 c2p = p - float2(stemPos.x + 0.04, stemPos.y - StemSize.y + 0.04);
    float c2d = length(float2(c2p.x - 1.5 * c2p.y * c2p.y, max(0.0, abs(c2p.y) - 0.02))) - 0.005;
    float stemCreases = min(c1d, c2d);

    // Stem Shading
    float stemShadowMask = smoothstep(-StemSize.x, StemSize.x, p.x - stemPos.x);
    float4 finalStemColor = lerp(StemColor, StemColor * 0.75, stemShadowMask * 0.7);

    // --- SHAPE 4: CAP MAIN ---
    float dCapOuter = length((p - capPos) / max(CapSize, 0.001)) - 1.0;
    dCapOuter *= min(CapSize.x, CapSize.y);
    
    float frontEdgeY = capPos.y - CapFlatness + CapCurve * (p.x * p.x);
    float dFrontEdge = -(p.y - frontEdgeY);
    
    float dCapMain = mush_smax(dCapOuter, dFrontEdge, 0.05);

    // Cap Shading
    float capShadowMask = smoothstep(0.0, 0.2, p.y - frontEdgeY);
    float4 finalCapColor = lerp(CapColor * 0.7, CapColor, capShadowMask);
    float capRim = smoothstep(-0.02, 0.05, dCapOuter + 0.06) * smoothstep(0.0, -0.4, p.x - capPos.x);
    finalCapColor = lerp(finalCapColor, float4(1.0, 1.0, 1.0, 1.0), capRim * 0.3);

    // --- SPOTS ON CAP ---
    float2 pSpot = p - capPos;
    pSpot.x *= 1.0 + 0.5 * (pSpot.y / max(CapSize.y, 0.001)); 
    pSpot.y *= 1.0 + 0.2 * abs(pSpot.x / max(CapSize.x, 0.001)); 

    float2 spotUV = (pSpot / max(CapSize, 0.001)) * SpotDensity;
    float2 i_st = floor(spotUV);
    float2 f_st = frac(spotUV);
    float minSpotDist = 10.0;
    
    for (int sy = -1; sy <= 1; sy++) {
        for (int sx = -1; sx <= 1; sx++) {
            float2 neighbor = float2(sx, sy);
            float2 pointInCell = mush_hash22(i_st + neighbor);
            float2 jitter = 0.5 + 0.4 * sin(pointInCell * 6.2831);
            float2 diff = neighbor + jitter - f_st;
            float dist = length(diff);
            float sizeMod = 0.6 + 0.8 * pointInCell.y;
            minSpotDist = min(minSpotDist, dist - SpotRadius * sizeMod);
        }
    }
    
    float spotMask = 1.0 - smoothstep(-aa, aa, minSpotDist);
    float capInsideMask = 1.0 - smoothstep(-aa, aa, dCapMain + 0.02);
    spotMask *= capInsideMask;

    // --- COMPOSITING (Back to Front) ---
    float4 finalColor = float4(0, 0, 0, 0);

    // Layer 1: Grass Base
    float4 grassLayer = mush_layer(dGrassTotal, finalGrassColor, StrokeColor, StrokeWidth, aa);
    finalColor = mush_blend(grassLayer, finalColor);

    // Layer 2: Inner Cap
    float4 innerCapLayer = mush_layer(dInnerCap, finalInnerCapColor, StrokeColor, StrokeWidth, aa);
    finalColor = mush_blend(innerCapLayer, finalColor);

    // Layer 3: Stem
    float stemFillMask = 1.0 - smoothstep(-aa, aa, dStem);
    float stemStrokeMask = 1.0 - smoothstep(-aa, aa, dStem - StrokeWidth);
    float4 stemStrokeCol = float4(StrokeColor.rgb, StrokeColor.a * stemStrokeMask);
    float4 stemFillLayer = float4(finalStemColor.rgb, finalStemColor.a * stemFillMask);
    
    // Apply stem creases
    float creaseMask = 1.0 - smoothstep(-aa, aa, stemCreases);
    stemFillLayer.rgb = lerp(stemFillLayer.rgb, StrokeColor.rgb, creaseMask * stemFillMask);
    
    float4 stemLayer = mush_blend(stemFillLayer, stemStrokeCol);
    finalColor = mush_blend(stemLayer, finalColor);

    // Layer 4: Cap Main
    float capFillMask = 1.0 - smoothstep(-aa, aa, dCapMain);
    float capStrokeMask = 1.0 - smoothstep(-aa, aa, dCapMain - StrokeWidth);
    float4 capStrokeCol = float4(StrokeColor.rgb, StrokeColor.a * capStrokeMask);
    float4 capFillLayer = float4(finalCapColor.rgb, finalCapColor.a * capFillMask);
    
    // Apply spots
    capFillLayer.rgb = lerp(capFillLayer.rgb, SpotColor.rgb, spotMask * SpotColor.a * capFillMask);
    
    float4 capLayer = mush_blend(capFillLayer, capStrokeCol);
    finalColor = mush_blend(capLayer, finalColor);

    // Output
    outColor = finalColor;
}
