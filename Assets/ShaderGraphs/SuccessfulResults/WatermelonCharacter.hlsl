#ifndef PI
#define PI 3.14159265359
#endif

// Alpha blending (Source Over Destination)
inline float4 blend_Watermelon(float4 src, float4 dst) {
    float outA = src.a + dst.a * (1.0 - src.a);
    float3 outRGB = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(outA, 1e-6);
    return float4(outRGB, outA);
}

// Helper to draw a layer with fill and stroke
inline float4 strokeOver_Watermelon(float4 fillCol, float d, float aa, float strokeW, float4 strokeCol) {
    float maskFill = smoothstep(aa, -aa, d);
    float maskStroke = smoothstep(strokeW + aa, strokeW - aa, abs(d));
    float4 fillLayer = float4(fillCol.rgb, fillCol.a * maskFill);
    float4 strokeLayer = float4(strokeCol.rgb, strokeCol.a * maskStroke);
    return blend_Watermelon(strokeLayer, fillLayer);
}

// Exact 2D distance to quadratic bezier
inline float sdBezier_Watermelon(float2 pos, float2 A, float2 B, float2 C) {    
    float2 a = B - A;
    float2 b = A - 2.0*B + C;
    float2 c = a * 2.0;
    float2 d = A - pos;

    float kk = 1.0 / max(dot(b,b), 1e-6);
    float kx = kk * dot(a,b);
    float ky = kk * (2.0*dot(a,a)+dot(d,b)) / 3.0;
    float kz = kk * dot(d,a);      

    float p = ky - kx*kx;
    float p3 = p*p*p;
    float q = kx*(2.0*kx*kx - 3.0*ky) + kz;
    float h = q*q + 4.0*p3;

    if(h >= 0.0) { 
        h = sqrt(h);
        float2 x = (float2(h, -h) - q) / 2.0;
        float2 uv = sign(x)*pow(abs(x), float2(1.0/3.0, 1.0/3.0));
        float t = clamp(uv.x+uv.y-kx, 0.0, 1.0);
        return length(d + (c + b*t)*t);
    }
    float z = sqrt(max(-p, 0.0));
    float v = acos(clamp(q/(p*z*2.0), -1.0, 1.0)) / 3.0;
    float m = cos(v);
    float n = sin(v)*1.732050808;
    float3 t = clamp(float3(m+m, -n-m, n-m)*z-kx, 0.0, 1.0);
    return min(min(length(d+(c+b*t.x)*t.x), length(d+(c+b*t.y)*t.y)), length(d+(c+b*t.z)*t.z));
}

// Safe curve function that falls back to line segment if curvature is near zero
inline float sdCurve_Watermelon(float2 p, float2 A, float2 B, float2 C) {
    float2 b = A - 2.0*B + C;
    if (dot(b, b) < 1e-4) {
        float2 pa = p - A, ba = C - A;
        float h = clamp(dot(pa, ba)/max(dot(ba, ba), 1e-6), 0.0, 1.0);
        return length(pa - ba * h);
    }
    return sdBezier_Watermelon(p, A, B, C);
}

// Capsule distance
inline float sdCapsule_Watermelon(float2 p, float2 a, float2 b, float r) {
    float2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-6), 0.0, 1.0);
    return length(pa - ba * h) - r;
}

// Circular Sector (Pie) distance
inline float sdPie_Watermelon(float2 p, float2 c, float r) {
    p.x = abs(p.x);
    float l = length(p);
    float m = length(p - c * clamp(dot(p, c), 0.0, r));
    return max(l - r, m * sign(c.y * p.x - c.x * p.y));
}

// Star distance
inline float sdStar_Function_Watermelon(float2 p, float r, float rInner, float n) {
    n = max(2.0, n);
    float an = PI / n;
    float sector = 2.0 * an;
    float angle = atan2(p.x, p.y);
    float id = floor(angle / sector + 0.5);
    float a = abs(angle - id * sector);
    float len = length(p);
    float2 p_wedge = float2(sin(a), cos(a)) * len;
    float2 v1 = float2(0.0, r);
    float2 v2 = float2(sin(an), cos(an)) * rInner;
    float2 pa = p_wedge - v1;
    float2 ba = v2 - v1;
    float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-6), 0.0, 1.0);
    float s = dot(pa, float2(-ba.y, ba.x));
    return length(pa - ba * h) * sign(s);
}

