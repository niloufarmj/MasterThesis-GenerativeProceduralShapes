#ifndef PI
#define PI 3.14159265359
#endif

// Helper: Procedural Hash
float2 cactus_hash(float2 p, float seed) {
    float3 p3 = frac(float3(p.xyx) * float3(0.1031, 0.1030, 0.0973) + seed * 0.123);
    p3 += dot(p3, p3.yzx + 33.33);
    return frac((p3.xx + p3.yz) * p3.zy);
}

// Helper: Smooth Minimum for organic connections
float cactus_smin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / max(k, 1e-5), 0.0, 1.0);
    return lerp(b, a, h) - k * h * (1.0 - h);
}

// Helper: Gradient-based Ellipse SDF for the ground
float cactus_sdEllipse(float2 p, float2 ab) {
    ab = max(ab, 1e-5);
    float f = length(p / ab) - 1.0;
    float2 grad = p / (ab * ab);
    return f / max(length(grad), 1e-8);
}

// Helper: Angled Arm Skeleton SDF
float cactus_sdArmSkeleton(float2 p, float2 p0, float2 p1, float2 p2) {
    float2 pa1 = p - p0, ba1 = p1 - p0;
    float h1 = clamp(dot(pa1, ba1) / max(dot(ba1, ba1), 1e-5), 0.0, 1.0);
    float d1 = length(pa1 - ba1 * h1);
    
    float2 pa2 = p - p1, ba2 = p2 - p1;
    float h2 = clamp(dot(pa2, ba2) / max(dot(ba2, ba2), 1e-5), 0.0, 1.0);
    float d2 = length(pa2 - ba2 * h2);
    
    float k = 0.06;
    float res = clamp(0.5 + 0.5 * (d2 - d1) / k, 0.0, 1.0);
    return lerp(d2, d1, res) - k * res * (1.0 - res);
}

// Helper: Blooming Flower SDF
float cactus_sdFlower(float2 p, float2 center, float petalCount, float radius, float petalLength) {
    float2 cp = p - center;
    float r = length(cp);
    float a = atan2(cp.y, cp.x);
    float wave = 0.5 + 0.5 * cos(petalCount * a);
    float shape = pow(max(0.0, wave), 1.5);
    return r - (radius + petalLength * shape);
}

// Helper: Standard Source-Over Alpha Composite
float4 cactus_over(float4 src, float4 dst) {
    float a = src.a + dst.a * (1.0 - src.a);
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-8);
    return float4(c, a);
}

