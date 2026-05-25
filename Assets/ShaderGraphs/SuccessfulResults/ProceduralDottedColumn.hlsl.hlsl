#ifndef PI
#define PI 3.14159265359
#endif

// --- Helper Functions ---

// Basic 2D distance functions
float sdBox(float2 p, float2 b) {
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

float sdCircle(float2 p, float r) {
    return length(p) - r;
}

// Pseudo-random functions for dot distribution
float random21(float2 p) {
    return frac(sin(dot(p, float2(12.9898, 78.233))) * 43758.5453);
}

float2 random22(float2 p) {
    p = float2(dot(p, float2(127.1, 311.7)), dot(p, float2(269.5, 183.3)));
    return -1.0 + 2.0 * frac(sin(p) * 43758.5453123);
}

// Dot pattern generator (Grid, Hex, Scattered)
float sdDots(float2 p, float density, float uniformity, float arrangement, float size) {
    float2 uv = p * max(density, 0.001);
    float styleIdx = round(arrangement);
    
    // Hexagonal shift
    if (styleIdx == 1.0) {
        uv.x += frac(floor(uv.y) * 0.5);
    }
    
    float2 id = floor(uv);
    float2 f = frac(uv) - 0.5;
    
    float minDist = 100.0;
    
    // 3x3 search to handle edge cases and jitter perfectly
    for(int y = -1; y <= 1; y++) {
        for(int x = -1; x <= 1; x++) {
            float2 neighbor = float2((float)x, (float)y);
            float2 cellId = id + neighbor;
            
            float2 offset = float2(0.0, 0.0);
            // Jitter for scattered or non-uniform grids
            if (styleIdx == 2.0 || uniformity < 1.0) {
                float2 pt = random22(cellId);
                offset = pt * (1.0 - clamp(uniformity, 0.0, 1.0)) * 0.5;
            }
            
            float2 diff = neighbor + offset - f;
            float dist = length(diff) - size;
            minDist = min(minDist, dist);
        }
    }
    
    return minDist / max(density, 0.001);
}

// Body SDF with styleable bottom
float getBodySDF(float2 p, float2 c, float2 s, float style) {
    float styleIdx = round(style);
    float dFlat = sdBox(p - c, s);
    if (styleIdx == 0.0 || styleIdx == 3.0) return dFlat;
    
    if (styleIdx == 1.0) { // Rounded
        float r = min(s.x * 0.2, s.y);
        return sdBox(p - c, max(s - r, 0.0)) - r;
    }
    
    if (styleIdx == 2.0) { // Beveled / Chamfered
        float cBevel = s.x * 0.2;
        float2 d = abs(p - c) - s;
        float dBox = length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
        float chamfer = (abs(p.x - c.x) + abs(p.y - c.y) - (s.x + s.y - cBevel)) * 0.70710678;
        return max(dBox, chamfer);
    }
    
    return dFlat;
}

// Cap SDF with styleable top (Flat, Rounded, Beveled, Scalloped)
float getCapSDF(float2 p, float2 c, float2 s, float style) {
    float styleIdx = round(style);
    float dFlat = sdBox(p - c, s);
    if (styleIdx == 0.0) return dFlat;
    
    if (styleIdx == 1.0) { // Rounded
        float r = s.y;
        return sdBox(p - c, max(s - r, 0.0)) - r;
    }
    
    if (styleIdx == 2.0) { // Beveled / Chamfered
        float cBevel = s.y * 0.5;
        float2 d = abs(p - c) - s;
        float dBox = length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
        float chamfer = (abs(p.x - c.x) + abs(p.y - c.y) - (s.x + s.y - cBevel)) * 0.70710678;
        return max(dBox, chamfer);
    }
    
    // 3.0: Scalloped (default image reference)
    float wCap = s.x * 2.0;
    float rBump = wCap / 10.0 * 1.2;
    
    // Shorten base to accommodate bumps inside total bounds
    float2 sBase = float2(s.x, max(s.y - rBump * 0.5, 0.0));
    float2 cBase = float2(c.x, c.y - rBump * 0.5);
    float dBase = sdBox(p - cBase, sBase);
    
    float dBumps = 100.0;
    float bumpSpacing = wCap / 5.0;
    for(int i = 0; i < 5; i++) {
        float bx = -wCap * 0.5 + bumpSpacing * (float(i) + 0.5);
        float by = cBase.y + sBase.y; 
        float d = sdCircle(p - float2(bx, by), rBump);
        dBumps = min(dBumps, d);
    }
    
    return min(dBase, dBumps);
}

// Alpha Compositing
float4 compositeOver(float4 src, float4 dst) {
    float a = src.a + dst.a * (1.0 - src.a);
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-6);
    return float4(c, a);
}

