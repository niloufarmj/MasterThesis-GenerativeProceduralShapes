// PLAN:
// 1. Define primitive SDFs (RoundBox for cactus parts, Trapezoid for pot base, Capsule for thorns, Flower).
// 2. Map UV to centered local space.
// 3. Construct Cactus Body and rotated Hands using sdRoundBox.
// 4. Construct Pot using Trapezoid and a RoundBox for the rim.
// 5. Place Flowers at the tops of the cactus parts.
// 6. Generate vertical Ridges using periodic functions in local part spaces.
// 7. Scatter Thorns using grid UVs and pseudo-random placement.
// 8. Layer everything back-to-front using an 'over' blending function to ensure clean outlines and overlaps.

#ifndef PI
#define PI 3.14159265359
#endif

// --- Helper Functions ---
inline float2 rotate2D(float2 p, float a) {
    float s = sin(a), c = cos(a);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

inline float sdRoundBox(float2 p, float2 halfSize, float r) {
    float2 b = max(halfSize - r, 0.0);
    float2 q = abs(p) - b;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

inline float2 nm_perpRight(float2 e) {
    return float2(e.y, -e.x);
}

inline float nm_distPointToSegment(float2 p, float2 a, float2 b) {
    float2 pa = p - a, ba = b - a;
    float baba = dot(ba, ba);
    float h = saturate(baba > 0.0 ? dot(pa, ba) / baba : 0.0);
    return length(pa - ba * h);
}

inline float nm_sdTrapezoid(float2 p, float widthBottom, float widthTop, float height) {
    float a = 0.5 * widthTop;
    float b = 0.5 * widthBottom;
    float h = 0.5 * height;
    float2 v0 = float2(-b, -h);
    float2 v1 = float2(b, -h);
    float2 v2 = float2(a, h);
    float2 v3 = float2(-a, h);
    float2 e0 = v1 - v0, n0 = normalize(nm_perpRight(e0));
    float2 e1 = v2 - v1, n1 = normalize(nm_perpRight(e1));
    float2 e2 = v3 - v2, n2 = normalize(nm_perpRight(e2));
    float2 e3 = v0 - v3, n3 = normalize(nm_perpRight(e3));
    float d0 = dot(n0, p - v0);
    float d1 = dot(n1, p - v1);
    float d2 = dot(n2, p - v2);
    float d3 = dot(n3, p - v3);
    float sgn = (max(max(d0, d1), max(d2, d3)) <= 0.0) ? -1.0 : 1.0;
    float du = min(min(nm_distPointToSegment(p, v0, v1), nm_distPointToSegment(p, v1, v2)),
                   min(nm_distPointToSegment(p, v2, v3), nm_distPointToSegment(p, v3, v0)));
    return du * sgn;
}

inline float sdCapsule(float2 p, float2 a, float2 b, float r) {
    return nm_distPointToSegment(p, a, b) - r;
}

inline float sdFlower(float2 p, float r, float petalSize, float petalCount) {
    float angle = atan2(p.y, p.x);
    float radius = r + petalSize * cos(petalCount * angle);
    return length(p) - radius;
}

inline float4 nm_over(float4 src, float4 dst) {
    float a = src.a + dst.a * (1.0 - src.a);
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-8);
    return float4(c, a);
}

// --- Main Function ---
// A cartoon cactus in a pot with adjustable body, arms, thorns, flowers, and pot dimensions.
void CartoonCactus_float(
    float2 UV,
    float4 BodyParams,
    float4 HandParams,
    float2 HandOffset,
    float HandAngle,
    float4 ThornParams,
    float4 FlowerParams,
    float2 RidgeParams,
    float4 PotParams,
    float PotRimWidth,
    float PotPosY,
    float OutlineWidth,
    float4 CactusColor,
    float4 RidgeColor,
    float4 ThornColor,
    float4 FlowerColor,
    float4 FlowerCenterColor,
    float4 PotColor,
    float4 OutlineColor,
    out float4 outColor
) {
    float2 p = UV - 0.5;
    float aa = length(float2(ddx(p.x), ddy(p.y)));
    aa = max(aa, 0.001);

    // 1. CACTUS SHAPE (Body + Hands)
    float bodyCenterY = 0.05;
    float2 pBody = p - float2(0.0, bodyCenterY);
    float2 pHandR = p - float2(HandOffset.x, bodyCenterY + HandOffset.y);
    float2 pHandL = p - float2(-HandOffset.x, bodyCenterY + HandOffset.y);

    float dBody = sdRoundBox(pBody, BodyParams.xy, BodyParams.z);
    float dHandR = sdRoundBox(rotate2D(pHandR, HandAngle), HandParams.xy, HandParams.z);
    float dHandL = sdRoundBox(rotate2D(pHandL, -HandAngle), HandParams.xy, HandParams.z);
    
    float dCactus = min(dBody, min(dHandL, dHandR));

    // 2. CACTUS RIDGES
    float rFreq = max(RidgeParams.x, 0.1);
    float rThick = RidgeParams.y;
    float ridgeBody = (abs(frac(pBody.x * rFreq + 0.5) - 0.5) - rThick) / rFreq;
    float ridgeHandR = (abs(frac(rotate2D(pHandR, HandAngle).x * rFreq + 0.5) - 0.5) - rThick) / rFreq;
    float ridgeHandL = (abs(frac(rotate2D(pHandL, -HandAngle).x * rFreq + 0.5) - 0.5) - rThick) / rFreq;

    float dRidge = ridgeBody;
    dRidge = lerp(dRidge, ridgeHandR, step(dHandR, dBody));
    dRidge = lerp(dRidge, ridgeHandL, step(dHandL, min(dBody, dHandR)));

    // 3. THORNS (Scattered pattern)
    float2 gridP = p * ThornParams.x;
    float2 cellId = floor(gridP);
    float2 localP = frac(gridP) - 0.5;
    
    float rand1 = frac(sin(dot(cellId, float2(12.9898, 78.233))) * 43758.5453);
    float rand2 = frac(sin(dot(cellId, float2(93.989, 67.345))) * 24634.6345);
    localP += (float2(rand1, rand2) - 0.5) * 0.4; // Jitter within cell
    localP = rotate2D(localP, rand1 * PI * 2.0 + ThornParams.w); // Random rotation
    
    float dThornLocal = sdCapsule(localP, float2(0.0, -ThornParams.z), float2(0.0, ThornParams.z), ThornParams.y);
    float dThorn = dThornLocal / max(ThornParams.x, 0.001);

    // 4. POT SHAPE
    float2 pPotBase = p - float2(0.0, PotPosY);
    float dPotBase = nm_sdTrapezoid(pPotBase, PotParams.z, PotParams.y, PotParams.x);
    float2 pPotRim = p - float2(0.0, PotPosY + PotParams.x * 0.5 + PotParams.w * 0.5);
    float dPotRim = sdRoundBox(pPotRim, float2(PotRimWidth * 0.5, PotParams.w * 0.5), 0.02);
    float dPot = min(dPotBase, dPotRim);

    // 5. FLOWERS SHAPE
    float2 topBody = float2(0.0, bodyCenterY + BodyParams.y + BodyParams.z * 0.5);
    float2 topHandR = float2(HandOffset.x, bodyCenterY + HandOffset.y) + rotate2D(float2(0.0, HandParams.y + HandParams.z * 0.5), -HandAngle);
    float2 topHandL = float2(-HandOffset.x, bodyCenterY + HandOffset.y) + rotate2D(float2(0.0, HandParams.y + HandParams.z * 0.5), HandAngle);

    float dFlower1 = sdFlower(p - topBody, FlowerParams.x, FlowerParams.y, FlowerParams.z);
    float dFlower2 = sdFlower(p - topHandR, FlowerParams.x, FlowerParams.y, FlowerParams.z);
    float dFlower3 = sdFlower(p - topHandL, FlowerParams.x, FlowerParams.y, FlowerParams.z);
    float dFlowers = min(dFlower1, min(dFlower2, dFlower3));

    float dCenter1 = length(p - topBody) - FlowerParams.x * 0.6;
    float dCenter2 = length(p - topHandR) - FlowerParams.x * 0.6;
    float dCenter3 = length(p - topHandL) - FlowerParams.x * 0.6;
    float dFlowerCenters = min(dCenter1, min(dCenter2, dCenter3));

    // 6. COMPOSITING (Back to Front)
    outColor = float4(0.0, 0.0, 0.0, 0.0);
    float halfStroke = OutlineWidth * 0.5;

    // Cactus Fill
    float mCactusFill = smoothstep(aa, -aa, dCactus);
    outColor = nm_over(float4(CactusColor.rgb, CactusColor.a * mCactusFill), outColor);

    // Cactus Ridges (clipped to body)
    float mRidge = smoothstep(aa, -aa, dRidge) * mCactusFill;
    outColor = nm_over(float4(RidgeColor.rgb, RidgeColor.a * mRidge), outColor);

    // Cactus Thorns (clipped to body)
    float mThorn = smoothstep(aa, -aa, dThorn) * mCactusFill;
    outColor = nm_over(float4(ThornColor.rgb, ThornColor.a * mThorn), outColor);

    // Cactus Outline
    float dCactusOutline = abs(dCactus) - halfStroke;
    float mCactusOut = smoothstep(aa, -aa, dCactusOutline);
    outColor = nm_over(float4(OutlineColor.rgb, OutlineColor.a * mCactusOut), outColor);

    // Pot Fill
    float mPotFill = smoothstep(aa, -aa, dPot);
    outColor = nm_over(float4(PotColor.rgb, PotColor.a * mPotFill), outColor);

    // Pot Outline
    float dPotOutline = abs(dPot) - halfStroke;
    float mPotOut = smoothstep(aa, -aa, dPotOutline);
    outColor = nm_over(float4(OutlineColor.rgb, OutlineColor.a * mPotOut), outColor);

    // Flowers Fill
    float mFlowerFill = smoothstep(aa, -aa, dFlowers);
    outColor = nm_over(float4(FlowerColor.rgb, FlowerColor.a * mFlowerFill), outColor);

    // Flowers Outline
    float dFlowerOutline = abs(dFlowers) - halfStroke;
    float mFlowerOut = smoothstep(aa, -aa, dFlowerOutline);
    outColor = nm_over(float4(OutlineColor.rgb, OutlineColor.a * mFlowerOut), outColor);

    // Flower Centers Fill
    float mCenterFill = smoothstep(aa, -aa, dFlowerCenters);
    outColor = nm_over(float4(FlowerCenterColor.rgb, FlowerCenterColor.a * mCenterFill), outColor);

    // Flower Centers Outline
    float dCenterOutline = abs(dFlowerCenters) - halfStroke;
    float mCenterOut = smoothstep(aa, -aa, dCenterOutline);
    outColor = nm_over(float4(OutlineColor.rgb, OutlineColor.a * mCenterOut), outColor);
}
