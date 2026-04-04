#ifndef PI
#define PI 3.14159265359
#endif

#ifndef CARTOON_AVOCADO_HELPERS
#define CARTOON_AVOCADO_HELPERS

float avo_smin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / max(k, 0.0001), 0.0, 1.0);
    return lerp(b, a, h) - k * h * (1.0 - h);
}

float avo_sdCircle(float2 p, float r) {
    return length(p) - r;
}

float avo_sdRoundBox(float2 p, float2 b, float r) {
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - r;
}

float avo_sdSegment(float2 p, float2 a, float2 b) {
    float2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / max(dot(ba, ba), 0.0001), 0.0, 1.0);
    return length(pa - ba * h);
}

float avo_sdArc(float2 p, float2 sc, float ra, float rb) {
    p.x = abs(p.x);
    float k = (sc.y * p.x > sc.x * p.y) ? dot(p, sc) : length(p);
    return sqrt(max(0.0, dot(p, p) + ra * ra - 2.0 * ra * k)) - rb;
}

float2 avo_rot(float2 p, float a) {
    float s = sin(a), c = cos(a);
    return float2(p.x * c - p.y * s, p.x * s + p.y * c);
}

#endif

void CartoonAvocadoLifting_float(
    float2 UV,
    float BodySize,
    float SeedSize,
    float ArmLength,
    float ShadowSize,
    float4 BackgroundColor,
    float4 OutlineColor,
    float4 SkinColor,
    float4 FleshColor,
    float4 SeedColor,
    float4 SeedHighlightColor,
    float4 ShadowColor,
    float4 DumbbellColor,
    out float4 outColor
) {
    // Center UV and apply dynamic overall scaling
    float2 p = (UV - 0.5) / max(BodySize, 0.001);
    
    // Screen-space derivatives for perfect anti-aliasing
    float aa = length(fwidth(p));
    if (aa < 0.0001) aa = 0.002;

    // 1. Shadow (Squished ellipse)
    float dShadow = length((p - float2(0.0, -0.45)) * float2(1.0, 5.0)) - ShadowSize;
    
    // 2. Main Body (Flesh, Skin, Outline)
    float dTop = avo_sdCircle(p - float2(0.0, 0.15), 0.12);
    float dBot = avo_sdCircle(p - float2(0.0, -0.08), 0.21);
    float dFlesh = avo_smin(dTop, dBot, 0.15);
    float dSkin = dFlesh - 0.02;
    float dOutline = dSkin - 0.01;
    
    // 3. Limbs
    float armL = ArmLength;
    
    // Left Arm
    float2 L_P0 = float2(-0.24, -0.02);
    float2 L_P1 = float2(-0.24 - 0.06 * armL, -0.1);
    float2 L_P2 = float2(-0.24 - 0.11 * armL, 0.08);
    float dArmL = avo_smin(avo_sdSegment(p, L_P0, L_P1), avo_sdSegment(p, L_P1, L_P2), 0.04);
    
    // Right Arm
    float2 R_P0 = float2(0.24, -0.02);
    float2 R_P1 = float2(0.24 + 0.06 * armL, -0.1);
    float2 R_P2 = float2(0.24 + 0.11 * armL, 0.08);
    float dArmR = avo_smin(avo_sdSegment(p, R_P0, R_P1), avo_sdSegment(p, R_P1, R_P2), 0.04);
    
    // Left Leg
    float2 LL_P0 = float2(-0.06, -0.31);
    float2 LL_P1 = float2(-0.09, -0.44);
    float2 LL_P2 = float2(-0.12, -0.44);
    float dLegL = avo_smin(avo_sdSegment(p, LL_P0, LL_P1), avo_sdSegment(p, LL_P1, LL_P2), 0.02);
    
    // Right Leg
    float2 RL_P0 = float2(0.06, -0.31);
    float2 RL_P1 = float2(0.09, -0.44);
    float2 RL_P2 = float2(0.12, -0.44);
    float dLegR = avo_smin(avo_sdSegment(p, RL_P0, RL_P1), avo_sdSegment(p, RL_P1, RL_P2), 0.02);
    
    // Combine Limbs and Outline into one base dark shape
    float dLimbs = min(min(dArmL, dArmR), min(dLegL, dLegR)) - 0.005;
    float dBaseOutline = min(dOutline, dLimbs);
    
    // 4. Dumbbells
    float2 D_L = float2(-0.24 - 0.11 * armL, 0.09);
    float dBarL = avo_sdSegment(p, D_L + float2(-0.06, 0.0), D_L + float2(0.06, 0.0)) - 0.004;
    float dWeightL1 = avo_sdRoundBox(p - (D_L + float2(-0.06, 0.0)), float2(0.012, 0.035), 0.002);
    float dWeightL2 = avo_sdRoundBox(p - (D_L + float2(0.06, 0.0)), float2(0.012, 0.035), 0.002);
    float dDumbbellL = min(dBarL, min(dWeightL1, dWeightL2));
    
    float2 D_R = float2(0.24 + 0.11 * armL, 0.09);
    float dBarR = avo_sdSegment(p, D_R + float2(-0.06, 0.0), D_R + float2(0.06, 0.0)) - 0.004;
    float dWeightR1 = avo_sdRoundBox(p - (D_R + float2(-0.06, 0.0)), float2(0.012, 0.035), 0.002);
    float dWeightR2 = avo_sdRoundBox(p - (D_R + float2(0.06, 0.0)), float2(0.012, 0.035), 0.002);
    float dDumbbellR = min(dBarR, min(dWeightR1, dWeightR2));
    
    float dDumbbell = min(dDumbbellL, dDumbbellR);
    
    // 5. Hands (Fingers overlapping the dumbbell bars)
    float dHandL = min(
        avo_sdSegment(p, D_L + float2(-0.008, -0.01), D_L + float2(-0.008, 0.012)),
        avo_sdSegment(p, D_L + float2(0.008, -0.01), D_L + float2(0.008, 0.012))
    ) - 0.004;
    float dHandR = min(
        avo_sdSegment(p, D_R + float2(-0.008, -0.01), D_R + float2(-0.008, 0.012)),
        avo_sdSegment(p, D_R + float2(0.008, -0.01), D_R + float2(0.008, 0.012))
    ) - 0.004;
    float dHands = min(dHandL, dHandR);
    
    // 6. Seed and Highlights
    float2 seedCenter = float2(0.0, -0.08);
    float dSeed = avo_sdCircle(p - seedCenter, SeedSize);
    
    // Rotate coordinate space by -45 degrees for highlight placement
    float2 hp = avo_rot(p - seedCenter, -0.785398);
    float highlightScale = SeedSize / 0.12;
    float2 scSeed = normalize(float2(0.4794, 0.8776)); // sin(0.5), cos(0.5)
    float dSeedHigh1 = avo_sdArc(hp, scSeed, 0.07 * highlightScale, 0.015 * highlightScale);
    float2 dotOffset = float2(-0.0589, 0.0378) * highlightScale; // Angle -1.0 offset
    float dSeedHigh2 = avo_sdCircle(hp - dotOffset, 0.015 * highlightScale);
    float dSeedHighlight = min(dSeedHigh1, dSeedHigh2);
    
    // 7. Facial Features
    float dEyeWhite = min(avo_sdCircle(p - float2(-0.06, 0.15), 0.02), avo_sdCircle(p - float2(0.06, 0.15), 0.02));
    float dEyePupil = min(avo_sdCircle(p - float2(-0.06, 0.15), 0.01), avo_sdCircle(p - float2(0.06, 0.15), 0.01));
    
    float2 mp = p - float2(0.0, 0.12);
    mp.y = -mp.y; // Flip Y to make the arc smile
    float2 scMouth = normalize(float2(0.7174, 0.6967)); // sin(0.8), cos(0.8)
    float dMouth = avo_sdArc(mp, scMouth, 0.012, 0.003);
    
    // --- Render Composition --- 
    // Start with Background
    float3 finalColor = BackgroundColor.rgb;
    
    // Layer: Shadow
    float mShadow = 1.0 - smoothstep(0.0, 0.02, dShadow);
    finalColor = lerp(finalColor, ShadowColor.rgb, mShadow * ShadowColor.a);
    
    // Layer: Base Outline (Body + Limbs)
    float mBaseOutline = 1.0 - smoothstep(0.0, aa, dBaseOutline);
    finalColor = lerp(finalColor, OutlineColor.rgb, mBaseOutline);
    
    // Layer: Dumbbells (Drawn over outline, but behind skin/flesh visually due to placement)
    float mDumbbell = 1.0 - smoothstep(0.0, aa, dDumbbell);
    finalColor = lerp(finalColor, DumbbellColor.rgb, mDumbbell);
    
    // Layer: Skin
    float mSkin = 1.0 - smoothstep(0.0, aa, dSkin);
    finalColor = lerp(finalColor, SkinColor.rgb, mSkin);
    
    // Layer: Flesh
    float mFlesh = 1.0 - smoothstep(0.0, aa, dFlesh);
    finalColor = lerp(finalColor, FleshColor.rgb, mFlesh);
    
    // Layer: Hands (Fingers wrapping over the dumbbell handles)
    float mHands = 1.0 - smoothstep(0.0, aa, dHands);
    finalColor = lerp(finalColor, OutlineColor.rgb, mHands);
    
    // Layer: Seed
    float mSeed = 1.0 - smoothstep(0.0, aa, dSeed);
    finalColor = lerp(finalColor, SeedColor.rgb, mSeed);
    
    // Layer: Seed Highlight (Masked to ensure it stays strictly inside the seed)
    float mSeedHigh = 1.0 - smoothstep(0.0, aa, dSeedHighlight);
    finalColor = lerp(finalColor, SeedHighlightColor.rgb, mSeedHigh * mSeed);
    
    // Layer: Eyes (White)
    float mEyeWhite = 1.0 - smoothstep(0.0, aa, dEyeWhite);
    finalColor = lerp(finalColor, float3(1.0, 1.0, 1.0), mEyeWhite);
    
    // Layer: Eyes (Pupil)
    float mEyePupil = 1.0 - smoothstep(0.0, aa, dEyePupil);
    finalColor = lerp(finalColor, float3(0.05, 0.05, 0.05), mEyePupil);
    
    // Layer: Mouth
    float mMouth = 1.0 - smoothstep(0.0, aa, dMouth);
    finalColor = lerp(finalColor, float3(0.05, 0.05, 0.05), mMouth);
    
    // Output
    outColor = float4(finalColor, 1.0);
}
