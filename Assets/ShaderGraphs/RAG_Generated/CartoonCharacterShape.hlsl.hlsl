#ifndef PI
#define PI 3.14159265359
#endif

// --- Helpers ---

float nm_distSqSegment(float2 p, float2 a, float2 b) {
    float2 pa = p - a, ba = b - a;
    float lenSq = dot(ba, ba);
    float h = saturate(dot(pa, ba) / max(lenSq, 1e-8));
    float2 d = pa - ba * h;
    return dot(d, d);
}

float nm_sdConvexPoly4(float2 p, float2 v0, float2 v1, float2 v2, float2 v3) {
    float2 v[4] = { v0, v1, v2, v3 };
    float minDSq = 1e20;
    float maxSignedDist = -1e20;
    
    [unroll]
    for (int i = 0; i < 4; ++i) {
        float2 a = v[i];
        float2 b = v[(i + 1) % 4];
        float2 e = b - a;
        minDSq = min(minDSq, nm_distSqSegment(p, a, b));
        float2 n = normalize(float2(e.y, -e.x));
        maxSignedDist = max(maxSignedDist, dot(p - a, n));
    }
    
    float dist = sqrt(minDSq);
    return (maxSignedDist > 0.0) ? dist : -dist;
}

float nm_sdSegment(float2 p, float2 a, float2 b) {
    float2 pa = p - a, ba = b - a;
    float h = saturate(dot(pa, ba) / max(dot(ba, ba), 1e-8));
    return length(pa - ba * h);
}

