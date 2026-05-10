#ifndef PI
#define PI 3.14159265359
#endif

#ifndef NM_OVER
#define NM_OVER
inline float4 nm_over(float4 src, float4 dst) {
    float a = src.a + dst.a * (1.0 - src.a);
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-8);
    return float4(c, a);
}
#endif

inline float2 rotate2D(float2 p, float angle) {
    float c = cos(angle), s = sin(angle);
    return float2(c * p.x + s * p.y, -s * p.x + c * p.y);
}

// Pseudo-distance for superellipse (for perfectly scaled outlines)
inline float sdSuperEllipse(float2 p, float2 size, float n) {
    float2 q = abs(p);
    float sx = max(size.x, 0.001);
    float sy = max(size.y, 0.001);
    float xW = q.x / sx;
    float yH = q.y / sy;
    float f = pow(max(xW, 0.0001), n) + pow(max(yH, 0.0001), n) - 1.0;
    float dfdx = (n / sx) * pow(max(xW, 0.0001), max(n - 1.0, 0.0));
    float dfdy = (n / sy) * pow(max(yH, 0.0001), max(n - 1.0, 0.0));
    float gradLen = sqrt(dfdx * dfdx + dfdy * dfdy);
    return (gradLen > 0.0001) ? (f / gradLen) : -min(sx, sy);
}

// Tapered flame SDF with sine displacement
inline float sdTaperedFlame(float2 pos, float w, float h, float jag, float dens) {
    float taper = smoothstep(-h, 0.0, pos.y); 
    float curW = max(w * taper, 0.001);
    float2 pb = pos;
    pb.y += clamp(-pos.y, 0.0, h);
    float d = length(pb) - curW;
    float wave = sin(pos.x * dens - pos.y * 15.0) * jag * (1.0 - taper);
    return d + wave;
}

// PLAN:
// 1) Transform UV to centered and rotated coordinates.
// 2) Compute Flame layers using sdTaperedFlame.
// 3) Compute Alien Head (tapered capsule) & Face (circles, arcs).
// 4) Compute Antennae (curved lines mapped via symmetry).
// 5) Compute Dome (ellipse intersected with parabolic curve).
// 6) Compute Saucer Base (superellipse) and Lights (domain repetition).
// 7) Combine structural SDFs into a global silhouette.
// 8) Composite layers back-to-front: Outer Stroke -> Flames -> Alien -> Dome -> Saucer -> Lights.

