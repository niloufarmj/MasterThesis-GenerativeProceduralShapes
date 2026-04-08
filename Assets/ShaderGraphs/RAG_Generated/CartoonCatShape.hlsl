#ifndef PI
#define PI 3.14159265359
#endif

// --- Helpers ---

float cat_sdRoundBox(float2 p, float2 b, float r) {
    float2 q = abs(p) - b;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

float cat_sdCircle(float2 p, float r) {
    return length(p) - r;
}

float cat_sdIsosceles(float2 p, float2 q) {
    p.x = abs(p.x);
    float2 a = p - q * clamp(dot(p, q) / dot(q, q), 0.0, 1.0);
    float2 b = p - q * float2(clamp(p.x / q.x, 0.0, 1.0), 1.0);
    float s = -sign(q.y);
    float2 d = min(float2(dot(a, a), s * (p.x * q.y - p.y * q.x)),
                   float2(dot(b, b), s * (p.y - q.y)));
    return -sqrt(d.x) * sign(d.y);
}

float cat_sdArc(float2 p, float2 sc, float ra, float rb) {
    p.x = abs(p.x);
    return ((sc.y * p.x > sc.x * p.y) ? length(p - sc * ra) : abs(length(p) - ra)) - rb;
}

float4 cat_over(float4 src, float4 dst) {
    float a = src.a + dst.a * (1.0 - src.a);
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-8);
    return float4(c, a);
}

// --- Main Function ---

