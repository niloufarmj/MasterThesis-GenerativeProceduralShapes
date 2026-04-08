#ifndef PI
#define PI 3.14159265359
#endif

// --- Helper Functions ---

// Straight-alpha blending (Source Over Destination)
float4 cactus_over(float4 src, float4 dst) {
    float a = src.a + dst.a * (1.0 - src.a);
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-8);
    return float4(c, a);
}

// Smooth minimum for organic branching
float cactus_smin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / max(k, 1e-5), 0.0, 1.0);
    return lerp(b, a, h) - k * h * (1.0 - h);
}

// Gradient-based Ellipse SDF (efficient and accurate for squashed shapes)
float cactus_sdEllipse(float2 p, float2 ab) {
    ab = max(ab, 1e-5);
    float f = length(p / ab) - 1.0;
    float2 grad = p / (ab * ab);
    return f / max(length(grad), 1e-8);
}

// Heart SDF for flowers
float cactus_sdHeart(float2 p) {
    p.x = abs(p.x);
    if (p.y + p.x > 1.0)
        return sqrt(dot(p - float2(0.25, 0.75), p - float2(0.25, 0.75))) - 0.35355339;
    return sqrt(min(dot(p - float2(0.00, 1.00), p - float2(0.00, 1.00)),
                    dot(p - 0.5 * max(p.x + p.y, 0.0), p - 0.5 * max(p.x + p.y, 0.0)))) * sign(p.x - p.y);
}

// Trapezoid Pot SDF
float cactus_sdPot(float2 p, float topW, float botW, float h) {
    p.x = abs(p.x);
    float2 a = float2(botW, 0.0);
    float2 b = float2(topW, h);
    
    float2 pa = p - a;
    float2 ba = b - a;
    float t = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-5), 0.0, 1.0);
    float dSeg = length(pa - ba * t);
    
    float2 n = normalize(float2(ba.y, -ba.x));
    float dSide = dot(pa, n);
    float dY = max(-p.y, p.y - h);
    
    float d = max(dSide, dY);
    if (d > 0.0) {
        float dTop = length(float2(max(p.x - topW, 0.0), p.y - h));
        float dBot = length(float2(max(p.x - botW, 0.0), p.y));
        if (p.y > h) return min(dTop, dSeg);
        if (p.y < 0.0) return min(dBot, dSeg);
        return dSeg;
    }
    return d;
}

// Saguaro Arm SDF
float cactus_sdArm(float2 p, float side, float w, float h, float k, float thickBase, float thickTip, out float dSkeleton) {
    float sideSign = side >= 0.0 ? 1.0 : -1.0;
    p.x *= sideSign;
    
    float2 p0 = float2(0.0, 0.0);
    float2 p1 = float2(w, 0.0);
    float2 p2 = float2(w, h);
    
    float2 pa = p - p0;
    float2 ba = p1 - p0;
    float h1 = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-5), 0.0, 1.0);
    float d1 = length(pa - ba * h1);
    
    float2 pb = p - p1;
    float2 cb = p2 - p1;
    float h2 = clamp(dot(pb, cb) / max(dot(cb, cb), 1e-5), 0.0, 1.0);
    float d2 = length(pb - cb * h2);
    
    float smoothK = max(k, 1e-4);
    float hs = clamp(0.5 + 0.5 * (d2 - d1) / smoothK, 0.0, 1.0);
    dSkeleton = lerp(d2, d1, hs) - smoothK * hs * (1.0 - hs);
    
    float t = clamp((p.x + max(0.0, p.y)) / max(w + h, 1e-5), 0.0, 1.0);
    float thickness = lerp(thickBase, thickTip, t);
    
    return dSkeleton - thickness;
}