// --- Main Shader Function ---
void ProceduralDottedColumn_float(
    float2 UV,
    float totalHeight,
    float totalWidth,
    float dotSize,
    float featureDensity,
    float dotSpacingUniformity,
    float dotArrangement,
    float dotColorOffset,
    float dotBorderThickness,
    float4 baseColor,
    float4 dotColor,
    float surfaceSheen,
    float topCapStyle,
    out float4 outColor
) {
    float2 p = UV - 0.5;
    float aa = 0.003; // Anti-aliasing width
    
    // Base dimensions
    float h = totalHeight;
    float y_bottom = -h * 0.5;
    float y_top = h * 0.5;
    
    // Component Heights
    float thTopCap = h * 0.08;
    float thRim = h * 0.06;
    float thBand = h * 0.03;
    
    // Y boundaries
    float y_capTop = y_top;
    float y_capBottom = y_capTop - thTopCap;
    float y_rimBottom = y_capBottom - thRim;
    float y_bandBottom = y_rimBottom - thBand;
    float y_bodyTop = y_bandBottom;
    float y_bodyBottom = y_bottom;
    
    // Widths
    float wBody = totalWidth;
    float wBand = totalWidth;
    float wRim = totalWidth * 1.15;
    float wCap = totalWidth * 1.3;
    
    // Centers and Half-extents (sizes)
    float2 cBody = float2(0.0, (y_bodyTop + y_bodyBottom) * 0.5);
    float2 sBody = float2(wBody * 0.5, max((y_bodyTop - y_bodyBottom) * 0.5, 0.0));
    
    float2 cBand = float2(0.0, (y_rimBottom + y_bandBottom) * 0.5);
    float2 sBand = float2(wBand * 0.5, max((y_rimBottom - y_bandBottom) * 0.5, 0.0));
    
    float2 cRim = float2(0.0, (y_capBottom + y_rimBottom) * 0.5);
    float2 sRim = float2(wRim * 0.5, max((y_capBottom - y_rimBottom) * 0.5, 0.0));
    
    float2 cCap = float2(0.0, (y_capTop + y_capBottom) * 0.5);
    float2 sCap = float2(wCap * 0.5, max((y_capTop - y_capBottom) * 0.5, 0.0));
    
    // Extend lower layers slightly upwards to prevent 1-pixel AA gaps
    float overlap = 0.02;
    float2 sBodyExt = sBody; sBodyExt.y += overlap;
    float2 cBodyExt = cBody; cBodyExt.y += overlap;
    float2 sBandExt = sBand; sBandExt.y += overlap;
    float2 cBandExt = cBand; cBandExt.y += overlap;
    float2 sRimExt = sRim; sRimExt.y += overlap;
    float2 cRimExt = cRim; cRimExt.y += overlap;
    
    // Canvas Background
    float4 finalColor = float4(0.0, 0.0, 0.0, 0.0);
    
    // --- 1. Draw Body & Dots ---
    float dBody = getBodySDF(p, cBodyExt, sBodyExt, topCapStyle);
    float alphaBody = smoothstep(aa, -aa, dBody);
    
    float dDots = sdDots(p, featureDensity, dotSpacingUniformity, dotArrangement, dotSize);
    float alphaDotShape = smoothstep(aa, -aa, dDots);
    
    float alphaDotOutline = 0.0;
    if (dotBorderThickness > 0.001) {
        float inner = dDots + dotBorderThickness;
        float outer = dDots;
        alphaDotOutline = smoothstep(aa, -aa, outer) - smoothstep(aa, -aa, inner);
    }
    
    float4 cDotsFinal = dotColor;
    cDotsFinal.rgb = clamp(cDotsFinal.rgb + dotColorOffset, 0.0, 1.0);
    
    float4 bodyLayer = baseColor;
    // Apply base dots
    bodyLayer.rgb = lerp(bodyLayer.rgb, cDotsFinal.rgb, alphaDotShape);
    // Apply dot outline if any
    if (dotBorderThickness > 0.001) {
        float4 borderColor = float4(cDotsFinal.rgb * 0.5, 1.0);
        bodyLayer.rgb = lerp(bodyLayer.rgb, borderColor.rgb, alphaDotOutline);
    }
    
    finalColor = compositeOver(float4(bodyLayer.rgb, alphaBody), finalColor);
    
    // --- 2. Draw Thin Band ---
    float dBand = sdBox(p - cBandExt, sBandExt);
    float alphaBand = smoothstep(aa, -aa, dBand);
    float4 bandColor = dotColor; // Thin band matches dot color organically
    finalColor = compositeOver(float4(bandColor.rgb, alphaBand), finalColor);
    
    // --- 3. Draw Rim ---
    float dRim = sdBox(p - cRimExt, sRimExt);
    float alphaRim = smoothstep(aa, -aa, dRim);
    float4 rimColor = float4(0.412, 0.412, 0.412, 1.0); // Hardcoded dark grey rim based on reference
    finalColor = compositeOver(float4(rimColor.rgb, alphaRim), finalColor);
    
    // --- 4. Draw Top Cap ---
    float dCap = getCapSDF(p, cCap, sCap, topCapStyle);
    float alphaCap = smoothstep(aa, -aa, dCap);
    float4 capColor = baseColor;
    finalColor = compositeOver(float4(capColor.rgb, alphaCap), finalColor);
    
    // --- 5. Global Surface Sheen ---
    if (surfaceSheen > 0.0) {
        float xNorm = p.x / max(wBody * 0.5, 0.001);
        // Creates a soft cylindrical highlight stripe
        float hGlow = smoothstep(-0.5, -0.1, xNorm) * smoothstep(0.5, -0.1, xNorm);
        finalColor.rgb += hGlow * surfaceSheen * 0.4 * finalColor.a;
    }
    
    outColor = finalColor;
}

// ------------------------------------------------------------------------
//  Visual Result (High-level, parameter-invariant description)
// ------------------------------------------------------------------------
//  This function produces a **2D cylindrical column** with decorative patterns. The column features a smooth, vertical body covered in circular polka dots arranged across its curved surface. These dots provide a playful, graphic contrast against the vibrant base, varying slightly in color. The top of the column includes a distinct, rounded cap with a scalloped edge, giving it a decorative finish, while a thin band separates the cap from the main body. A subtle sheen runs vertically, suggesting a glossy surface texture. The overall appearance is geometric and stylized with a uniform distribution of visual elements.
// ------------------------------------------------------------------------
