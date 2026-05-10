#ifndef PI
#define PI 3.14159265359
#endif

// --- Helper Functions ---

float cactus_sdUnevenCapsule(float2 p, float r1, float r2, float h) {
    p.x = abs(p.x);
    float b = (r1 - r2) / h;
    float a = sqrt(max(0.0, 1.0 - b * b));
    float k = dot(p, float2(-b, a));
    if (k < 0.0) return length(p) - r1;
    if (k > a * h) return length(p - float2(0.0, h)) - r2;
    return dot(p, float2(a, b)) - r1;
}

float cactus_sdRoundBox(float2 p, float2 b, float r) {
    float2 q = abs(p) - b + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

float cactus_sdTrapezoid(float2 p, float r1, float r2, float he) {
    float2 k1 = float2(r2, he);
    float2 k2 = float2(r2 - r1, 2.0 * he);
    p.x = abs(p.x);
    float2 ca = float2(p.x - min(p.x, (p.y < 0.0) ? r1 : r2), abs(p.y) - he);
    float2 cb = p - k1 + k2 * clamp(dot(k1 - p, k2) / dot(k2, k2), 0.0, 1.0);
    float s = (cb.x < 0.0 && ca.y < 0.0) ? -1.0 : 1.0;
    return s * sqrt(min(dot(ca, ca), dot(cb, cb)));
}

float cactus_sdCapsule(float2 p, float2 a, float2 b, float r) {
    float2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / max(dot(ba, ba), 0.0001), 0.0, 1.0);
    return length(pa - ba * h) - r;
}

float4 cactus_blend(float4 top, float4 bottom) {
    float a = top.a + bottom.a * (1.0 - top.a);
    if (a < 0.0001) return float4(0, 0, 0, 0);
    float3 c = (top.rgb * top.a + bottom.rgb * bottom.a * (1.0 - top.a)) / a;
    return float4(c, a);
}

// --- Rendering Functions ---

float4 renderCactusPart(float2 p, float2 pos, float rot, float length_, float width, float curve, 
                        float4 lightCol, float4 shadowCol, float4 stripeCol, float4 thornCol, 
                        float thornsDensity, out float2 topPos) {
    
    // Transform to local space
    float2 localP = p - pos;
    float c = cos(rot), s = sin(rot);
    localP = float2(c * localP.x + s * localP.y, -s * localP.x + c * localP.y);
    
    // Deform and set base
    float2 defP = localP;
    defP.y += length_ * 0.5;
    defP.x += curve * defP.y * defP.y;
    
    float r1 = width * 0.8; 
    float r2 = width * 1.1; 
    
    float d = cactus_sdUnevenCapsule(defP, r1, r2, length_);
    float aa = fwidth(p.x);
    if(aa <= 0.0) aa = 0.005;
    
    float alpha = smoothstep(aa, -aa, d);
    
    // Compute top attachment point for the flower
    float visualTopY = length_ + r2;
    float localX = -curve * visualTopY * visualTopY;
    float localY = length_ * 0.5 + r2 - 0.05; 
    float2 localP_top = float2(localX, localY);
    topPos = float2(c * localP_top.x - s * localP_top.y, s * localP_top.x + c * localP_top.y) + pos;
    
    if (alpha <= 0.0) return float4(0, 0, 0, 0);
    
    // Shadow
    float2 shadowP = localP;
    shadowP.x -= width * 0.25; 
    float2 defShadowP = shadowP;
    defShadowP.y += length_ * 0.5;
    defShadowP.x += curve * defShadowP.y * defShadowP.y;
    float dShadow = cactus_sdUnevenCapsule(defShadowP, r1, r2, length_);
    float isShadow = smoothstep(-aa * 2.0, aa * 2.0, dShadow);
    
    // Stripes
    float stripeUV = defP.x * (1.0 / width) * 2.5;
    float stripeVal = abs(frac(stripeUV) - 0.5);
    float isStripe = smoothstep(0.1 + aa * 15.0, 0.1, stripeVal);
    isStripe *= smoothstep(0.0, width * 0.2, -d);
    
    // Thorns
    float2 grid = floor(defP * thornsDensity);
    float2 gridP = frac(defP * thornsDensity) - 0.5;
    float hash = frac(sin(dot(grid, float2(12.9898, 78.233))) * 43758.5453);
    float isThorn = 0.0;
    if (hash > 0.75) {
        float rotT = hash * PI;
        float ct = cos(rotT), st = sin(rotT);
        float2 tp = float2(ct * gridP.x + st * gridP.y, -st * gridP.x + ct * gridP.y);
        float dThorn = cactus_sdCapsule(tp, float2(0.0, -0.15), float2(0.0, 0.15), 0.04);
        isThorn = smoothstep(aa * thornsDensity, 0.0, dThorn);
    }
    isThorn *= smoothstep(0.0, width * 0.1, -d);
    
    float3 col = lightCol.rgb;
    col = lerp(col, shadowCol.rgb, isShadow);
    col = lerp(col, stripeCol.rgb, isStripe * stripeCol.a);
    col = lerp(col, thornCol.rgb, isThorn * thornCol.a);
    
    return float4(col, alpha * lightCol.a);
}

