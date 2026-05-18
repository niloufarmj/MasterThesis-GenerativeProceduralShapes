#ifndef PI
#define PI 3.14159265359
#endif

// --- Helper Functions ---

// Pseudo-random hash functions
float mushroom_hash11(float p) {
    p = frac(p * .1031);
    p *= p + 33.33;
    p *= p + p;
    return frac(p);
}

float2 mushroom_hash12(float t) {
    float3 p3 = frac(t * float3(.1031, .1030, .0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return frac((p3.xx + p3.yz) * p3.zy);
}

// Basic 2D Box SDF
float mushroom_sdBox(float2 p, float2 b) {
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// 2D Rounded Box SDF with distinct top/bottom radii
float mushroom_sdRoundBox(float2 p, float2 b, float rTop, float rBot) {
    float r = p.y > 0.0 ? rTop : rBot;
    float2 q = abs(p) - b + r;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

// --- Main Shader Function ---
void ProceduralMushroomTower_float(
    float2 UV,
    float totalHeight,
    float shaftWidth,
    float mushroomShelfCount,
    float shelfSize,
    float shelfThickness,
    float shelfAngle,
    float featureDensity,
    float shelfVerticalSpread,
    float surfaceRoughness,
    float pittingDensity,
    float capWidth,
    float capHeight,
    float capBrimWidth,
    float gillCount,
    float4 ShaftColorLight,
    float4 ShaftColorDark,
    float4 SpotLightColor,
    float4 SpotDarkColor,
    float4 ShelfColor,
    float4 GillLightColor,
    float4 GillDarkColor,
    float4 CapColor,
    float4 CapBandColor,
    float4 CapHighlightColor,
    out float4 outColor
) {
    // Recenter coordinate system horizontally
    float2 p = UV - float2(0.5, 0.0);
    
    // Screen-space anti-aliasing approximation
    float aa = fwidth(p.y);
    if (aa == 0.0) aa = 0.002;
    
    // --- STRUCTURAL LAYOUT ---
    float shaftBottom = 0.05;
    float shaftTop = shaftBottom + totalHeight - capHeight;
    float shaftCenterY = (shaftBottom + shaftTop) * 0.5;
    float shaftHalfH = (shaftTop - shaftBottom) * 0.5;
    float shaftHalfW = shaftWidth * 0.5;
    
    float capBaseY = shaftTop;
    float capCenterY = capBaseY + capHeight * 0.5;
    
    float gillTotalH = 0.05;
    float gillHalfH = gillTotalH * 0.5;
    float gillW = shaftHalfW + capBrimWidth;
    
    // --- 1. SHAFT SDF ---
    float dShaft = mushroom_sdBox(p - float2(0.0, shaftCenterY), float2(shaftHalfW, shaftHalfH));
    
    // --- 2. SURFACE PITTING SDF ---
    float dSpotsDark = 999.0;
    float dSpotsLight = 999.0;
    int numSpots = int(clamp(pittingDensity, 0.0, 30.0));
    
    for(int i = 0; i < 30; i++) {
        if(i >= numSpots) break;
        float2 h = mushroom_hash12(float(i + 123));
        float spotX = (h.x - 0.5) * shaftHalfW * 1.5; 
        float spotY = shaftBottom + h.y * (shaftTop - shaftBottom);
        float spotR = 0.01 + mushroom_hash11(float(i + 456)) * 0.02;
        
        float d = length(p - float2(spotX, spotY)) - spotR;
        if (spotX > 0.0) dSpotsDark = min(dSpotsDark, d);
        else dSpotsLight = min(dSpotsLight, d);
    }
    
    // --- 3. SHELF PROTRUSIONS SDF ---
    float dShelves = 999.0;
    int numShelves = int(clamp(mushroomShelfCount, 0.0, 20.0));
    
    for(int j = 0; j < 20; j++) {
        if(j >= numShelves) break;
        float2 h = mushroom_hash12(float(j + 789));
        
        float side = h.x > 0.5 ? 1.0 : -1.0;
        
        // Distribute vertically based on spread parameter
        float spread = lerp(h.y, float(j) / max(float(numShelves - 1), 1.0), shelfVerticalSpread);
        float shelfY = shaftBottom + 0.15 + spread * (shaftTop - shaftBottom - 0.3);
        float shelfX = side * shaftHalfW;
        
        float2 sp = p - float2(shelfX, shelfY);
        
        // Apply outward tilt/angle
        float angle = shelfAngle * (h.y - 0.5) * PI * 0.5 * side;
        float s = sin(angle), c = cos(angle);
        sp = float2(sp.x * c - sp.y * s, sp.x * s + sp.y * c);
        
        // Offset outwards
        sp.x -= side * shelfSize * 0.5;
        
        // Ellipse base shape
        float2 eq = sp;
        float ds = length(eq / float2(shelfSize * 0.5, shelfThickness)) - 1.0;
        ds *= min(shelfSize * 0.5, shelfThickness);
        
        // Cut off the top to make it flat
        ds = max(ds, eq.y);
        
        // Carve out the underside to make it concave
        float concaveR = shelfSize * 0.8;
        float overlap = shelfThickness * 0.5;
        float concaveD = length(eq - float2(0.0, -shelfThickness - concaveR + overlap)) - concaveR;
        ds = max(ds, -concaveD);
        
        dShelves = min(dShelves, ds);
    }
    
    // --- 4. GILLS COLLAR SDF ---
    float2 gp = p - float2(0.0, capBaseY - gillHalfH);
    float freq = gillCount / max(gillW * 2.0, 0.001);
    float scallop = abs(cos(p.x * PI * freq)) * 0.015;
    
    // Apply wave displacement only to the bottom edge
    float waveWeight = smoothstep(0.0, -gillHalfH, gp.y);
    float2 gpWavy = gp;
    gpWavy.y += scallop * waveWeight;
    float dGills = mushroom_sdRoundBox(gpWavy, float2(gillW, gillHalfH), 0.0, 0.015);
    
    // --- 5. TOP CAP SDF ---
    float2 cp = p - float2(0.0, capCenterY);
    float dCap = mushroom_sdRoundBox(cp, float2(capWidth * 0.5, capHeight * 0.5), capHeight * 0.4, capHeight * 0.1);
    
    // Sub-regions of the cap
    float dCapBand = max(dCap, cp.y + capHeight * 0.5 - capHeight * 0.2); // Bottom 20%
    
    // Cap Highlights and Details
    float dHighlight = length(cp - float2(-capWidth * 0.15, capHeight * 0.15)) - capWidth * 0.2;
    float2 dp1 = cp - float2(-capWidth * 0.25, capHeight * 0.05);
    float dDetail1 = length(dp1) - capWidth * 0.06;
    float2 dp2 = cp - float2(-capWidth * 0.1, -capHeight * 0.1);
    float dDetail2 = length(dp2) - capWidth * 0.04;
    float dDetails = min(dDetail1, dDetail2);
    
    
    // --- COMPOSITING & COLORING ---
    float4 finalColor = float4(0.0, 0.0, 0.0, 0.0);
    
    // A. Shaft
    float shaftMask = 1.0 - smoothstep(-aa, aa, dShaft);
    float4 shaftCol = lerp(ShaftColorLight, ShaftColorDark, smoothstep(-0.02, 0.05, p.x));
    
    // Stucco texture variation
    float surfaceNoise = sin(p.x * featureDensity * 300.0) * cos(p.y * featureDensity * 300.0);
    surfaceNoise += sin(p.x * featureDensity * 700.0 + p.y * 100.0) * cos(p.y * featureDensity * 700.0 + p.x * 100.0) * 0.5;
    shaftCol.rgb += surfaceNoise * surfaceRoughness * 0.1;
    
    // Apply Pitting
    float spotDarkMask = 1.0 - smoothstep(-aa, aa, dSpotsDark);
    float spotLightMask = 1.0 - smoothstep(-aa, aa, dSpotsLight);
    shaftCol = lerp(shaftCol, SpotDarkColor, spotDarkMask);
    shaftCol = lerp(shaftCol, SpotLightColor, spotLightMask);
    
    finalColor = lerp(finalColor, float4(shaftCol.rgb, 1.0), shaftMask);
    
    // B. Shelves
    float shelfMask = 1.0 - smoothstep(-aa, aa, dShelves);
    finalColor = lerp(finalColor, float4(ShelfColor.rgb, 1.0), shelfMask);
    
    // C. Gills
    float gillMask = 1.0 - smoothstep(-aa, aa, dGills);
    float gillGradient = smoothstep(capBaseY - gillTotalH * 1.5, capBaseY, p.y);
    float4 gillCol = lerp(GillDarkColor, GillLightColor, gillGradient);
    finalColor = lerp(finalColor, float4(gillCol.rgb, 1.0), gillMask);
    
    // D. Main Cap
    float capMask = 1.0 - smoothstep(-aa, aa, dCap);
    float capBandMask = 1.0 - smoothstep(-aa, aa, dCapBand);
    float highlightMask = 1.0 - smoothstep(-aa, aa, dHighlight);
    float detailMask = 1.0 - smoothstep(-aa, aa, dDetails);
    
    float3 capCol = CapColor.rgb;
    capCol = lerp(capCol, CapBandColor.rgb, capBandMask);
    capCol = lerp(capCol, CapHighlightColor.rgb, highlightMask * 0.3);
    capCol = lerp(capCol, CapHighlightColor.rgb, detailMask * 0.8);
    
    finalColor = lerp(finalColor, float4(capCol, 1.0), capMask);
    
    outColor = finalColor;
}
