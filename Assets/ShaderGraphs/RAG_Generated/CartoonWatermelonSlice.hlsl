#ifndef PI
#define PI 3.14159265359
#endif

float2 watermelon_rotate(float2 p, float angle) {
    float c = cos(angle);
    float s = sin(angle);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

float sdPie(float2 p, float2 c, float r) {
    p.x = abs(p.x);
    float l = length(p);
    float m = length(p - c * clamp(dot(p, c), 0.0, r));
    return max(l - r, m * sign(c.y * p.x - c.x * p.y));
}

float sdBezier(float2 pos, float2 A, float2 B, float2 C) {
    float2 a = B - A;
    float2 b = A - 2.0*B + C;
    float2 c = a * 2.0;
    float2 d = A - pos;

    float kk = 1.0 / max(dot(b,b), 1e-8);
    float kx = kk * dot(a,b);
    float ky = kk * (2.0*dot(a,a)+dot(d,b)) / 3.0;
    float kz = kk * dot(d,a);

    float res = 0.0;
    float p = ky - kx*kx;
    float p3 = p*p*p;
    float q = kx*(2.0*kx*kx - 3.0*ky) + kz;
    float h = q*q + 4.0*p3;

    if(h >= 0.0) {
        h = sqrt(h);
        float2 x = (float2(h, -h) - q) / 2.0;
        float2 uv = sign(x)*pow(abs(x), float2(1.0/3.0, 1.0/3.0));
        float t = clamp(uv.x+uv.y-kx, 0.0, 1.0);
        float2 q0 = d + (c + b*t)*t;
        res = dot(q0,q0);
    } else {
        float z = sqrt(-p);
        float v = acos(clamp(q/(p*z*2.0), -1.0, 1.0)) / 3.0;
        float m = cos(v);
        float n = sin(v)*1.732050808;
        float3 t = clamp(float3(m+m, -n-m, n-m)*z-kx, 0.0, 1.0);
        float2 q0 = d + (c + b*t.x)*t.x;
        float2 q1 = d + (c + b*t.y)*t.y;
        res = min(dot(q0,q0), dot(q1,q1));
    }
    return sqrt(res);
}

float sdBezierSafe(float2 pos, float2 A, float2 B, float2 C) {
    float2 b = A - 2.0*B + C;
    if (dot(b,b) < 1e-4) {
        float2 pa = pos - A, ba = C - A;
        float h = clamp(dot(pa, ba)/max(dot(ba,ba), 1e-8), 0.0, 1.0);
        return length(pa - ba*h);
    }
    return sdBezier(pos, A, B, C);
}

float sdCapsule(float2 p, float2 a, float2 b, float r) {
    float2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba)/max(dot(ba, ba), 1e-8), 0.0, 1.0);
    return length(pa - ba*h) - r;
}

float sdStar_Function(float2 p, float r, float rInner, float n) {
    n = max(2.0, n);
    float an = PI / n;
    float sector = 2.0 * an;
    float angle = atan2(p.x, p.y);
    float id = floor(angle / sector + 0.5);
    float a = angle - id * sector;
    a = abs(a);
    float len = length(p);
    float2 p_wedge = float2(sin(a), cos(a)) * len;
    float2 v1 = float2(0.0, r);
    float2 v2 = float2(sin(an), cos(an)) * rInner;
    float2 pa = p_wedge - v1;
    float2 ba = v2 - v1;
    float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-8), 0.0, 1.0);
    float2 dVec = pa - ba * h;
    float2 normal = float2(-ba.y, ba.x);
    float s = dot(pa, normal);
    return length(dVec) * sign(s);
}

float4 blend_over(float4 src, float4 dst) {
    float a = src.a + dst.a * (1.0 - src.a);
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-8);
    return float4(c, a);
}