float4 renderFlower(float2 p, float2 pos, float rot, float size, float petalCount, 
                    float petalSize, float centerSize, float4 petalCol, float4 centerCol) {
    float2 localP = p - pos;
    float c = cos(rot), s = sin(rot);
    localP = float2(c * localP.x + s * localP.y, -s * localP.x + c * localP.y);
    
    if (size < 0.001) return float4(0, 0, 0, 0);
    localP /= size;
    
    float aa = fwidth(localP.x);
    if (aa <= 0.0) aa = 0.005;
    
    float dCenter = length(localP) - centerSize;
    
    float a = atan2(localP.y, localP.x);
    float stepA = 2.0 * PI / max(petalCount, 1.0);
    float id = floor(a / stepA + 0.5);
    float angle = id * stepA;
    
    float cp = cos(angle), sp = sin(angle);
    float2 rotP = float2(cp * localP.x + sp * localP.y, -sp * localP.x + cp * localP.y);
    rotP.x -= centerSize + petalSize * 0.8;
    float dp = length(rotP / float2(petalSize, petalSize * 0.6)) - 1.0;
    dp *= petalSize * 0.6;
    
    float alphaCenter = smoothstep(aa, -aa, dCenter);
    float alphaPetal = smoothstep(aa, -aa, dp);
    
    return cactus_blend(float4(centerCol.rgb, alphaCenter * centerCol.a), 
                        float4(petalCol.rgb, alphaPetal * petalCol.a));
}

// --- Main Shader Function ---