// Full Cactus SDF
void getCactusSDF(float2 p, float trunkH, float trunkW, float branchCount, 
                  float4 b1, float4 b2, float4 b3, float3 bY, float2 bThick,
                  out float dCactus, out float dSkelSum) {
    
    float trunkSkel = length(float2(p.x, p.y - clamp(p.y, 0.0, trunkH)));
    float dTrunk = trunkSkel - trunkW;
    
    dCactus = dTrunk;
    float minSkel = trunkSkel;
    float dSkel;
    
    if (branchCount > 0.5) {
        float dArm1 = cactus_sdArm(p - float2(0.0, bY.x), b1.x, b1.y, b1.z, b1.w, bThick.x, bThick.y, dSkel);
        dCactus = cactus_smin(dCactus, dArm1, trunkW * 0.5);
        minSkel = min(minSkel, dSkel);
    }
    if (branchCount > 1.5) {
        float dArm2 = cactus_sdArm(p - float2(0.0, bY.y), b2.x, b2.y, b2.z, b2.w, bThick.x, bThick.y, dSkel);
        dCactus = cactus_smin(dCactus, dArm2, trunkW * 0.5);
        minSkel = min(minSkel, dSkel);
    }
    if (branchCount > 2.5) {
        float dArm3 = cactus_sdArm(p - float2(0.0, bY.z), b3.x, b3.y, b3.z, b3.w, bThick.x, bThick.y, dSkel);
        dCactus = cactus_smin(dCactus, dArm3, trunkW * 0.5);
        minSkel = min(minSkel, dSkel);
    }
    
    dSkelSum = minSkel;
}

// Hash for procedural scattering
float2 cactus_hash(float2 p, float seed) {
    float3 p3 = frac(float3(p.xyx) * float3(0.1031, 0.1030, 0.0973) + seed * 0.123);
    p3 += dot(p3, p3.yzx + 33.33);
    return frac((p3.xx + p3.yz) * p3.zy);
}

