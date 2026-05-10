#ifndef PI
#define PI 3.14159265359
#endif

float2 rotate(float2 p, float a) {
    float c = cos(a);
    float s = sin(a);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

float dot2(float2 v) {
    return dot(v, v);
}

float4 alphaBlend(float4 top, float4 bottom) {
    float outA = top.a + bottom.a * (1.0 - top.a);
    if (outA == 0.0) return float4(0.0, 0.0, 0.0, 0.0);
    float3 outC = (top.rgb * top.a + bottom.rgb * bottom.a * (1.0 - top.a)) / outA;
    return float4(outC, outA);
}

float sdEllipseApprox(float2 p, float2 ab) {
    ab = max(ab, 0.00001);
    float f = length(p / ab) - 1.0;
    float2 grad = p / (ab * ab);
    return f / length(grad);
}

float sdTrapezoid(float2 p, float r1, float r2, float he) {
    float2 k1 = float2(r2, he);
    float2 k2 = float2(r2 - r1, 2.0 * he);
    p.x = abs(p.x);
    float2 ca = float2(p.x - min(p.x, (p.y < 0.0) ? r1 : r2), abs(p.y) - he);
    float2 cb = p - k1 + k2 * clamp(dot(k1 - p, k2) / dot2(k2), 0.0, 1.0);
    float s = (cb.x < 0.0 && ca.y < 0.0) ? -1.0 : 1.0;
    return s * sqrt(min(dot2(ca), dot2(cb)));
}

float sdRoundRect(float2 p, float2 b, float r) {
    float2 d = abs(p) - b + float2(r, r);
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - r;
}

float4 renderArm(
    float2 uv, float2 pos, float rot, float size, float fatness, float curve, 
    float4 baseColor, float4 darkColor, float4 highlightColor, 
    float thornDensity, float4 thornColor, float aa
) {
    float2 p = uv - pos;
    p = rotate(p, -rot);
    float2 pB = p;
    pB.x -= curve * p.y * p.y * sign(p.y);
    
    float dArm = sdEllipseApprox(pB, float2(fatness, size));
    
    float armMask = 1.0 - smoothstep(0.0, aa, dArm);
    if (armMask <= 0.0) return float4(0.0, 0.0, 0.0, 0.0);
    
    float3 col = baseColor.rgb;
    
    // Highlight on left side
    float hlMask = 1.0 - smoothstep(-fatness * 0.4, -fatness * 0.1, pB.x);
    col = lerp(col, highlightColor.rgb, hlMask);
    
    // Vertical Grooves (Dark Green)
    float lineMask = smoothstep(0.9, 0.95, cos(pB.x * 12.0 / fatness));
    lineMask *= smoothstep(0.8, 0.5, abs(pB.x) / fatness); // Fade near edges
    col = lerp(col, darkColor.rgb, lineMask * 0.6);
    
    // Scattered Thorns
    float thornAlpha = 0.0;
    if (thornDensity > 0.0) {
        float2 grid = pB * thornDensity;
        float2 id = floor(grid);
        float2 f = frac(grid) - 0.5;
        float h = frac(sin(dot(id, float2(12.9898, 78.233))) * 43758.5453);
        if (h > 0.5) {
            float2 off = float2((frac(h * 34.0) - 0.5) * 0.7, (frac(h * 12.0) - 0.5) * 0.7);
            float2 tp = f - off;
            tp = rotate(tp, (h - 0.5) * 1.5);
            float dt = length(tp - float2(0.0, clamp(tp.y, -0.15, 0.15))) - 0.05;
            thornAlpha = 1.0 - smoothstep(0.0, 0.03, dt);
        }
    }
    col = lerp(col, thornColor.rgb, thornAlpha);
    
    return float4(col, armMask);
}

float4 renderPot(
    float2 uv, float2 pos, float scale, float width, float height, float botScale,
    float4 potCol, float4 lipCol, float4 hlCol, float aa
) {
    float2 p = uv - pos;
    p /= max(scale, 0.001);
    
    float he = height * 0.5;
    float r2 = width * 0.5;
    float r1 = r2 * botScale;
    
    // Body
    float dBody = sdTrapezoid(p, r1, r2, he);
    
    // Lip
    float lipH = height * 0.15;
    float lipW = r2 * 1.15;
    float2 pLip = p - float2(0.0, he + lipH * 0.5);
    float dLip = sdRoundRect(pLip, float2(lipW, lipH * 0.5), lipH * 0.2);
    
    float bodyMask = 1.0 - smoothstep(0.0, aa / scale, dBody);
    float lipMask = 1.0 - smoothstep(0.0, aa / scale, dLip);
    
    float fullMask = max(bodyMask, lipMask);
    if (fullMask <= 0.0) return float4(0.0, 0.0, 0.0, 0.0);
    
    float3 col = potCol.rgb;
    
    // Body Highlight
    float bodyHlMask = smoothstep(r2 * 0.4, r2 * 0.6, p.x + p.y * 0.2);
    col = lerp(col, hlCol.rgb, bodyHlMask);
    
    // Lip Shadow on Body
    float shadowMask = smoothstep(he - lipH * 1.5, he, p.y) * bodyMask;
    col = lerp(col, potCol.rgb * 0.7, shadowMask * 0.8);
    
    // Lip Highlight & Color
    float lipHlMask = smoothstep(lipW * 0.4, lipW * 0.6, pLip.x);
    float3 finalLipCol = lerp(lipCol.rgb, hlCol.rgb, lipHlMask);
    col = lerp(col, finalLipCol, lipMask);
    
    return float4(col, fullMask);
}

float2 getFlowerPos(float2 pos, float rot, float size, float curve) {
    float localX = curve * size * size;
    float localY = size * 0.85;
    return pos + rotate(float2(localX, localY), rot);
}

float4 renderFlower(
    float2 uv, float2 pos, float size, float petals, float centerSize,
    float4 petalCol, float4 centerCol, float rot, float aa
) {
    float2 p = uv - pos;
    p = rotate(p, -rot);
    p /= max(size, 0.001);
    
    float r = length(p);
    float a = atan2(p.y, p.x);
    
    float wave = cos(a * petals);
    float shape = 0.5 + 0.5 * pow(max(0.0, wave), 0.5);
    float petalDist = r - shape;
    float centerDist = r - centerSize;
    
    float localAA = max(aa / size, 0.001);
    float petalMask = 1.0 - smoothstep(0.0, localAA, petalDist);
    float centerMask = 1.0 - smoothstep(0.0, localAA, centerDist);
    
    float fullMask = max(petalMask, centerMask);
    if (fullMask <= 0.0) return float4(0.0, 0.0, 0.0, 0.0);
    
    float3 col = petalCol.rgb;
    col = lerp(col, centerCol.rgb, centerMask);
    
    return float4(col, fullMask);
}

void PottedCactus_float(
    float2 UV,
    float2 PotPos, float PotSize, float PotWidth, float PotHeight, float PotBottomScale,
    float4 PotColor, float4 PotLipColor, float4 PotHighlightColor,
    float4 CactusColor, float4 CactusDarkColor, float4 CactusHighlightColor,
    float ThornDensity, float4 ThornColor,
    float2 ArmCPos, float ArmCRot, float ArmCSize, float ArmCFatness, float ArmCCurve,
    float2 ArmLPos, float ArmLRot, float ArmLSize, float ArmLFatness, float ArmLCurve,
    float2 ArmRPos, float ArmRRot, float ArmRSize, float ArmRFatness, float ArmRCurve,
    float FlowerSize, float FlowerPetals, float FlowerCenterSize,
    float4 FlowerPetalColor, float4 FlowerCenterColor,
    out float4 outColor
) {
    float aa = max(fwidth(UV.x), 0.001) * 1.5;
    float4 finalColor = float4(0.0, 0.0, 0.0, 0.0);
    
    // 1. Left Arm
    float4 colArmL = renderArm(UV, ArmLPos, ArmLRot, ArmLSize, ArmLFatness, ArmLCurve, CactusColor, CactusDarkColor, CactusHighlightColor, ThornDensity, ThornColor, aa);
    finalColor = alphaBlend(colArmL, finalColor);
    
    // 2. Right Arm
    float4 colArmR = renderArm(UV, ArmRPos, ArmRRot, ArmRSize, ArmRFatness, ArmRCurve, CactusColor, CactusDarkColor, CactusHighlightColor, ThornDensity, ThornColor, aa);
    finalColor = alphaBlend(colArmR, finalColor);
    
    // 3. Center Arm (Overlaps side arms)
    float4 colArmC = renderArm(UV, ArmCPos, ArmCRot, ArmCSize, ArmCFatness, ArmCCurve, CactusColor, CactusDarkColor, CactusHighlightColor, ThornDensity, ThornColor, aa);
    finalColor = alphaBlend(colArmC, finalColor);
    
    // 4. Pot (Overlaps cactus bases)
    float4 colPot = renderPot(UV, PotPos, PotSize, PotWidth, PotHeight, PotBottomScale, PotColor, PotLipColor, PotHighlightColor, aa);
    finalColor = alphaBlend(colPot, finalColor);
    
    // 5. Flowers (Top-most layer)
    float2 fpL = getFlowerPos(ArmLPos, ArmLRot, ArmLSize, ArmLCurve);
    float4 colFlowerL = renderFlower(UV, fpL, FlowerSize, FlowerPetals, FlowerCenterSize, FlowerPetalColor, FlowerCenterColor, ArmLRot, aa);
    finalColor = alphaBlend(colFlowerL, finalColor);
    
    float2 fpR = getFlowerPos(ArmRPos, ArmRRot, ArmRSize, ArmRCurve);
    float4 colFlowerR = renderFlower(UV, fpR, FlowerSize, FlowerPetals, FlowerCenterSize, FlowerPetalColor, FlowerCenterColor, ArmRRot, aa);
    finalColor = alphaBlend(colFlowerR, finalColor);
    
    float2 fpC = getFlowerPos(ArmCPos, ArmCRot, ArmCSize, ArmCCurve);
    float4 colFlowerC = renderFlower(UV, fpC, FlowerSize, FlowerPetals, FlowerCenterSize, FlowerPetalColor, FlowerCenterColor, ArmCRot, aa);
    finalColor = alphaBlend(colFlowerC, finalColor);
    
    outColor = finalColor;
}