void ProceduralCactus_float(
    float2 UV,
    float4 PotBaseColor,
    float4 PotRimColor,
    float4 PotHighlightColor,
    float PotSize,
    float PotHeight,
    float PotWidth,
    
    float4 CactusLightColor,
    float4 CactusShadowColor,
    float4 StripeColor,
    float4 ThornColor,
    float ThornsDensity,
    
    float MainBodyHeight,
    float MainBodyWidth,
    
    float2 LeftHandPos,
    float LeftHandRot,
    float LeftHandSize,
    float LeftHandWidth,
    float LeftHandCurve,
    
    float2 RightHandPos,
    float RightHandRot,
    float RightHandSize,
    float RightHandWidth,
    float RightHandCurve,
    
    float FlowerSize,
    float FlowerPetalCount,
    float FlowerPetalSize,
    float FlowerCenterSize,
    float4 FlowerPetalColor,
    float4 FlowerCenterColor,
    
    out float4 outColor
) {
    float2 p = (UV - 0.5) * 3.0;
    
    float2 topMain, topLeft, topRight;
    
    // 1. Right Hand (Back Layer)
    float4 layerRightHand = renderCactusPart(p, RightHandPos, RightHandRot, RightHandSize, RightHandWidth, RightHandCurve, 
                                            CactusLightColor, CactusShadowColor, StripeColor, ThornColor, ThornsDensity, topRight);
                                            
    // 2. Main Body (Middle Layer)
    float4 layerMainBody = renderCactusPart(p, float2(0.0, -0.1), 0.0, MainBodyHeight, MainBodyWidth, 0.0, 
                                           CactusLightColor, CactusShadowColor, StripeColor, ThornColor, ThornsDensity, topMain);
                                           
    // 3. Left Hand (Front Layer)
    float4 layerLeftHand = renderCactusPart(p, LeftHandPos, LeftHandRot, LeftHandSize, LeftHandWidth, LeftHandCurve, 
                                           CactusLightColor, CactusShadowColor, StripeColor, ThornColor, ThornsDensity, topLeft);
                                           
    // 4. Pot
    float2 potP = p - float2(0.0, -0.6);
    potP /= max(PotSize, 0.001);
    float aaPot = fwidth(potP.x); 
    if (aaPot <= 0.0) aaPot = 0.005;
    
    float dPotBase = cactus_sdTrapezoid(potP, PotWidth * 0.7, PotWidth, PotHeight * 0.5);
    float alphaPotBase = smoothstep(aaPot, -aaPot, dPotBase);
    
    float2 hlP = potP - float2(PotWidth * 0.6, 0.0);
    hlP = float2(0.96 * hlP.x + 0.25 * hlP.y, -0.25 * hlP.x + 0.96 * hlP.y); 
    float dHighlight = cactus_sdCapsule(hlP, float2(0.0, -PotHeight * 0.3), float2(0.0, PotHeight * 0.2), 0.03);
    float alphaHighlight = smoothstep(aaPot, -aaPot, dHighlight) * alphaPotBase;
    
    float2 rimP = potP - float2(0.0, PotHeight * 0.5);
    float dRim = cactus_sdRoundBox(rimP, float2(PotWidth * 1.15, PotHeight * 0.15), 0.05);
    float alphaRim = smoothstep(aaPot, -aaPot, dRim);
    
    float3 potBaseColRGB = lerp(PotBaseColor.rgb, PotHighlightColor.rgb, alphaHighlight * PotHighlightColor.a);
    float4 layerPotBase = float4(potBaseColRGB, alphaPotBase * PotBaseColor.a);
    float4 layerPotRim = float4(PotRimColor.rgb, alphaRim * PotRimColor.a);
    float4 layerPot = cactus_blend(layerPotRim, layerPotBase);
    
    // 5. Flowers
    float4 layerFlowerRight = renderFlower(p, topRight, RightHandRot, FlowerSize * 0.8, FlowerPetalCount, FlowerPetalSize, FlowerCenterSize, FlowerPetalColor, FlowerCenterColor);
    float4 layerFlowerMain = renderFlower(p, topMain, 0.0, FlowerSize, FlowerPetalCount, FlowerPetalSize, FlowerCenterSize, FlowerPetalColor, FlowerCenterColor);
    float4 layerFlowerLeft = renderFlower(p, topLeft, LeftHandRot, FlowerSize, FlowerPetalCount, FlowerPetalSize, FlowerCenterSize, FlowerPetalColor, FlowerCenterColor);
    
    float4 layerFlowers = cactus_blend(layerFlowerMain, layerFlowerLeft);
    layerFlowers = cactus_blend(layerFlowers, layerFlowerRight);
    
    // Composition (Back to Front)
    float4 finalCol = float4(0, 0, 0, 0);
    finalCol = cactus_blend(layerRightHand, finalCol);
    finalCol = cactus_blend(layerMainBody, finalCol);
    finalCol = cactus_blend(layerLeftHand, finalCol);
    finalCol = cactus_blend(layerPot, finalCol);
    finalCol = cactus_blend(layerFlowers, finalCol);
    
    outColor = finalCol;
}