// Rotate 2D vector
float2 cactus_rotate(float2 p, float angle) {
    float c = cos(angle);
    float s = sin(angle);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

// --- Main Shader Function ---
void CartoonPottedCactusShape_float(
    float2 UV,
    float CactusWidth,
    float CactusHeight,
    float BranchCount,
    float4 Arm1Params,
    float4 Arm2Params,
    float4 Arm3Params,
    float3 ArmYPos,
    float2 ArmThickness,
    float4 CactusColor,
    float4 CactusDarkColor,
    float ShadingDepth,
    float RidgeSpacing,
    float RidgeDepth,
    float FlowerDensity,
    float FlowerSize,
    float FlowerSeed,
    float4 FlowerColor,
    float PotHeight,
    float PotTopWidth,
    float PotBottomWidth,
    float4 PotColor,
    float SoilDepth,
    float4 SoilColor,
    float ShadowSpread,
    float ShadowOpacity,
    float StrokeThickness,
    float4 StrokeColor,
    out float4 outColor
) {
    // 1. Coordinate Setup (Scale to -1..1)
    float2 p = (UV - 0.5) * 2.0;
    float aa = fwidth(p.x);
    aa = max(aa, 0.001);
    
    float2 potBase = float2(0.0, -0.6);
    float2 cactusStart = float2(0.0, potBase.y + PotHeight - 0.1); // Buried slightly to be masked by pot

    // 2. SDF: Ground Shadow
    float dShadow = cactus_sdEllipse(p - potBase, float2(ShadowSpread, 0.05));
    float alphaShadow = 1.0 - smoothstep(0.0, aa, dShadow);
    float4 layerShadow = float4(0.0, 0.0, 0.0, ShadowOpacity * alphaShadow);

    // 3. SDF: Main Cactus Base
    float dCactus, dCactusSkel;
    getCactusSDF(p - cactusStart, CactusHeight, CactusWidth, BranchCount, 
                 Arm1Params, Arm2Params, Arm3Params, ArmYPos, ArmThickness, 
                 dCactus, dCactusSkel);
                 
    float alphaCactus = 1.0 - smoothstep(0.0, aa, dCactus);
    float strokeCactusMask = 1.0 - smoothstep(0.0, aa, abs(dCactus) - StrokeThickness * 0.5);
    
    // Ridge Texturing & 3D Shading
    float3 cactusFillRgb = lerp(CactusDarkColor.rgb, CactusColor.rgb, smoothstep(-StrokeThickness, -ShadingDepth, dCactus));
    float ridgeVal = abs(cos(dCactusSkel * RidgeSpacing));
    float groove = smoothstep(0.8, 1.0, ridgeVal);
    cactusFillRgb *= lerp(1.0, 1.0 - RidgeDepth, groove);
    
    float4 layerCactusFill = float4(cactusFillRgb, alphaCactus * CactusColor.a);
    float4 layerCactusStroke = float4(StrokeColor.rgb, StrokeColor.a * strokeCactusMask);
    float4 layerCactus = cactus_over(layerCactusStroke, layerCactusFill);

    // 4. SDF: Flowers (Scattered Hearts)
    float dFlowers = 999.0;
    if (FlowerDensity > 0.0 && alphaCactus > 0.0) {
        float2 flowerGrid = (p - cactusStart) * FlowerDensity;
        float2 cellId = floor(flowerGrid);
        float2 localP = frac(flowerGrid) - 0.5;
        
        for(int y = -1; y <= 1; y++) {
            for(int x = -1; x <= 1; x++) {
                float2 offset = float2(x, y);
                float2 nCellId = cellId + offset;
                float2 nRand = cactus_hash(nCellId, FlowerSeed) - 0.5;
                float2 nCenter = (nCellId + 0.5 + nRand * 0.5) / FlowerDensity;
                
                float nCactusD, nSkel;
                getCactusSDF(nCenter, CactusHeight, CactusWidth, BranchCount, 
                             Arm1Params, Arm2Params, Arm3Params, ArmYPos, ArmThickness, 
                             nCactusD, nSkel);
                
                float nValid = step(nCactusD, -0.05);
                if (nValid > 0.0) {
                    float nSize = FlowerSize * (0.6 + 0.4 * cactus_hash(nCellId, FlowerSeed + 1.0).x);
                    float2 nLocalP = localP - offset - nRand * 0.5;
                    nLocalP.y += nSize * 0.5; // Visually center the heart
                    
                    float rotAngle = (cactus_hash(nCellId, FlowerSeed + 2.0).y - 0.5) * 1.5;
                    float2 rLocalP = cactus_rotate(nLocalP, rotAngle);
                    
                    float dH = cactus_sdHeart(rLocalP / max(nSize, 1e-5)) * nSize;
                    dFlowers = min(dFlowers, dH);
                }
            }
        }
    }
    float alphaFlower = 1.0 - smoothstep(0.0, aa, dFlowers);
    float strokeFlowerMask = 1.0 - smoothstep(0.0, aa, abs(dFlowers) - max(StrokeThickness * 0.6, 0.005));
    
    float4 layerFlowerFill = float4(FlowerColor.rgb, alphaFlower * FlowerColor.a);
    float4 layerFlowerStroke = float4(StrokeColor.rgb, StrokeColor.a * strokeFlowerMask);
    float4 layerFlower = cactus_over(layerFlowerStroke, layerFlowerFill);
    
    float4 layerCactusGroup = cactus_over(layerFlower, layerCactus);

    // 5. SDF: Pot & Soil
    float2 potLocal = p - potBase;
    float dPot = cactus_sdPot(potLocal, PotTopWidth, PotBottomWidth, PotHeight);
    
    float alphaPot = 1.0 - smoothstep(0.0, aa, dPot);
    float strokePotMask = 1.0 - smoothstep(0.0, aa, abs(dPot) - StrokeThickness * 0.5);
    
    // Soil band across the top of the pot
    float isSoil = smoothstep(PotHeight - SoilDepth - 0.01, PotHeight - SoilDepth + 0.01, potLocal.y);
    float3 potFillRgb = lerp(PotColor.rgb, SoilColor.rgb, isSoil);
    
    float4 layerPotFill = float4(potFillRgb, alphaPot * PotColor.a);
    float4 layerPotStroke = float4(StrokeColor.rgb, StrokeColor.a * strokePotMask);
    float4 layerPot = cactus_over(layerPotStroke, layerPotFill);

    // 6. Composition
    float4 finalColor = layerShadow;
    finalColor = cactus_over(layerCactusGroup, finalColor); // Cactus behind the Pot's front edge
    finalColor = cactus_over(layerPot, finalColor);         // Pot completely masks the roots

    outColor = finalColor;
}
