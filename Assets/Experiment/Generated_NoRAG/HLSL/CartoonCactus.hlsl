// PLAN:
// 1) Remap UV to centered coordinates.
// 2) Compute Ground SDF using an elongated sdRoundBox.
// 3) Compute Cactus Body SDF (tapered trunk + mirrored curved arms) using segments and smin for smooth organic joints.
// 4) Compute Spines SDF using domain repetition, clipping them strictly to the body margin so they stick out perfectly.
// 5) Compute Flowers SDF at the tip of the arms using a polar wave for distinct petals.
// 6) Render each layer back-to-front (Ground -> Body -> Spines -> Flower) with 'src over' outline compositing.

#ifndef PI
#define PI 3.14159265359
#endif

inline float sdSegment(float2 p, float2 a, float2 b) {
    float2 pa = p - a, ba = b - a;
    float h = saturate(dot(pa, ba) / max(dot(ba, ba), 1e-12));
    return length(pa - ba * h);
}

inline float smin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / max(k, 1e-5), 0.0, 1.0);
    return lerp(b, a, h) - k * h * (1.0 - h);
}

inline float sdRoundBox(float2 p, float2 b, float r) {
    float2 q = abs(p) - b;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

inline float4 renderLayer(float d, float4 fillColor, float4 strokeColor, float strokeWidth, float aa) {
    float totalMask = smoothstep(aa, -aa, d - strokeWidth * 0.5);
    float insideMask = smoothstep(aa, -aa, d + strokeWidth * 0.5);
    float3 rgb = lerp(strokeColor.rgb, fillColor.rgb, insideMask);
    return float4(rgb, totalMask);
}

inline float4 nm_over(float4 src, float4 dst) {
    float a = src.a + dst.a * (1.0 - src.a);
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-8);
    return float4(c, a);
}

void CartoonCactus_float(
    float2 UV,
    float TrunkWidth,
    float TrunkHeight,
    float Taper,
    float4 CactusColor,
    float ArmLength,
    float ArmWidth,
    float BranchAngle,
    float SpineLength,
    float SpineCount,
    float4 SpineColor,
    float PetalCount,
    float4 PetalColor,
    float BaseWidth,
    float4 BaseColor,
    float StrokeThickness,
    float4 StrokeColor,
    out float4 outColor
) {
    float2 p = UV - 0.5;
    float aa = 0.005;
    
    // 1. Ground
    float2 bp = p - float2(0.0, -TrunkHeight * 0.5 - TrunkWidth * 0.5 + 0.02);
    float dGround = sdRoundBox(bp, float2(BaseWidth * 0.5, 0.005), 0.02);
    
    // 2. Cactus Body
    // Tapered Trunk
    float yRatio = clamp((p.y + TrunkHeight * 0.5) / max(TrunkHeight, 0.001), 0.0, 1.0);
    float currentTrunkWidth = lerp(TrunkWidth, TrunkWidth * Taper, yRatio);
    float dTrunk = sdSegment(p, float2(0.0, -TrunkHeight * 0.5), float2(0.0, TrunkHeight * 0.5)) - currentTrunkWidth * 0.5;
    
    // Arms
    float2 armP = p;
    armP.x = abs(armP.x); // Mirror logic for both sides
    
    float2 branchP = float2(TrunkWidth * 0.2, 0.0);
    float2 armDir = float2(sin(BranchAngle), cos(BranchAngle));
    float2 elbowP = branchP + armDir * ArmLength * 0.5;
    float2 armEndP = elbowP + float2(0.0, ArmLength * 0.5);
    
    float dArmSeg1 = sdSegment(armP, branchP, elbowP);
    float dArmSeg2 = sdSegment(armP, elbowP, armEndP);
    float dArmCore = smin(dArmSeg1, dArmSeg2, 0.08);
    float dArm = dArmCore - ArmWidth * 0.5;
    
    // Blend arms and trunk seamlessly
    float dBody = smin(dTrunk, dArm, 0.05);
    
    // 3. Spines
    float2 sp = p * max(SpineCount, 1.0);
    float row = floor(sp.y);
    float2 gridP = frac(float2(sp.x + row * 0.5, sp.y)) - 0.5;
    
    // V-shaped spine pointing outwards/downwards
    float sl = SpineLength * max(SpineCount, 1.0);
    float dV1 = sdSegment(gridP, float2(0.0, 0.0), float2(-sl, sl));
    float dV2 = sdSegment(gridP, float2(0.0, 0.0), float2(sl, sl));
    float dSpineGrid = min(dV1, dV2) / max(SpineCount, 1.0) - 0.003;
    
    // Clip spines so they only dot the surface and protrude accurately
    float dSpines = max(dSpineGrid, dBody - SpineLength);
    
    // 4. Flowers
    float2 flowerCenter = armEndP + float2(0.0, ArmWidth * 0.5);
    float2 fp = armP - flowerCenter;
    float rFlower = length(fp);
    float aFlower = atan2(fp.y, fp.x);
    float petalWobble = abs(sin(aFlower * PetalCount * 0.5));
    float dFlower = rFlower - (0.02 + 0.04 * petalWobble);
    
    // 5. Compositing
    float4 bg = float4(0.0, 0.0, 0.0, 0.0);
    
    float4 layerGround = renderLayer(dGround, BaseColor, StrokeColor, StrokeThickness, aa);
    bg = nm_over(layerGround, bg);
    
    float4 layerBody = renderLayer(dBody, CactusColor, StrokeColor, StrokeThickness, aa);
    bg = nm_over(layerBody, bg);
    
    // Spines are drawn as crisp details with no separate outline to stay clean
    float4 layerSpines = renderLayer(dSpines, SpineColor, SpineColor, 0.0, aa);
    bg = nm_over(layerSpines, bg);
    
    float4 layerFlower = renderLayer(dFlower, PetalColor, StrokeColor, StrokeThickness, aa);
    bg = nm_over(layerFlower, bg);
    
    outColor = bg;
}