void WatermelonCharacter_float(
    float2 UV,
    float4 SliceParams,      // x: Angle, y: Radius, z: BottomCurvature
    float4 ThicknessParams,  // x: SkinThick, y: WhiteThick, z: OutlineThick
    float4 WatermelonSkinColor,
    float4 WatermelonWhiteColor,
    float4 WatermelonRedColor,
    float4 SeedParams,       // x: Size, y: Count
    float4 SeedColor,
    float4 EyeParams,        // x: Size, y: Distance
    float4 MouthParams,      // x: Width, y: Curve, z: Thickness
    float4 FaceColor,
    float4 ArmParams,        // x: YPos, y: Length, z: Curve, w: Thickness
    float4 ArmColor,
    float4 WandStickParams,  // x: YOffsetRatio, y: Length, z: Angle, w: Thickness
    float4 WandStickColor,
    float4 StarParams,       // x: Size, y: Points, z: InnerRatio, w: CornerRad
    float4 StarColor,
    float4 StarFaceParams,   // x: EyeSize, y: EyeDist, z: MouthWidth, w: MouthCurve
    float4 StarFaceColor,
    float4 OutlineColor,
    out float4 outColor
) {
    float2 p = UV - 0.5;
    float aa = fwidth(length(p));
    if (aa < 0.0001) aa = 0.003;

    float outlineThick = ThicknessParams.z;
    float bodyCurvature = max(0.01, SliceParams.z);
    float bodyRadius = SliceParams.y;
    float bodyShiftY = bodyRadius * bodyCurvature * 0.5;

    // Constrain angle up to half circle max (PI/2)
    float sliceAngle = clamp(SliceParams.x, 0.01, PI * 0.5);

    // 1. Arm coordinates
    float armY = ArmParams.x;
    float depthFromVertex = bodyShiftY - armY;
    float halfWidth = (depthFromVertex / bodyCurvature) * tan(sliceAngle);
    float attachX = halfWidth - 0.02; 
    float armLen = ArmParams.y;
    float armCurve = ArmParams.z;
    float armThick = ArmParams.w;

    float2 rArmA = float2(attachX, armY);
    float2 rArmB = float2(attachX + armLen*0.5, armY - armCurve);
    float2 rArmC = float2(attachX + armLen, armY);
    float dRightArm = sdCurve_Watermelon(p, rArmA, rArmB, rArmC) - armThick;

    float2 lArmA = float2(-attachX, armY);
    float2 lArmB = float2(-attachX - armLen*0.5, armY - armCurve);
    float2 lArmC = float2(-attachX - armLen, armY);
    float dLeftArm = sdCurve_Watermelon(p, lArmA, lArmB, lArmC) - armThick;

    // 2. Wand coordinates
    float2 wandCenter = rArmC;
    float wAngle = WandStickParams.z;
    float2 wDir = float2(cos(wAngle), sin(wAngle));
    float2 wandPt1 = wandCenter - wDir * (WandStickParams.y * WandStickParams.x);
    float2 wandPt2 = wandCenter + wDir * (WandStickParams.y * (1.0 - WandStickParams.x));
    float dWandStick = sdCapsule_Watermelon(p, wandPt1, wandPt2, WandStickParams.w);

    // 3. Body coordinates
    float2 pPie = p;
    pPie.y = bodyShiftY - p.y;
    pPie.y /= bodyCurvature;
    float dBody = sdPie_Watermelon(pPie, float2(sin(sliceAngle), cos(sliceAngle)), bodyRadius);
    dBody *= min(1.0, bodyCurvature);

    // 4. Seeds
    float dSeeds = 1e5;
    float seedSize = SeedParams.x;
    int numSeeds = clamp(int(SeedParams.y), 0, 10);
    for(int i = 0; i < 10; i++) {
        if (i >= numSeeds) break;
        float fi = float(i) + 1.0;
        float h1 = frac(sin(fi * 12.9898) * 43758.5453);
        float h2 = frac(sin(fi * 78.233) * 43758.5453);
        float r = bodyRadius * (0.15 + 0.6 * h1);
        float a = sliceAngle * (-0.75 + 1.5 * h2);
        
        float2 sPosPie = float2(sin(a)*r, cos(a)*r);
        float2 sPos = float2(sPosPie.x, bodyShiftY - sPosPie.y * bodyCurvature);
        
        float2 sp = p - sPos;
        float2 dir = sPos - float2(0.0, bodyShiftY);
        float lenSq = dot(dir, dir);
        if(lenSq > 1e-6) dir *= rsqrt(lenSq); else dir = float2(0.0, -1.0);
        
        float sa = atan2(dir.y, dir.x) + PI*0.5;
        float c_s = cos(sa), s_s = sin(sa);
        sp = float2(c_s*sp.x + s_s*sp.y, -s_s*sp.x + c_s*sp.y);
        
        float dS = sdCapsule_Watermelon(sp, float2(0.0, -seedSize*0.5), float2(0.0, seedSize*0.5), seedSize*0.4);
        dSeeds = min(dSeeds, dS);
    }

    // 5. Watermelon Face coordinates
    float2 eyePos = float2(EyeParams.y * 0.5, 0.0);
    float dEyes = length(float2(abs(p.x) - eyePos.x, p.y)) - EyeParams.x;

    float mouthY = -0.05;
    float mouthW = MouthParams.x;
    float mouthCurve = MouthParams.y;
    float2 mouthA = float2(-mouthW*0.5, mouthY);
    float2 mouthB = float2(0.0, mouthY - mouthCurve);
    float2 mouthC = float2(mouthW*0.5, mouthY);
    float dMouth = sdCurve_Watermelon(p, mouthA, mouthB, mouthC) - MouthParams.z;

    // 6. Star coordinates
    float starAngle = wAngle - PI * 0.5;
    float2 pStar = p - wandPt2;
    float cS = cos(starAngle), sS = sin(starAngle);
    pStar = float2(cS*pStar.x + sS*pStar.y, -sS*pStar.x + cS*pStar.y);
    float dStar = sdStar_Function_Watermelon(pStar, StarParams.x, StarParams.x * StarParams.z, StarParams.y) - StarParams.w;

    // 7. Star Face coordinates
    float2 sEyePos = float2(StarFaceParams.y * 0.5, 0.01);
    float dStarEyes = length(float2(abs(pStar.x) - sEyePos.x, pStar.y - sEyePos.y)) - StarFaceParams.x;
    float sMouthW = StarFaceParams.z;
    float sMouthCurve = StarFaceParams.w;
    float sMouthY = -0.015;
    float2 sMouthA = float2(-sMouthW*0.5, sMouthY);
    float2 sMouthB = float2(0.0, sMouthY - sMouthCurve);
    float2 sMouthC = float2(sMouthW*0.5, sMouthY);
    float dStarMouth = sdCurve_Watermelon(pStar, sMouthA, sMouthB, sMouthC) - 0.002;

    // --- COMPOSITING --- //
    float4 current = float4(0, 0, 0, 0);

    // Draw Arms (Behind Body)
    current = blend_Watermelon(strokeOver_Watermelon(ArmColor, dLeftArm, aa, outlineThick, OutlineColor), current);
    current = blend_Watermelon(strokeOver_Watermelon(ArmColor, dRightArm, aa, outlineThick, OutlineColor), current);

    // Draw Wand Stick
    current = blend_Watermelon(strokeOver_Watermelon(WandStickColor, dWandStick, aa, outlineThick, OutlineColor), current);

    // Draw Body Fill & Outline
    float maskSkin = smoothstep(aa, -aa, dBody);
    float maskWhite = smoothstep(aa, -aa, dBody + ThicknessParams.x);
    float maskRed = smoothstep(aa, -aa, dBody + ThicknessParams.x + ThicknessParams.y);
    
    float3 bodyRGB = lerp(WatermelonSkinColor.rgb, WatermelonWhiteColor.rgb, maskWhite);
    bodyRGB = lerp(bodyRGB, WatermelonRedColor.rgb, maskRed);
    float4 layerBodyFill = float4(bodyRGB, WatermelonSkinColor.a * maskSkin);
    
    float maskBodyStroke = smoothstep(outlineThick + aa, outlineThick - aa, abs(dBody));
    float4 layerBodyStroke = float4(OutlineColor.rgb, OutlineColor.a * maskBodyStroke);
    float4 layerBodyTotal = blend_Watermelon(layerBodyStroke, layerBodyFill);
    current = blend_Watermelon(layerBodyTotal, current);

    // Draw Seeds (Clipped to Red)
    float maskSeeds = smoothstep(aa, -aa, dSeeds) * maskRed;
    float maskSeedStroke = smoothstep(outlineThick*0.5 + aa, outlineThick*0.5 - aa, abs(dSeeds)) * maskRed;
    float4 layerSeeds = blend_Watermelon(float4(OutlineColor.rgb, OutlineColor.a * maskSeedStroke), float4(SeedColor.rgb, SeedColor.a * maskSeeds));
    current = blend_Watermelon(layerSeeds, current);

    // Draw Face (Eyes and Mouth)
    current = blend_Watermelon(strokeOver_Watermelon(FaceColor, dEyes, aa, outlineThick*0.5, OutlineColor), current);
    current = blend_Watermelon(strokeOver_Watermelon(FaceColor, dMouth, aa, outlineThick*0.5, OutlineColor), current);

    // Draw Star Base
    current = blend_Watermelon(strokeOver_Watermelon(StarColor, dStar, aa, outlineThick, OutlineColor), current);

    // Draw Star Face
    current = blend_Watermelon(strokeOver_Watermelon(StarFaceColor, dStarEyes, aa, outlineThick*0.5, OutlineColor), current);
    current = blend_Watermelon(strokeOver_Watermelon(StarFaceColor, dStarMouth, aa, outlineThick*0.5, OutlineColor), current);

    outColor = current;
}

// ------------------------------------------------------------------------
//  Visual Result (High-level, parameter-invariant description)
// ------------------------------------------------------------------------
//  This function produces a **2D cartoonish watermelon slice character**. The main structure includes a watermelon slice with a red body, a green skin at the bottom edge, and a white layer separating them. The slice is less than a semicircle, with editable curvature at the bottom. The character's face comprises two eyes and a mouth with an adjustable curvature, allowing for different expressions. Seeds are scattered on the red portion, each with editable size and density. Two line-based arms are attached, with the right arm holding a wand topped by a star, which also features a face with eyes and a mouth. A consistent, flat outline accentuates the whole figure, with editable colors and thickness.
// ------------------------------------------------------------------------