void CartoonCatShape_float(
    float2 UV,
    float BodyWidth, float BodyHeight, float BodyRoundness,
    float HeadSize, float HeadRoundness,
    float EarSize, float EarSharpness, float EarSpacing,
    float EyeSize, float EyeSpacing,
    float NoseSize,
    float WhiskerCount, float WhiskerLength, float WhiskerGap,
    float MouthCurvature, float MouthThickness,
    float CollarThickness, float TagRadius,
    float StripeCount, float StripeThickness, float StripeSpacing,
    float FootWidth, float FootHeight, float FootRoundness, float FootSpacing,
    float TailLength, float TailThickness, float TailCurvature,
    float OutlineThickness,
    float4 BodyColor, float4 EarColor, float4 InnerEarColor,
    float4 NoseColor, float4 WhiskerColor, float4 CollarColor,
    float4 TagColor, float4 StripeColor, float4 FootColor,
    float4 OutlineColor,
    out float4 outColor
) {
    float2 p = UV - 0.5;
    
    // --- Layout Computations ---
    float halfBodyW = max(BodyWidth, 0.01) * 0.5;
    float halfBodyH = max(BodyHeight, 0.01) * 0.5;
    float2 bodyCenter = float2(0.0, -0.2);
    
    float halfHeadS = max(HeadSize, 0.01) * 0.5;
    float2 headCenter = bodyCenter + float2(0.0, halfBodyH + halfHeadS - 0.05);
    
    // --- Body ---
    float rBody = clamp(BodyRoundness, 0.0, min(halfBodyW, halfBodyH));
    float dBody = cat_sdRoundBox(p - bodyCenter, float2(halfBodyW - rBody, halfBodyH - rBody), rBody);
    
    // --- Head ---
    float rHead = clamp(HeadRoundness, 0.0, halfHeadS);
    float dHead = cat_sdRoundBox(p - headCenter, float2(halfHeadS - rHead, halfHeadS - rHead), rHead);
    
    // --- Ears ---
    float2 earP = p - headCenter;
    earP.x = abs(earP.x) - EarSpacing;
    earP.y -= halfHeadS - 0.02;
    // Rotate ears outwards
    float cE = cos(0.26); float sE = sin(0.26);
    float2 earPRot = float2(cE * earP.x + sE * earP.y, -sE * earP.x + cE * earP.y);
    float dEarOuter = cat_sdIsosceles(earPRot, float2(EarSize, EarSize * 1.2)) - EarSharpness;
    float dEarInner = cat_sdIsosceles(earPRot - float2(0.0, 0.05), float2(EarSize * 0.6, EarSize * 0.8)) - EarSharpness * 0.5;
    
    // --- Tail ---
    float2 tailP = p - bodyCenter;
    float2 tailCenterOffset = float2(halfBodyW + TailLength - 0.02, -halfBodyH * 0.5);
    tailP -= tailCenterOffset;
    float tailAperture = PI - clamp(TailCurvature, 0.0, PI - 0.1);
    float2 tailSC = float2(sin(tailAperture), cos(tailAperture));
    // Rotate 90 deg CCW to align the C-shape to open towards the body
    float dTail = cat_sdArc(float2(-tailP.y, tailP.x), tailSC, TailLength, TailThickness * 0.5);
    
    // --- Feet ---
    float2 footP = p - bodyCenter;
    footP.y += halfBodyH;
    footP.x = abs(footP.x) - FootSpacing;
    float rFoot = clamp(FootRoundness, 0.0, min(FootWidth, FootHeight) * 0.5);
    float dFeet = cat_sdRoundBox(footP, float2(FootWidth * 0.5 - rFoot, FootHeight * 0.5 - rFoot), rFoot);
    
    // --- Base Silhouette ---
    float dBase = min(min(min(dBody, dHead), dTail), min(dFeet, dEarOuter));
    
    // --- Face Features ---
    float2 eyeP = p - headCenter;
    eyeP.x = abs(eyeP.x) - EyeSpacing;
    eyeP.y -= 0.05;
    float dEyes = cat_sdCircle(eyeP, EyeSize);
    
    float2 noseP = p - headCenter;
    noseP.y += 0.05;
    float dNose = cat_sdCircle(noseP, NoseSize);
    
    float2 mouthP = p - headCenter;
    mouthP.y += 0.1;
    float mouthAperture = PI - clamp(MouthCurvature, 0.0, PI - 0.1);
    float2 mouthSC = float2(sin(mouthAperture), cos(mouthAperture));
    // Flip Y to make it U-shape
    float dMouth = cat_sdArc(float2(mouthP.x, -mouthP.y), mouthSC, 0.03, MouthThickness * 0.5);
    
    // Whiskers
    float2 whiskerP = p - headCenter;
    whiskerP.x = abs(whiskerP.x) - (halfHeadS + WhiskerLength * 0.5 - 0.02);
    whiskerP.y += 0.02;
    float dWhiskers = 999.0;
    int wCount = clamp(round(WhiskerCount), 1, 10);
    float wStartY = -(wCount - 1.0) * WhiskerGap * 0.5;
    for(int i = 0; i < 10; i++) {
        if (i >= wCount) break;
        float wy = wStartY + i * WhiskerGap;
        float d = cat_sdRoundBox(float2(whiskerP.x, whiskerP.y - wy), float2(WhiskerLength * 0.5, 0.005), 0.005);
        dWhiskers = min(dWhiskers, d);
    }
    
    // --- Collar & Tag ---
    float collarY = bodyCenter.y + halfBodyH + 0.01;
    float2 collarP = p - float2(0.0, collarY);
    float rCollar = CollarThickness * 0.2;
    float dCollar = cat_sdRoundBox(collarP, float2(halfHeadS * 0.9 - rCollar, CollarThickness * 0.5 - rCollar), rCollar);
    
    float2 tagP = p - float2(0.0, collarY - CollarThickness * 0.5 - TagRadius);
    float dTag = cat_sdCircle(tagP, TagRadius);
    float dCollarTag = min(dCollar, dTag);
    
    // --- Stripes ---
    float2 stripeP = p - bodyCenter;
    float dStripes = 999.0;
    int sCount = clamp(round(StripeCount), 1, 10);
    float sStartY = -(sCount - 1.0) * StripeSpacing * 0.5;
    for(int j = 0; j < 10; j++) {
        if (j >= sCount) break;
        float sy = sStartY + j * StripeSpacing;
        float d = abs(stripeP.y - sy) - StripeThickness * 0.5;
        dStripes = min(dStripes, d);
    }
    
    // --- Rendering / Composition ---
    float aa = max(fwidth(dBase), 0.0001);
    
    // Masks
    float mBase = 1.0 - smoothstep(0.0, aa, dBase);
    float mEarInner = 1.0 - smoothstep(0.0, aa, dEarInner);
    float mStripes = (1.0 - smoothstep(0.0, aa, dStripes)) * (1.0 - smoothstep(0.0, aa, dBody));
    
    // Determine base fill color
    float4 baseFillColor = BodyColor;
    if (dEarOuter < dBody && dEarOuter < dHead) baseFillColor = EarColor;
    if (dFeet < dBody && dFeet < dTail) baseFillColor = FootColor;
    
    float4 layerBase = float4(baseFillColor.rgb, baseFillColor.a * mBase);
    float4 layerEarInner = float4(InnerEarColor.rgb, InnerEarColor.a * mEarInner);
    float4 layerStripes = float4(StripeColor.rgb, StripeColor.a * mStripes);
    
    // Base Stroke
    float strokeBaseD = abs(dBase) - OutlineThickness * 0.5;
    float mStrokeBase = 1.0 - smoothstep(0.0, aa, strokeBaseD);
    float4 layerStrokeBase = float4(OutlineColor.rgb, OutlineColor.a * mStrokeBase);
    
    // Collar Tag
    float mCollarTag = 1.0 - smoothstep(0.0, aa, dCollarTag);
    float4 cTagColor = (dCollar < dTag) ? CollarColor : TagColor;
    float4 layerCollarTag = float4(cTagColor.rgb, cTagColor.a * mCollarTag);
    
    float strokeCollarTagD = abs(dCollarTag) - OutlineThickness * 0.5;
    float mStrokeCollarTag = 1.0 - smoothstep(0.0, aa, strokeCollarTagD);
    float4 layerStrokeCollarTag = float4(OutlineColor.rgb, OutlineColor.a * mStrokeCollarTag);
    
    // Face
    float mEyes = 1.0 - smoothstep(0.0, aa, dEyes);
    float4 layerEyes = float4(OutlineColor.rgb, OutlineColor.a * mEyes);
    
    float mNose = 1.0 - smoothstep(0.0, aa, dNose);
    float4 layerNose = float4(NoseColor.rgb, NoseColor.a * mNose);
    
    float mMouth = 1.0 - smoothstep(0.0, aa, dMouth);
    float4 layerMouth = float4(OutlineColor.rgb, OutlineColor.a * mMouth);
    
    float mWhiskers = 1.0 - smoothstep(0.0, aa, dWhiskers);
    float4 layerWhiskers = float4(WhiskerColor.rgb, WhiskerColor.a * mWhiskers);
    
    // --- Composite (Back to Front) ---
    float4 outC = float4(0.0, 0.0, 0.0, 0.0);
    
    outC = cat_over(layerBase, outC);
    outC = cat_over(layerStripes, outC);
    outC = cat_over(layerEarInner, outC);
    
    outC = cat_over(layerStrokeBase, outC);
    
    outC = cat_over(layerCollarTag, outC);
    outC = cat_over(layerStrokeCollarTag, outC);
    
    outC = cat_over(layerEyes, outC);
    outC = cat_over(layerNose, outC);
    outC = cat_over(layerMouth, outC);
    outC = cat_over(layerWhiskers, outC);
    
    outColor = outC;
}
