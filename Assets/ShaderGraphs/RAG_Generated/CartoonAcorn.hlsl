#ifndef PI
#define PI 3.14159265359
#endif

// Helper: Uneven Capsule SDF for the tapered nut body
float acorn_sdUnevenCapsule(float2 p, float r1, float r2, float h) {
    p.x = abs(p.x);
    float b = clamp((r1 - r2) / max(h, 0.0001), -0.999, 0.999);
    float a = sqrt(1.0 - b * b);
    float k = dot(p, float2(-b, a));
    if (k < 0.0) return length(p) - r1;
    if (k > a * h) return length(p - float2(0.0, h)) - r2;
    return dot(p, float2(a, b)) - r1;
}

// Helper: Source-over alpha blending for compositing layers
float4 acorn_opBlend(float4 top, float4 bottom) {
    float a = top.a + bottom.a * (1.0 - top.a);
    float3 rgb = (top.rgb * top.a + bottom.rgb * bottom.a * (1.0 - top.a)) / max(a, 1e-6);
    return float4(rgb, a);
}

void CartoonAcorn_float(
    float2 UV,
    float2 NutSize,
    float2 NutParams,
    float4 NutColor,
    float2 CapSize,
    float2 CapParams,
    float4 CapColor,
    float3 GridParams,
    float4 CapGridColor,
    float4 StemParams,
    float4 StemColor,
    float4 HighlightParams,
    float HighlightAngle,
    float4 HighlightColor,
    float StrokeWidth,
    float4 StrokeColor,
    out float4 outColor
) {
    float2 p = UV - 0.5;
    // Base anti-aliasing width from screen derivatives
    float aa = max(max(fwidth(p.x), fwidth(p.y)) * 1.5, 0.001);
    
    // --------------------------------------------------------
    // 1. STEM SDF
    // --------------------------------------------------------
    float2 pStem = p - float2(0.0, StemParams.w);
    pStem.x -= StemParams.z * pStem.y * pStem.y; // Parabolic bend
    float2 baStem = float2(0.0, StemParams.x);
    float hStem = clamp(dot(pStem, baStem) / max(dot(baStem, baStem), 1e-5), 0.0, 1.0);
    float dStem = length(pStem - baStem * hStem) - StemParams.y;
    
    // --------------------------------------------------------
    // 2. NUT BODY SDF
    // --------------------------------------------------------
    float2 pNut = p - float2(0.0, NutParams.y);
    // Invert Y so the wide base is at the top, pointing downwards
    pNut.y = NutSize.y * 0.5 - pNut.y;
    float topRadius = NutSize.x * 0.5;
    float bottomRadius = topRadius * NutParams.x;
    float dNut = acorn_sdUnevenCapsule(pNut, topRadius, bottomRadius, NutSize.y);
    
    // Glossy Highlight on Nut
    float2 pHi = p - HighlightParams.xy;
    float cA = cos(HighlightAngle);
    float sA = sin(HighlightAngle);
    pHi = float2(cA * pHi.x - sA * pHi.y, sA * pHi.x + cA * pHi.y);
    pHi.y -= clamp(pHi.y, -HighlightParams.z, HighlightParams.z);
    float dHi = length(pHi) - HighlightParams.w;
    
    // --------------------------------------------------------
    // 3. CAP SDF & TEXTURE
    // --------------------------------------------------------
    float2 pCap = p - float2(0.0, CapParams.y);
    pCap.y += CapParams.x * pCap.x * pCap.x; // Bend ends downwards
    float2 pCapSeg = pCap;
    pCapSeg.x = clamp(pCapSeg.x, -CapSize.x, CapSize.x);
    float dCap = length(pCapSeg) - CapSize.y;
    
    // Distance correction to maintain consistent outline width despite domain warping
    float capScale = 1.0 / (1.0 + abs(CapParams.x) * CapSize.x);
    dCap *= capScale;
    float aaCap = aa * capScale;
    float capStrokeWidth = StrokeWidth * capScale;
    
    // Cap Diamond Lattice Grid
    float2 pGrid = p * GridParams.x;
    float cG = cos(GridParams.z);
    float sG = sin(GridParams.z);
    pGrid = float2(cG * pGrid.x - sG * pGrid.y, sG * pGrid.x + cG * pGrid.y);
    float2 gridFrac = frac(pGrid) - 0.5;
    // Distance to the nearest lattice line
    float dGrid = min(abs(gridFrac.x), abs(gridFrac.y)) - GridParams.y * 0.5;
    dGrid /= max(GridParams.x, 0.001); // Scale back to UV space
    
    // --------------------------------------------------------
    // COMPOSITING (Back to Front)
    // --------------------------------------------------------
    
    // --- Layer 1: Stem ---
    float stemFill = 1.0 - smoothstep(0.0, aa, dStem);
    float stemOutline = 1.0 - smoothstep(0.0, aa, dStem - StrokeWidth);
    
    float4 stemLayer = float4(StrokeColor.rgb, StrokeColor.a * stemOutline);
    float stemFillAlpha = StemColor.a * stemFill;
    stemLayer.rgb = lerp(stemLayer.rgb, StemColor.rgb, stemFillAlpha);
    stemLayer.a = stemLayer.a + stemFillAlpha * (1.0 - stemLayer.a);
    
    // --- Layer 2: Nut Body ---
    float nutFill = 1.0 - smoothstep(0.0, aa, dNut);
    float nutOutline = 1.0 - smoothstep(0.0, aa, dNut - StrokeWidth);
    
    float hiFill = 1.0 - smoothstep(0.0, aa, dHi);
    float4 modNutColor = NutColor;
    float hiA = HighlightColor.a * hiFill;
    // Blend highlight onto nut color
    modNutColor.rgb = lerp(modNutColor.rgb, HighlightColor.rgb, hiA);
    modNutColor.a = modNutColor.a + hiA * (1.0 - modNutColor.a);
    
    float4 nutLayer = float4(StrokeColor.rgb, StrokeColor.a * nutOutline);
    float nutFillAlpha = modNutColor.a * nutFill;
    nutLayer.rgb = lerp(nutLayer.rgb, modNutColor.rgb, nutFillAlpha);
    nutLayer.a = nutLayer.a + nutFillAlpha * (1.0 - nutLayer.a);
    
    // --- Layer 3: Cap ---
    float capFill = 1.0 - smoothstep(0.0, aaCap, dCap);
    float capOutline = 1.0 - smoothstep(0.0, aaCap, dCap - capStrokeWidth);
    
    float gridFill = 1.0 - smoothstep(0.0, aa, dGrid);
    float4 modCapColor = CapColor;
    float gridA = CapGridColor.a * gridFill;
    // Blend grid pattern onto cap color
    modCapColor.rgb = lerp(modCapColor.rgb, CapGridColor.rgb, gridA);
    modCapColor.a = modCapColor.a + gridA * (1.0 - modCapColor.a);
    
    float4 capLayer = float4(StrokeColor.rgb, StrokeColor.a * capOutline);
    float capFillAlpha = modCapColor.a * capFill;
    capLayer.rgb = lerp(capLayer.rgb, modCapColor.rgb, capFillAlpha);
    capLayer.a = capLayer.a + capFillAlpha * (1.0 - capLayer.a);
    
    // --- Final Assembly ---
    float4 finalColor = float4(0, 0, 0, 0);
    finalColor = acorn_opBlend(stemLayer, finalColor);
    finalColor = acorn_opBlend(nutLayer, finalColor);
    finalColor = acorn_opBlend(capLayer, finalColor);
    
    outColor = finalColor;
}