float nm_sdRoundedBox(float2 p, float2 b, float r) {
    float2 q = abs(p) - b + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

float nm_sdBox(float2 p, float2 b) {
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

float nm_sdCircle(float2 p, float r) {
    return length(p) - r;
}

float nm_sdEllipse(float2 p, float2 ab) {
    float2 p_scaled = p / max(ab, 1e-5);
    float d = length(p_scaled) - 1.0;
    return d * min(ab.x, ab.y);
}

inline float4 h_blend(float4 src, float4 dst) {
    float a = src.a + dst.a * (1.0 - src.a);
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-8);
    return float4(c, a);
}

// --- Main Function ---

void CartoonCharacter_float(
    float2 UV,
    float2 Center,
    float OverallSize,
    float4 SkinColor,
    float4 SkinShadowColor,
    float4 HairColor,
    float4 ShirtColor,
    float4 SkirtColor,
    float4 SockColor,
    float4 ShoeColor,
    out float4 outColor
) {
    // 1. Coordinates and scaling
    float2 p = UV - Center;
    p /= max(OverallSize, 0.001);
    
    // Symmetry for bilateral components
    float2 p_sym = float2(abs(p.x), p.y);
    
    // Anti-aliasing scaling factor
    float aa = length(float2(fwidth(p.x), fwidth(p.y))) * 0.707;
    aa = max(aa, 0.0001);
    
    // Initialize empty background
    outColor = float4(0.0, 0.0, 0.0, 0.0);
    
    // --- Layer 1: Pigtails (Back Hair) ---
    float dPigtail = nm_sdCircle(p_sym - float2(0.15, 0.23), 0.06);
    float4 pigtailLayer = float4(HairColor.rgb, HairColor.a * (1.0 - smoothstep(0.0, aa, dPigtail)));
    outColor = h_blend(pigtailLayer, outColor);
    
    // --- Layer 2: Legs ---
    float dLeg = nm_sdSegment(p_sym, float2(0.08, -0.10), float2(0.08, -0.44)) - 0.025;
    float4 legLayer = float4(SkinColor.rgb, SkinColor.a * (1.0 - smoothstep(0.0, aa, dLeg)));
    outColor = h_blend(legLayer, outColor);
    
    // --- Layer 3: Socks ---
    float dSock = nm_sdSegment(p_sym, float2(0.08, -0.34), float2(0.08, -0.45)) - 0.027;
    // Cut flat top and bottom for socks
    dSock = max(dSock, abs(p_sym.y + 0.395) - 0.055);
    float4 sockLayer = float4(SockColor.rgb, SockColor.a * (1.0 - smoothstep(0.0, aa, dSock)));
    outColor = h_blend(sockLayer, outColor);
    
    // --- Layer 4: Shoes ---
    float dShoeBase = nm_sdSegment(p_sym, float2(0.05, -0.46), float2(0.13, -0.46)) - 0.025;
    // Cut flat sole
    dShoeBase = max(dShoeBase, -(p_sym.y + 0.475));
    float dShoeBump = nm_sdCircle(p_sym - float2(0.08, -0.45), 0.025);
    float dShoe = min(dShoeBase, dShoeBump);
    float4 shoeLayer = float4(ShoeColor.rgb, ShoeColor.a * (1.0 - smoothstep(0.0, aa, dShoe)));
    outColor = h_blend(shoeLayer, outColor);
    
    // --- Layer 5: Neck ---
    float dNeck = nm_sdBox(p - float2(0.0, 0.18), float2(0.025, 0.04));
    float4 neckLayer = float4(SkinColor.rgb, SkinColor.a * (1.0 - smoothstep(0.0, aa, dNeck)));
    outColor = h_blend(neckLayer, outColor);
    
    float dNeckShadow = nm_sdBox(p - float2(0.0, 0.195), float2(0.025, 0.015));
    float4 shadowLayer = float4(SkinShadowColor.rgb, SkinShadowColor.a * (1.0 - smoothstep(0.0, aa, dNeckShadow)));
    outColor = h_blend(shadowLayer, outColor);
    
    // --- Layer 6: Torso (Shirt) ---
    float dTorso = nm_sdRoundedBox(p - float2(0.0, 0.10), float2(0.12, 0.09), 0.02);
    float4 torsoLayer = float4(ShirtColor.rgb, ShirtColor.a * (1.0 - smoothstep(0.0, aa, dTorso)));
    outColor = h_blend(torsoLayer, outColor);
    
    // --- Layer 7: Skirt ---
    // Drawn as a convex polygon (trapezoid)
    float2 vTR = float2(0.13, 0.02);
    float2 vTL = float2(-0.13, 0.02);
    float2 vBL = float2(-0.19, -0.20);
    float2 vBR = float2(0.19, -0.20);
    float dSkirt = nm_sdConvexPoly4(p, vTR, vTL, vBL, vBR) - 0.01;
    float4 skirtLayer = float4(SkirtColor.rgb, SkirtColor.a * (1.0 - smoothstep(0.0, aa, dSkirt)));
    outColor = h_blend(skirtLayer, outColor);
    
    // --- Layer 8: Arms (Skin) ---
    float2 armStart = float2(0.13, 0.10);
    float2 armEnd = float2(0.20, -0.15);
    float dArm = nm_sdSegment(p_sym, armStart, armEnd) - 0.025;
    float dThumb = nm_sdSegment(p_sym, armEnd, armEnd + float2(-0.02, 0.01)) - 0.012;
    float dHand = nm_sdCircle(p_sym - armEnd, 0.035);
    float dArmTotal = min(dArm, min(dHand, dThumb));
    float4 armLayer = float4(SkinColor.rgb, SkinColor.a * (1.0 - smoothstep(0.0, aa, dArmTotal)));
    outColor = h_blend(armLayer, outColor);
    
    // --- Layer 9: Sleeves (Shirt) ---
    float2 armDir = normalize(armEnd - armStart);
    float dSleeve = nm_sdSegment(p_sym, armStart, armStart + armDir * 0.08) - 0.035;
    float4 sleeveLayer = float4(ShirtColor.rgb, ShirtColor.a * (1.0 - smoothstep(0.0, aa, dSleeve)));
    outColor = h_blend(sleeveLayer, outColor);
    
    // --- Layer 10: Head & Ears ---
    float dHead = nm_sdRoundedBox(p - float2(0.0, 0.30), float2(0.08, 0.075), 0.04);
    float dEars = nm_sdCircle(p_sym - float2(0.115, 0.28), 0.025);
    float dHeadEars = min(dHead, dEars);
    float4 headLayer = float4(SkinColor.rgb, SkinColor.a * (1.0 - smoothstep(0.0, aa, dHeadEars)));
    outColor = h_blend(headLayer, outColor);
    
    // --- Layer 11: Hair Front & Bangs ---
    float dHairFront = nm_sdEllipse(p - float2(0.0, 0.39), float2(0.12, 0.08));
    float dBang = nm_sdEllipse(p_sym - float2(0.05, 0.36), float2(0.07, 0.04));
    float dHairBase = min(dHairFront, dBang);
    float4 hairFrontLayer = float4(HairColor.rgb, HairColor.a * (1.0 - smoothstep(0.0, aa, dHairBase)));
    outColor = h_blend(hairFrontLayer, outColor);
    
    // --- Layer 12: Face Details ---
    float dEyes = nm_sdCircle(p_sym - float2(0.045, 0.31), 0.008);
    float dEyebrow = nm_sdSegment(p_sym, float2(0.03, 0.35), float2(0.065, 0.355)) - 0.003;
    float dMouthArc = abs(nm_sdCircle(p - float2(0.0, 0.285), 0.02)) - 0.003;
    float dMouth = max(dMouthArc, p.y - 0.28); // Clip top part to form smile
    float dFaceDark = min(dEyes, min(dEyebrow, dMouth));
    float4 faceDarkLayer = float4(HairColor.rgb, HairColor.a * (1.0 - smoothstep(0.0, aa, dFaceDark)));
    outColor = h_blend(faceDarkLayer, outColor);
    
    // Nose (Drawn with darker skin shadow tone)
    float dNose = nm_sdSegment(p, float2(0.0, 0.29), float2(0.0, 0.28)) - 0.003;
    float4 noseLayer = float4(SkinShadowColor.rgb, SkinShadowColor.a * (1.0 - smoothstep(0.0, aa, dNose)));
    outColor = h_blend(noseLayer, outColor);
}