void CartoonCactus_float(
    float2 UV,
    float TrunkHeight,
    float TrunkWidth,
    float TrunkTaper,
    float4 CactusColor,
    float ArmLength,
    float ArmSpread,
    float ArmWidth,
    float ArmAngle,
    float SpineCount,
    float SpineLength,
    float4 SpineColor,
    float FlowerPetalCount,
    float FlowerSize,
    float4 FlowerColor,
    float GroundWidth,
    float4 GroundColor,
    float StrokeThickness,
    float4 StrokeColor,
    out float4 outColor
) {
    float2 p = UV;
    
    // Geometry Coordinates Definition
    float2 P_base = float2(0.5, max(0.1, 0.5 - TrunkHeight * 0.5));
    float2 P_top = P_base + float2(0.0, TrunkHeight);
    
    float2 P_R0 = P_base + float2(0.0, TrunkHeight * 0.45);
    float2 P_R1 = P_R0 + float2(ArmSpread, ArmAngle);
    float2 P_R2 = P_R1 + float2(0.0, ArmLength);
    
    float2 P_L0 = P_base + float2(0.0, TrunkHeight * 0.65);
    float2 P_L1 = P_L0 + float2(-ArmSpread, ArmAngle);
    float2 P_L2 = P_L1 + float2(0.0, ArmLength);
    
    // 1. SDF: Ground Base
    float2 P_ground = float2(0.5, P_base.y - TrunkWidth * 0.9);
    float dGround = cactus_sdEllipse(p - P_ground, float2(GroundWidth, GroundWidth * 0.2));
    
    // 2. SDF: Cactus Body
    float2 pa = p - P_base, ba = P_top - P_base;
    float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-5), 0.0, 1.0);
    float dTrunk = length(pa - ba * h) - TrunkWidth * lerp(1.0, TrunkTaper, h);
    
    float dArmR = cactus_sdArmSkeleton(p, P_R0, P_R1, P_R2) - ArmWidth;
    float dArmL = cactus_sdArmSkeleton(p, P_L0, P_L1, P_L2) - ArmWidth;
    
    float dCactus = cactus_smin(dTrunk, dArmR, 0.05);
    dCactus = cactus_smin(dCactus, dArmL, 0.05);
    
    // 3. SDF: Flowers
    float2 F_L = P_L2 + float2(0.0, ArmWidth * 0.8);
    float2 F_R = P_R2 + float2(0.0, ArmWidth * 0.8);
    float dFlower1 = cactus_sdFlower(p, F_R, FlowerPetalCount, FlowerSize * 0.5, FlowerSize * 0.5);
    float dFlower2 = cactus_sdFlower(p, F_L, FlowerPetalCount, FlowerSize * 0.5, FlowerSize * 0.5);
    float dFlowers = min(dFlower1, dFlower2);
    
    // 4. SDF: Spines (Grid Spatial Hashing)
    float dSpines = 999.0;
    float safeSpineCount = max(SpineCount, 1.0);
    if (SpineCount > 0.0) {
        float2 gridP = p * safeSpineCount;
        float2 cellId = floor(gridP);
        float2 localP = frac(gridP) - 0.5;
        
        for(int y = -1; y <= 1; y++) {
            for(int x = -1; x <= 1; x++) {
                float2 offset = float2(x, y);
                float2 id = cellId + offset;
                float2 cellCenterUV = (id + 0.5) / safeSpineCount;
                
                // Sample cactus skeleton approx. at the cell center
                float2 paC = cellCenterUV - P_base;
                float hC = clamp(dot(paC, ba) / max(dot(ba, ba), 1e-5), 0.0, 1.0);
                float dTC = length(paC - ba * hC) - TrunkWidth * lerp(1.0, TrunkTaper, hC);
                float dARC = cactus_sdArmSkeleton(cellCenterUV, P_R0, P_R1, P_R2) - ArmWidth;
                float dALC = cactus_sdArmSkeleton(cellCenterUV, P_L0, P_L1, P_L2) - ArmWidth;
                
                float dCC = cactus_smin(dTC, dARC, 0.05);
                dCC = cactus_smin(dCC, dALC, 0.05);
                
                // Only place spines inside the body geometry
                if (dCC < 0.0) {
                    float2 h2 = cactus_hash(id, 13.37) - 0.5;
                    float2 lP = localP - offset - h2 * 0.5;
                    
                    // Random spine rotation
                    float angle = h2.x * 6.2831;
                    float cA = cos(angle), sA = sin(angle);
                    float2 rP = float2(cA * lP.x + sA * lP.y, -sA * lP.x + cA * lP.y);
                    
                    float spineThicknessGrid = 0.003 * safeSpineCount;
                    float sLen = SpineLength * safeSpineCount;
                    
                    float2 spPa = rP - float2(0.0, -sLen);
                    float2 spBa = float2(0.0, sLen * 2.0);
                    float spH = clamp(dot(spPa, spBa) / max(dot(spBa, spBa), 1e-5), 0.0, 1.0);
                    float dS = length(spPa - spBa * spH) - spineThicknessGrid;
                    
                    dSpines = min(dSpines, dS);
                }
            }
        }
        dSpines /= safeSpineCount;
    }
    
    // Rendering and Analytic AA
    float aa = max(fwidth(p.x), fwidth(p.y));
    aa = max(aa, 0.001);
    float halfStroke = max(StrokeThickness, 0.0) * 0.5;
    
    outColor = float4(0.0, 0.0, 0.0, 0.0);
    
    // Composite: Ground
    float alphaGround = 1.0 - smoothstep(0.0, aa, dGround);
    float strokeGroundMask = 1.0 - smoothstep(0.0, aa, abs(dGround) - halfStroke);
    float4 layerGround = cactus_over(
        float4(StrokeColor.rgb, StrokeColor.a * strokeGroundMask),
        float4(GroundColor.rgb, GroundColor.a * alphaGround)
    );
    outColor = cactus_over(layerGround, outColor);
    
    // Composite: Cactus Main Body
    float alphaCactus = 1.0 - smoothstep(0.0, aa, dCactus);
    float strokeCactusMask = 1.0 - smoothstep(0.0, aa, abs(dCactus) - halfStroke);
    float4 layerCactus = cactus_over(
        float4(StrokeColor.rgb, StrokeColor.a * strokeCactusMask),
        float4(CactusColor.rgb, CactusColor.a * alphaCactus)
    );
    outColor = cactus_over(layerCactus, outColor);
    
    // Composite: Spines (No Outline)
    float alphaSpines = 1.0 - smoothstep(0.0, aa, dSpines);
    float4 layerSpines = float4(SpineColor.rgb, SpineColor.a * alphaSpines);
    outColor = cactus_over(layerSpines, outColor);
    
    // Composite: Flowers
    float alphaFlowers = 1.0 - smoothstep(0.0, aa, dFlowers);
    float strokeFlowersMask = 1.0 - smoothstep(0.0, aa, abs(dFlowers) - halfStroke);
    float4 layerFlowers = cactus_over(
        float4(StrokeColor.rgb, StrokeColor.a * strokeFlowersMask),
        float4(FlowerColor.rgb, FlowerColor.a * alphaFlowers)
    );
    outColor = cactus_over(layerFlowers, outColor);
}
