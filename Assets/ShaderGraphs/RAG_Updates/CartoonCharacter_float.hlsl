#ifndef PI
#define PI 3.14159265359
#endif

// --- Helpers ---

float2 rot2D(float2 p, float angle) {
    float c = cos(angle);
    float s = sin(angle);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

float sdLimb(float2 p, float2 pivot, float angle, float halfW, float segLen) {
    float2 localP = p - pivot;
    localP = rot2D(localP, -angle);
    float h = saturate(localP.x / max(segLen, 1e-8));
    float2 d = localP - float2(h * segLen, 0.0);
    return length(d) - halfW;
}

float2 limbEnd(float2 pivot, float angle, float segLen) {
    return pivot + float2(cos(angle), sin(angle)) * segLen;
}

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
    float LShoulderAngle,
    float RShoulderAngle,
    float LElbowAngle,
    float RElbowAngle,
    float LHipAngle,
    float RHipAngle,
    float LKneeAngle,
    float RKneeAngle,
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
    // Right Leg Kinematics
    float2 rHip = float2(0.08, -0.10);
    float rUpperLegAngle = -1.570796 + RHipAngle;
    float rLowerLegAngle = rUpperLegAngle + RKneeAngle;
    float legLen = 0.17;
    float2 rKnee = limbEnd(rHip, rUpperLegAngle, legLen);
    
    // Left Leg Kinematics
    float2 lHip = float2(-0.08, -0.10);
    float lUpperLegAngle = -1.570796 + LHipAngle;
    float lLowerLegAngle = lUpperLegAngle + LKneeAngle;
    float2 lKnee = limbEnd(lHip, lUpperLegAngle, legLen);

    float dLegR = min(sdLimb(p, rHip, rUpperLegAngle, 0.025, legLen),
                      sdLimb(p, rKnee, rLowerLegAngle, 0.025, legLen));
    float dLegL = min(sdLimb(p, lHip, lUpperLegAngle, 0.025, legLen),
                      sdLimb(p, lKnee, lLowerLegAngle, 0.025, legLen));
    float dLeg = min(dLegR, dLegL);
    float4 legLayer = float4(SkinColor.rgb, SkinColor.a * (1.0 - smoothstep(0.0, aa, dLeg)));
    outColor = h_blend(legLayer, outColor);
    
    // --- Layer 3: Socks ---
    float2 rSockStart = limbEnd(rKnee, rLowerLegAngle, 0.07);
    float dSockR = sdLimb(p, rSockStart, rLowerLegAngle, 0.027, 0.11);
    float2 rSockP = rot2D(p - rKnee, -rLowerLegAngle);
    float rSockCut = abs(rSockP.x - 0.125) - 0.055;
    dSockR = max(dSockR, rSockCut);
    
    float2 lSockStart = limbEnd(lKnee, lLowerLegAngle, 0.07);
    float dSockL = sdLimb(p, lSockStart, lLowerLegAngle, 0.027, 0.11);
    float2 lSockP = rot2D(p - lKnee, -lLowerLegAngle);
    float lSockCut = abs(lSockP.x - 0.125) - 0.055;
    dSockL = max(dSockL, lSockCut);
    
    float dSock = min(dSockR, dSockL);
    float4 sockLayer = float4(SockColor.rgb, SockColor.a * (1.0 - smoothstep(0.0, aa, dSock)));
    outColor = h_blend(sockLayer, outColor);
    
    // --- Layer 4: Shoes ---
    float dShoeBaseR = nm_sdSegment(rSockP, float2(0.19, -0.03), float2(0.19, 0.05)) - 0.025;
    dShoeBaseR = max(dShoeBaseR, rSockP.x - 0.205);
    float dShoeBumpR = nm_sdCircle(rSockP - float2(0.18, 0.0), 0.025);
    float dShoeR = min(dShoeBaseR, dShoeBumpR);

    float dShoeBaseL = nm_sdSegment(lSockP, float2(0.19, -0.05), float2(0.19, 0.03)) - 0.025;
    dShoeBaseL = max(dShoeBaseL, lSockP.x - 0.205);
    float dShoeBumpL = nm_sdCircle(lSockP - float2(0.18, 0.0), 0.025);
    float dShoeL = min(dShoeBaseL, dShoeBumpL);
    
    float dShoe = min(dShoeR, dShoeL);
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
    float2 vTR = float2(0.13, 0.02);
    float2 vTL = float2(-0.13, 0.02);
    float2 vBL = float2(-0.19, -0.20);
    float2 vBR = float2(0.19, -0.20);
    float dSkirt = nm_sdConvexPoly4(p, vTR, vTL, vBL, vBR) - 0.01;
    float4 skirtLayer = float4(SkirtColor.rgb, SkirtColor.a * (1.0 - smoothstep(0.0, aa, dSkirt)));
    outColor = h_blend(skirtLayer, outColor);
    
    // --- Layer 8: Arms (Skin) ---
    // Right Arm Kinematics
    float2 rShoulder = float2(0.13, 0.10);
    float rUpperAngle = -1.297676 + (RShoulderAngle - 1.5708);
    float rLowerAngle = rUpperAngle + RElbowAngle;
    float armLen = 0.1298;
    float2 rElbow = limbEnd(rShoulder, rUpperAngle, armLen);
    float2 rHandPos = limbEnd(rElbow, rLowerAngle, armLen);
    
    // Left Arm Kinematics
    float2 lShoulder = float2(-0.13, 0.10);
    float lUpperAngle = -1.843916 + (LShoulderAngle + 1.5708);
    float lLowerAngle = lUpperAngle + LElbowAngle;
    float2 lElbow = limbEnd(lShoulder, lUpperAngle, armLen);
    float2 lHandPos = limbEnd(lElbow, lLowerAngle, armLen);

    float dArmR = min(sdLimb(p, rShoulder, rUpperAngle, 0.025, armLen),
                      sdLimb(p, rElbow, rLowerAngle, 0.025, armLen));
    float dArmL = min(sdLimb(p, lShoulder, lUpperAngle, 0.025, armLen),
                      sdLimb(p, lElbow, lLowerAngle, 0.025, armLen));
                      
    float rHandDelta = rLowerAngle - (-1.297676);
    float2 rThumbVec = rot2D(float2(-0.02, 0.01), rHandDelta);
    float dThumbR = nm_sdSegment(p, rHandPos, rHandPos + rThumbVec) - 0.012;
    float dHandR = nm_sdCircle(p - rHandPos, 0.035);
    
    float lHandDelta = lLowerAngle - (-1.843916);
    float2 lThumbVec = rot2D(float2(0.02, 0.01), lHandDelta);
    float dThumbL = nm_sdSegment(p, lHandPos, lHandPos + lThumbVec) - 0.012;
    float dHandL = nm_sdCircle(p - lHandPos, 0.035);
    
    float dArmTotal = min(min(dArmR, min(dHandR, dThumbR)), 
                          min(dArmL, min(dHandL, dThumbL)));
    float4 armLayer = float4(SkinColor.rgb, SkinColor.a * (1.0 - smoothstep(0.0, aa, dArmTotal)));
    outColor = h_blend(armLayer, outColor);
    
    // --- Layer 9: Sleeves (Shirt) ---
    float dSleeveR = sdLimb(p, rShoulder, rUpperAngle, 0.035, 0.08);
    float dSleeveL = sdLimb(p, lShoulder, lUpperAngle, 0.035, 0.08);
    float dSleeve = min(dSleeveR, dSleeveL);
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
    float dMouth = max(dMouthArc, p.y - 0.28);
    float dFaceDark = min(dEyes, min(dEyebrow, dMouth));
    float4 faceDarkLayer = float4(HairColor.rgb, HairColor.a * (1.0 - smoothstep(0.0, aa, dFaceDark)));
    outColor = h_blend(faceDarkLayer, outColor);
    
    // Nose
    float dNose = nm_sdSegment(p, float2(0.0, 0.29), float2(0.0, 0.28)) - 0.003;
    float4 noseLayer = float4(SkinShadowColor.rgb, SkinShadowColor.a * (1.0 - smoothstep(0.0, aa, dNose)));
    outColor = h_blend(noseLayer, outColor);
}
