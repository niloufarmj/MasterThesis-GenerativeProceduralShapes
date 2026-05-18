#ifndef PI
#define PI 3.14159265359
#endif

// Helper functions
float mushroom_hash11(float p) {
    return frac(sin(p * 12.9898) * 43758.5453);
}

float mushroom_noise1D(float x) {
    float i = floor(x);
    float f = frac(x);
    f = f * f * (3.0 - 2.0 * f);
    return lerp(mushroom_hash11(i), mushroom_hash11(i + 1.0), f);
}

float2 mushroom_hash22(float2 p) {
    float3 p3 = frac(float3(p.xyx) * float3(.1031, .1030, .0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return frac((p3.xx + p3.yz) * p3.zy);
}

void MushroomTower_float(
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
    float4 shaftColor,
    float4 shaftShadowColor,
    float4 shelfColor,
    float4 shelfShadowColor,
    float4 capColor,
    float4 capHighlightColor,
    float4 gillColor,
    float4 pitColor,
    out float4 outColor
) {
    // Center UV horizontally, move base near the bottom
    float2 p = UV - float2(0.5, 0.05);
    
    // Dynamic Anti-Aliasing
    float aa = fwidth(length(p));
    if (aa == 0.0) aa = 0.003;
    
    // ==========================================
    // 1. SHAFT GENERATION
    // ==========================================
    float shaftTop = totalHeight * 0.8;
    // Base cylindrical shaft
    float d_shaft = max(abs(p.x) - shaftWidth * 0.5, max(-p.y, p.y - shaftTop));
    
    // Add surface roughness to the edges
    float rough = (mushroom_noise1D(p.y * 30.0 * featureDensity) - 0.5) * surfaceRoughness * 0.02;
    d_shaft -= rough;
    
    // Pits (darker textured spots on shaft)
    float2 pitP = p * pittingDensity;
    float2 pitId = floor(pitP);
    float2 pitF = frac(pitP);
    float2 pHash = mushroom_hash22(pitId);
    // Randomize pit center inside grid cell
    float2 pitCenter = float2(0.5, 0.5) + (pHash - 0.5) * 0.6;
    float d_pit = length(pitF - pitCenter) - 0.15 * pHash.x;
    bool hasPit = pHash.y > (1.0 - 0.3 * featureDensity);
    float pitMask = hasPit ? smoothstep(aa, -aa, d_pit) : 0.0;
    // Mask pits so they don't leak outside the rough shaft
    float pitInsideShaft = smoothstep(0.0, 0.02, -d_shaft);
    pitMask *= pitInsideShaft;
    
    // ==========================================
    // 2. MUSHROOM SHELVES
    // ==========================================
    float d_shelf = 999.0;
    float d_shelf_dark = 999.0;
    
    [unroll]
    for(int i = 0; i < 10; i++) {
        if(i >= (int)mushroomShelfCount) continue;
        
        // Pseudo-random parameters for each shelf
        float h1 = frac(sin(i * 12.345) * 456.789);
        float h2 = frac(sin(i * 98.765) * 321.654);
        
        // Vertical distribution
        float rangeY = shaftTop - 0.2;
        float baseY = 0.1 + (i + 0.5) * rangeY / max(mushroomShelfCount, 1.0);
        float y = baseY + (h1 - 0.5) * shelfVerticalSpread;
        
        // Side (left or right)
        float side = h2 > 0.5 ? 1.0 : -1.0;
        float x = side * (shaftWidth * 0.5 - 0.01);
        
        // Local coordinate system for shelf
        float2 sp = p - float2(x, y);
        sp.x *= side; // Flip X so shelf always points to +X in local space
        
        // Apply tilt angle
        float sa = sin(shelfAngle);
        float ca = cos(shelfAngle);
        float2 rp = float2(ca * sp.x - sa * sp.y, sa * sp.x + ca * sp.y);
        
        // Half-ellipse shape
        float2 scale = float2(shelfSize, shelfThickness);
        float d = length(rp / scale) - 1.0;
        d *= min(shelfSize, shelfThickness);
        
        // Slice top to make it flat, slice left to attach to shaft
        d = max(d, rp.y); 
        d = max(d, -rp.x);
        
        d_shelf = min(d_shelf, d);
        
        // Shadow on the underside of the shelf
        float shadow = max(d, rp.y + shelfThickness * 0.3);
        d_shelf_dark = min(d_shelf_dark, shadow);
    }
    
    // ==========================================
    // 3. TOP CAP GILLS
    // ==========================================
    float gillWidth = capWidth - capBrimWidth * 2.0;
    float gillHeight = 0.06;
    // Wavy scalloped bottom for gills
    float wave = abs(sin( ((p.x + gillWidth * 0.5) / gillWidth) * gillCount * PI )) * 0.015;
    float d_gills = max(abs(p.x) - gillWidth * 0.5, max(shaftTop - p.y + wave, p.y - (shaftTop + gillHeight)));
    
    // ==========================================
    // 4. TOP MUSHROOM CAP
    // ==========================================
    float capBaseY = shaftTop + gillHeight - 0.01; 
    float2 capP = p - float2(0.0, capBaseY);
    
    // Rounded box top calculation
    float capR = min(capWidth * 0.5, capHeight * 0.6);
    float2 cCorner = float2(capWidth * 0.5 - capR, capHeight - capR);
    float2 qCap = float2(abs(capP.x), capP.y);
    float d_cap;
    if(qCap.x > cCorner.x && qCap.y > cCorner.y) {
        d_cap = length(qCap - cCorner) - capR;
    } else {
        d_cap = max(qCap.x - capWidth * 0.5, qCap.y - capHeight);
    }
    d_cap = max(d_cap, -capP.y); // Flat bottom
    
    // Cap Highlight (Left-aligned stretched ellipse)
    float2 hlP = capP - float2(-capWidth * 0.25, capHeight * 0.65);
    float d_highlight = length(float2(hlP.x / 1.5, hlP.y)) - capHeight * 0.12;
    
    // ==========================================
    // COMPOSITING & BLENDING
    // ==========================================
    float4 c = float4(0.0, 0.0, 0.0, 0.0);
    
    // Layer 1: Shaft
    float shaftAlpha = smoothstep(aa, -aa, d_shaft);
    // Asymmetric right-side shadow
    float shaftShadowMask = smoothstep(shaftWidth * 0.05, shaftWidth * 0.25, p.x);
    float3 shaftFill = lerp(shaftColor.rgb, shaftShadowColor.rgb, shaftShadowMask);
    // Blend pits over shaft
    shaftFill = lerp(shaftFill, pitColor.rgb, pitMask * pitColor.a);
    c = float4(shaftFill, shaftAlpha * shaftColor.a);
    
    // Layer 2: Shelves
    float shelfAlpha = smoothstep(aa, -aa, d_shelf);
    float shelfDarkAlpha = smoothstep(aa, -aa, d_shelf_dark);
    float3 shelfFillRGB = lerp(shelfColor.rgb, shelfShadowColor.rgb, shelfDarkAlpha);
    float outAlpha = shelfAlpha + c.a * (1.0 - shelfAlpha);
    float3 outRGB = (shelfFillRGB * shelfAlpha + c.rgb * c.a * (1.0 - shelfAlpha)) / max(outAlpha, 0.0001);
    c = float4(outRGB, outAlpha);
    
    // Layer 3: Gills
    float gillAlpha = smoothstep(aa, -aa, d_gills);
    // Darken the upper pockets of the gill scallops for a 3D effect
    float gillShadowMask = smoothstep(0.005, 0.015, wave);
    float3 gillFillRGB = lerp(gillColor.rgb, gillColor.rgb * 0.85, gillShadowMask);
    outAlpha = gillAlpha + c.a * (1.0 - gillAlpha);
    outRGB = (gillFillRGB * gillAlpha + c.rgb * c.a * (1.0 - gillAlpha)) / max(outAlpha, 0.0001);
    c = float4(outRGB, outAlpha);
    
    // Layer 4: Top Red Cap
    float capAlpha = smoothstep(aa, -aa, d_cap);
    float highlightAlpha = smoothstep(aa, -aa, d_highlight) * capHighlightColor.a;
    float3 capFillRGB = lerp(capColor.rgb, capHighlightColor.rgb, highlightAlpha);
    outAlpha = capAlpha + c.a * (1.0 - capAlpha);
    outRGB = (capFillRGB * capAlpha + c.rgb * c.a * (1.0 - capAlpha)) / max(outAlpha, 0.0001);
    c = float4(outRGB, outAlpha);
    
    outColor = c;
}
