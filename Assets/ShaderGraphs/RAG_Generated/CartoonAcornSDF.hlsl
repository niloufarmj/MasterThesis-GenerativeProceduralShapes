#ifndef PI
#define PI 3.14159265359
#endif

// Helper: Smooth Union
float opSmoothUnion(float d1, float d2, float k) {
    float h = clamp(0.5 + 0.5 * (d2 - d1) / max(k, 0.0001), 0.0, 1.0);
    return lerp(d2, d1, h) - k * h * (1.0 - h);
}

// Helper: Straight-alpha composite (Source Over Destination)
float4 alphaBlend(float4 src, float4 dst) {
    float outA = src.a + dst.a * (1.0 - src.a);
    float3 outRGB = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(outA, 1e-8);
    return float4(outRGB, outA);
}

void CartoonAcorn_float(
    float2 UV,
    float Size,
    float OutlineWidth,
    float4 OutlineColor,
    float NutWidth,
    float NutHeight,
    float NutSmoothness,
    float4 NutColor,
    float CapWidth,
    float CapHeight,
    float CapCornerRadius,
    float CapBend,
    float CapOffsetY,
    float4 CapColor,
    float GridDensity,
    float GridThickness,
    float GridAngle,
    float CapTextureOpacity,
    float StemLength,
    float StemThickness,
    float StemAngle,
    float4 StemColor,
    float2 HighlightOffset,
    float2 HighlightSize,
    float HighlightAngle,
    float HighlightRadius,
    float4 HighlightColor,
    out float4 outColor
) {
    // 1. Setup coordinates
    float2 p = UV - 0.5;
    p /= max(Size, 0.001);
    
    float aa = fwidth(p.x);
    aa = max(aa, 0.0001);

    // 2. Nut SDF (Smooth teardrop/oval base)
    float dTop = length(p - float2(0.0, 0.0)) - NutWidth;
    float dBot = length(p - float2(0.0, -NutHeight)) - NutWidth * 0.1;
    float dNut = opSmoothUnion(dBot, dTop, max(NutSmoothness, 0.001));

    // 3. Cap SDF (Bent rounded dome)
    float2 pCap = p - float2(0.0, CapOffsetY);
    // Parabolic domain bend to wrap the cap downward over the nut
    pCap.y += CapBend * pCap.x * pCap.x;
    
    float capR = clamp(CapCornerRadius, 0.0, min(CapWidth, CapHeight));
    float2 qCap = abs(pCap) - float2(CapWidth, CapHeight) + capR;
    float dCap = length(max(qCap, 0.0)) + min(max(qCap.x, qCap.y), 0.0) - capR;

    // 4. Stem SDF
    float2 pStem = p - float2(0.0, CapOffsetY + CapHeight - 0.05);
    float sA = -StemAngle;
    float cS = cos(sA), sS = sin(sA);
    pStem = float2(cS * pStem.x - sS * pStem.y, sS * pStem.x + cS * pStem.y);
    
    float2 pA = float2(0.0, 0.0);
    float2 pB = float2(0.0, StemLength);
    float2 pAtoB = pStem - pA;
    float2 bAtoB = pB - pA;
    float hS = clamp(dot(pAtoB, bAtoB) / max(dot(bAtoB, bAtoB), 0.0001), 0.0, 1.0);
    float dStem = length(pAtoB - bAtoB * hS) - StemThickness;

    // 5. Highlight SDF (Glossy reflection)
    float2 pHigh = p - HighlightOffset;
    float hA = -HighlightAngle;
    float cH = cos(hA), sH = sin(hA);
    pHigh = float2(cH * pHigh.x - sH * pHigh.y, sH * pHigh.x + cH * pHigh.y);
    
    float highR = clamp(HighlightRadius, 0.0, min(HighlightSize.x, HighlightSize.y));
    float2 qHigh = abs(pHigh) - HighlightSize + highR;
    float dHighlight = length(max(qHigh, 0.0)) + min(max(qHigh.x, qHigh.y), 0.0) - highR;

    // 6. Cap Texture (Diagonal Crisscross Lattice)
    float2 pGrid = pCap * GridDensity;
    float gA = -GridAngle;
    float cG = cos(gA), sG = sin(gA);
    pGrid = float2(cG * pGrid.x - sG * pGrid.y, sG * pGrid.x + cG * pGrid.y);
    
    float2 gridFrac = abs(frac(pGrid) - 0.5);
    float dGridLine = min(0.5 - gridFrac.x, 0.5 - gridFrac.y);
    float gridAA = fwidth(pGrid.x);
    gridAA = max(gridAA, 0.001);
    float mTexture = smoothstep(GridThickness * 0.5 + gridAA, GridThickness * 0.5 - gridAA, dGridLine);
    
    float3 capFillColor = lerp(CapColor.rgb, CapColor.rgb * 0.4, mTexture * CapTextureOpacity);

    // 7. Shape Masks (Fill and Outlines)
    float mStemFill = 1.0 - smoothstep(-aa, aa, dStem);
    float mStemOut  = 1.0 - smoothstep(-aa, aa, dStem - OutlineWidth);
    
    float mNutFill = 1.0 - smoothstep(-aa, aa, dNut);
    float mNutOut  = 1.0 - smoothstep(-aa, aa, dNut - OutlineWidth);
    
    float mCapFill = 1.0 - smoothstep(-aa, aa, dCap);
    float mCapOut  = 1.0 - smoothstep(-aa, aa, dCap - OutlineWidth);
    
    float mHighFill = 1.0 - smoothstep(-aa, aa, dHighlight);
    mHighFill *= mNutFill; // Clip highlight strictly to the inside of the nut body

    // 8. Layer Processing
    float stemA = lerp(OutlineColor.a, StemColor.a, mStemFill) * mStemOut;
    float4 stemLayer = float4(lerp(OutlineColor.rgb, StemColor.rgb, mStemFill), stemA);

    float nutA = lerp(OutlineColor.a, NutColor.a, mNutFill) * mNutOut;
    float4 nutLayer = float4(lerp(OutlineColor.rgb, NutColor.rgb, mNutFill), nutA);

    float4 highLayer = float4(HighlightColor.rgb, mHighFill * HighlightColor.a);

    float capA = lerp(OutlineColor.a, CapColor.a, mCapFill) * mCapOut;
    float4 capLayer = float4(lerp(OutlineColor.rgb, capFillColor, mCapFill), capA);

    // 9. Back-to-Front Compositing
    float4 res = float4(0.0, 0.0, 0.0, 0.0);
    res = alphaBlend(stemLayer, res); // Stem (back)
    res = alphaBlend(nutLayer, res);  // Nut
    res = alphaBlend(highLayer, res); // Highlight (over nut)
    res = alphaBlend(capLayer, res);  // Cap (front)

    outColor = res;
}