void CartoonUFOWithAlien_float(
    float2 UV,
    float Size,
    float Rotation,
    float2 SaucerSize,
    float SaucerCurve,
    float2 DomeSize,
    float DomeCurve,
    float2 HeadSize,
    float HeadTopRadius,
    float4 FaceParams,
    float4 AntennaParams,
    float AntennaThickness,
    float4 FlameParams,
    float4 LightParams,
    float StrokeWidth,
    float4 StrokeColor,
    float4 SaucerColor,
    float4 DomeColor,
    float4 HeadColor,
    float4 EyeColor,
    float4 BlushColor,
    float4 AntennaColor,
    float4 OuterFlameColor,
    float4 MidFlameColor,
    float4 InnerFlameColor,
    float4 LightColor,
    out float4 outColor
) {
    float2 p = UV - 0.5;
    p = rotate2D(p, Rotation);
    p /= max(Size, 0.001);
    
    float aa = 0.005 / max(Size, 0.001);
    
    // === FLAMES ===
    float2 pf = p - float2(0.0, -SaucerSize.y * 0.8);
    float fw = FlameParams.x, fh = FlameParams.y, fj = FlameParams.z, fd = FlameParams.w;
    float dFlameOuter = sdTaperedFlame(pf, fw, fh, fj, fd);
    float dFlameMid = sdTaperedFlame(pf, fw * 0.7, fh * 0.7, fj * 0.8, fd);
    float dFlameInner = sdTaperedFlame(pf, fw * 0.4, fh * 0.4, fj * 0.5, fd);
    
    // === ALIEN BASE (Head) ===
    float2 ph = p - float2(0.0, DomeSize.y * 0.2); 
    float headH = HeadSize.y;
    float2 phead = ph;
    phead.y -= clamp(phead.y, 0.0, headH);
    float rHead = lerp(HeadSize.x, HeadTopRadius, saturate(ph.y / max(headH, 0.001)));
    float dHead = length(phead) - rHead;
    
    // === ALIEN FACE ===
    float eyeR = FaceParams.x, eyeSpc = FaceParams.y, blushR = FaceParams.z, mouthC = FaceParams.w;
    float2 pLeftEye = ph - float2(-eyeSpc, headH * 0.6);
    float2 pRightEye = ph - float2(eyeSpc, headH * 0.6);
    float dEyes = min(length(pLeftEye), length(pRightEye)) - eyeR;
    
    float2 pLeftBlush = ph - float2(-eyeSpc * 1.5, headH * 0.4);
    float2 pRightBlush = ph - float2(eyeSpc * 1.5, headH * 0.4);
    float dBlush = min(length(pLeftBlush * float2(1.0, 1.5)), length(pRightBlush * float2(1.0, 1.5))) - blushR;
    
    float2 pm = ph - float2(0.0, headH * 0.35);
    float expectedY = mouthC * (pm.x * pm.x);
    float dMouth = abs(pm.y - expectedY) - StrokeWidth * 0.4;
    dMouth = max(dMouth, abs(pm.x) - eyeSpc * 0.8);
    
    // === ANTENNAE ===
    float2 pAntBase = ph - float2(0.0, headH);
    float aLen = AntennaParams.x, aSpc = AntennaParams.y, aCrv = AntennaParams.z, aBulb = AntennaParams.w;
    float2 pA = float2(abs(pAntBase.x), pAntBase.y);
    float tA = clamp(pA.y / max(aLen, 0.001), 0.0, 1.0);
    float expectedAX = sin(tA * PI) * aCrv + tA * aSpc;
    float dStem = length(pA - float2(expectedAX, tA * aLen)) - AntennaThickness;
    float dBulb = length(pA - float2(aSpc, aLen)) - aBulb;
    float dAntennae = min(dStem, dBulb);
    float dAlien = min(dHead, dAntennae);
    
    // === DOME ===
    float dDomeBase = length(p * float2(DomeSize.y / max(DomeSize.x, 0.001), 1.0)) - DomeSize.y;
    float cutLine = p.y - (p.x * p.x * DomeCurve);
    float dDome = max(dDomeBase, -cutLine);
    
    // === SAUCER ===
    float dSaucer = sdSuperEllipse(p, SaucerSize, SaucerCurve);
    
    // === LIGHTS ===
    float dLights = 999.0;
    float lCount = LightParams.x, lRad = LightParams.y, lSpc = LightParams.z, lY = LightParams.w;
    float startX = -(lCount - 1.0) * 0.5 * lSpc;
    for(int i = 0; i < 15; i++) {
        if(float(i) >= lCount) break;
        float lx = startX + float(i) * lSpc;
        float dL = length(p - float2(lx, lY)) - lRad;
        dLights = min(dLights, dL);
    }
    
    // === SILHOUETTE & COMPOSITING ===
    float dShip = min(dSaucer, dDome);
    float dSilhouette = min(dShip, min(dAlien, dFlameOuter));
    
    float4 finalCol = float4(0,0,0,0);
    
    // 1. Thick Outer Stroke
    float mOuterStroke = 1.0 - smoothstep(0.0, aa, dSilhouette - StrokeWidth);
    finalCol = float4(StrokeColor.rgb, StrokeColor.a * mOuterStroke);
    
    // 2. Flames
    float mFO = 1.0 - smoothstep(0.0, aa, dFlameOuter);
    finalCol = nm_over(float4(OuterFlameColor.rgb, OuterFlameColor.a * mFO), finalCol);
    float mFM = 1.0 - smoothstep(0.0, aa, dFlameMid);
    finalCol = nm_over(float4(MidFlameColor.rgb, MidFlameColor.a * mFM), finalCol);
    float mFI = 1.0 - smoothstep(0.0, aa, dFlameInner);
    finalCol = nm_over(float4(InnerFlameColor.rgb, InnerFlameColor.a * mFI), finalCol);
    
    // 3. Alien Body & Inner Stroke
    float mAntennae = 1.0 - smoothstep(0.0, aa, dAntennae);
    finalCol = nm_over(float4(AntennaColor.rgb, AntennaColor.a * mAntennae), finalCol);
    float mHead = 1.0 - smoothstep(0.0, aa, dHead);
    finalCol = nm_over(float4(HeadColor.rgb, HeadColor.a * mHead), finalCol);
    float mAlienStroke = 1.0 - smoothstep(0.0, aa, abs(dAlien) - StrokeWidth * 0.4);
    finalCol = nm_over(float4(StrokeColor.rgb, StrokeColor.a * mAlienStroke), finalCol);
    
    // 4. Face Features
    float mEyes = 1.0 - smoothstep(0.0, aa, dEyes);
    finalCol = nm_over(float4(EyeColor.rgb, EyeColor.a * mEyes), finalCol);
    float mBlush = 1.0 - smoothstep(0.0, aa, dBlush);
    finalCol = nm_over(float4(BlushColor.rgb, BlushColor.a * mBlush), finalCol);
    float mMouth = 1.0 - smoothstep(0.0, aa, dMouth);
    finalCol = nm_over(float4(StrokeColor.rgb, StrokeColor.a * mMouth), finalCol);
    
    // 5. Dome & Inner Stroke
    float mDomeBase = 1.0 - smoothstep(0.0, aa, dDome);
    finalCol = nm_over(float4(DomeColor.rgb, DomeColor.a * mDomeBase), finalCol);
    float mDomeStroke = 1.0 - smoothstep(0.0, aa, abs(dDome) - StrokeWidth * 0.4);
    finalCol = nm_over(float4(StrokeColor.rgb, StrokeColor.a * mDomeStroke), finalCol);
    
    // 6. Saucer & Inner Stroke
    float mSaucerBase = 1.0 - smoothstep(0.0, aa, dSaucer);
    finalCol = nm_over(float4(SaucerColor.rgb, SaucerColor.a * mSaucerBase), finalCol);
    float mSaucerStroke = 1.0 - smoothstep(0.0, aa, abs(dSaucer) - StrokeWidth * 0.4);
    finalCol = nm_over(float4(StrokeColor.rgb, StrokeColor.a * mSaucerStroke), finalCol);
    
    // 7. Lights
    float mLightsBase = 1.0 - smoothstep(0.0, aa, dLights);
    finalCol = nm_over(float4(LightColor.rgb, LightColor.a * mLightsBase), finalCol);
    float mLightsStroke = 1.0 - smoothstep(0.0, aa, abs(dLights) - StrokeWidth * 0.25);
    finalCol = nm_over(float4(StrokeColor.rgb, StrokeColor.a * mLightsStroke), finalCol);
    
    outColor = finalCol;
}