void CartoonWatermelonSlice_float(
    float2 UV,
    float SliceRadius,
    float SliceAngle,
    float BottomCurvature,
    float SkinThick,
    float WhiteThick,
    float4 SeedParams,
    float4 FaceParams,
    float4 HandParams,
    float4 WandParams,
    float4 StarParams,
    float OutlineThick,
    float4 ColorBody,
    float4 ColorSkin,
    float4 ColorWhite,
    float4 ColorSeed,
    float4 ColorFace,
    float4 ColorOutline,
    float4 ColorWand,
    float4 ColorStar,
    out float4 outColor
) {
    float2 p = UV - 0.5;
    float2 wp = p;
    wp.y *= max(0.01, BottomCurvature);
    
    float aa = fwidth(p.x);
    if(aa < 0.0001) aa = 0.002;
    aa *= 1.5;
    
    float sliceAngClamp = clamp(SliceAngle, 0.1, 1.57079);
    float2 sliceC = float2(sin(sliceAngClamp), cos(sliceAngClamp));
    float dBody = sdPie(float2(wp.x, -wp.y), sliceC, SliceRadius);
    dBody *= min(1.0, 1.0 / max(0.01, BottomCurvature));
    
    float bodyFill = 1.0 - smoothstep(-aa, aa, dBody);
    float bodyOutline = 1.0 - smoothstep(-aa, aa, dBody - OutlineThick);
    
    float distToCenter = length(wp);
    float3 sliceColor = ColorSkin.rgb;
    float inWhite = 1.0 - smoothstep(-aa, aa, distToCenter - (SliceRadius - SkinThick));
    sliceColor = lerp(sliceColor, ColorWhite.rgb, inWhite);
    float inRed = 1.0 - smoothstep(-aa, aa, distToCenter - (SliceRadius - SkinThick - WhiteThick));
    sliceColor = lerp(sliceColor, ColorBody.rgb, inRed);
    
    float4 finalColor = float4(0.0, 0.0, 0.0, 0.0);
    
    float handDist = HandParams.w;
    float handY = HandParams.z;
    float2 hA = float2(handDist, handY);
    float2 hC = float2(handDist + HandParams.x, handY + HandParams.y);
    
    float2 wandPos = hC;
    float2 wandDir = float2(sin(WandParams.y), cos(WandParams.y));
    float2 stickStart = wandPos - wandDir * WandParams.x * clamp(WandParams.w, 0.0, 1.0);
    float2 stickEnd = wandPos + wandDir * WandParams.x * (1.0 - clamp(WandParams.w, 0.0, 1.0));
    float dWand = sdCapsule(p, stickStart, stickEnd, WandParams.z);
    float wandFill = 1.0 - smoothstep(-aa, aa, dWand);
    float wandOut = 1.0 - smoothstep(-aa, aa, dWand - OutlineThick);
    finalColor = blend_over(float4(ColorOutline.rgb, wandOut), finalColor);
    finalColor = blend_over(float4(ColorWand.rgb, wandFill), finalColor);
    
    float2 starP = watermelon_rotate(p - stickEnd, WandParams.y);
    float rOuter = max(0.001, StarParams.x - StarParams.y);
    float rInner = max(0.001, StarParams.x * 0.4 - StarParams.y);
    float dStar = sdStar_Function(starP, rOuter, rInner, 5.0) - StarParams.y;
    float starFill = 1.0 - smoothstep(-aa, aa, dStar);
    float starOut = 1.0 - smoothstep(-aa, aa, dStar - OutlineThick);
    finalColor = blend_over(float4(ColorOutline.rgb, starOut), finalColor);
    finalColor = blend_over(float4(ColorStar.rgb, starFill), finalColor);
    
    finalColor = blend_over(float4(ColorOutline.rgb, bodyOutline), finalColor);
    finalColor = blend_over(float4(sliceColor, bodyFill), finalColor);
    
    float dSeeds = 100.0;
    float numSeeds = SeedParams.x;
    float seedSize = SeedParams.y;
    float seedDens = SeedParams.z;
    float seedRadius = SliceRadius - SkinThick - WhiteThick - seedSize * 2.5;
    if (seedRadius > 0.0 && numSeeds > 0.0) {
        float maxAng = sliceAngClamp * 0.8 * seedDens;
        [unroll(12)]
        for(int i = 0; i < 12; i++) {
            if(float(i) >= numSeeds) break;
            float t = numSeeds > 1.5 ? float(i) / (numSeeds - 1.0) : 0.5;
            float a = lerp(-maxAng, maxAng, t);
            float2 sPos = float2(sin(a), -cos(a)) * seedRadius;
            sPos.y /= max(0.01, BottomCurvature);
            float2 sLocal = watermelon_rotate(p - sPos, a);
            float d = length(float2(sLocal.x * 1.5, sLocal.y)) - seedSize;
            dSeeds = min(dSeeds, d);
        }
    }
    float seedFill = (1.0 - smoothstep(-aa, aa, dSeeds)) * bodyFill;
    finalColor = blend_over(float4(ColorSeed.rgb, seedFill), finalColor);
    
    float2 hB = float2(handDist + HandParams.x * 0.5, handY + HandParams.y * 1.5);
    float dRightHand = sdBezierSafe(p, hA, hB, hC) - OutlineThick * 0.5;
    float2 hA_l = float2(-handDist, handY);
    float2 hC_l = float2(-handDist - HandParams.x, handY + HandParams.y);
    float2 hB_l = float2(-handDist - HandParams.x * 0.5, handY + HandParams.y * 1.5);
    float dLeftHand = sdBezierSafe(p, hA_l, hB_l, hC_l) - OutlineThick * 0.5;
    float dHands = min(dRightHand, dLeftHand);
    float handsFill = 1.0 - smoothstep(-aa, aa, dHands);
    finalColor = blend_over(float4(ColorOutline.rgb, handsFill), finalColor);
    
    float faceY = -SliceRadius * 0.4;
    float2 ep = p - float2(0.0, faceY);
    ep.x = abs(ep.x) - FaceParams.y;
    float dEyes = length(ep) - FaceParams.x;
    float2 mp_pos = p - float2(0.0, faceY - 0.05);
    float dMouth = sdBezierSafe(mp_pos, float2(-FaceParams.z, FaceParams.w), float2(0.0, -FaceParams.w), float2(FaceParams.z, FaceParams.w)) - OutlineThick * 0.4;
    float dFace = min(dEyes, dMouth);
    float faceMask = 1.0 - smoothstep(-aa, aa, dFace);
    finalColor = blend_over(float4(ColorFace.rgb, faceMask), finalColor);
    
    float2 stepP = starP - float2(0.0, StarParams.z * 1.8);
    stepP.x = abs(stepP.x) - StarParams.z * 1.5;
    float dStarEyes = length(stepP) - StarParams.z;
    float2 smp = starP - float2(0.0, -StarParams.z * 1.5);
    float dStarMouth = sdBezierSafe(smp, float2(-StarParams.z*2.0, StarParams.w), float2(0.0, -StarParams.w), float2(StarParams.z*2.0, StarParams.w)) - OutlineThick * 0.3;
    float dSFace = min(dStarEyes, dStarMouth);
    float sFaceMask = 1.0 - smoothstep(-aa, aa, dSFace);
    finalColor = blend_over(float4(ColorFace.rgb, sFaceMask), finalColor);
    
    outColor = finalColor;
}