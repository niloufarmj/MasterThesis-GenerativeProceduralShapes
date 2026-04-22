#ifndef PI
#define PI 3.14159265359
#endif

// SDF for a circle
float sdCircleMannequin(float2 p, float r) {
    return length(p) - r;
}

// SDF for an axis-aligned box
float sdBoxMannequin(float2 p, float2 b) {
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// SDF for an arbitrarily oriented rectangular segment with flat ends
float sdRectSegMannequin(float2 p, float2 a, float2 b, float width) {
    float2 ba = b - a;
    float l = length(ba);
    float2 dir = ba / (l + 1e-5);
    float2 pa = p - a;
    
    // Project pa onto the direction vector and its perpendicular
    float x = dot(pa, dir);
    float y = dot(pa, float2(-dir.y, dir.x));
    
    // Translate to center of the box in local space
    float2 center = float2(l * 0.5, 0.0);
    
    // Standard box SDF logic in local space
    float2 d = abs(float2(x, y) - center) - float2(l * 0.5, width * 0.5);
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

void MannequinFigure_float(
    float2 UV,
    float2 Center,
    float Scale,
    float HeadRadius,
    float NeckWidth,
    float NeckHeight,
    float TorsoWidth,
    float TorsoHeight,
    float PelvisWidth,
    float PelvisHeight,
    float ShoulderSpread,
    float HipSpread,
    float JointRadius,
    float UpperArmWidth,
    float UpperArmLength,
    float LowerArmWidth,
    float LowerArmLength,
    float HandWidth,
    float HandLength,
    float UpperLegWidth,
    float UpperLegLength,
    float LowerLegWidth,
    float LowerLegLength,
    float FootWidth,
    float FootLength,
    float RShoulderAngle,
    float RElbowAngle,
    float LShoulderAngle,
    float LElbowAngle,
    float RHipAngle,
    float RKneeAngle,
    float LHipAngle,
    float LKneeAngle,
    float4 FillColor,
    float4 StrokeColor,
    float StrokeThickness,
    out float4 outColor
) {
    // Ensure scale isn't zero to avoid division by zero
    float safeScale = max(Scale, 0.0001);
    
    // Map UVs so that Center is at (0,0) and space is appropriately scaled
    float2 p = (UV - Center) / safeScale;
    
    float d = 1e9;
    
    // ======================================
    // CORE BODY (Torso, Neck, Head, Pelvis)
    // ======================================
    
    // Torso (centered at origin)
    d = min(d, sdBoxMannequin(p, float2(TorsoWidth * 0.5, TorsoHeight * 0.5)));
    
    // Neck
    float2 neckC = float2(0.0, TorsoHeight * 0.5 + NeckHeight * 0.5);
    d = min(d, sdBoxMannequin(p - neckC, float2(NeckWidth * 0.5, NeckHeight * 0.5)));
    
    // Head
    float2 headC = float2(0.0, TorsoHeight * 0.5 + NeckHeight + HeadRadius);
    d = min(d, sdCircleMannequin(p - headC, HeadRadius));
    
    // Pelvis
    float2 pelvisC = float2(0.0, -TorsoHeight * 0.5 - PelvisHeight * 0.5);
    d = min(d, sdBoxMannequin(p - pelvisC, float2(PelvisWidth * 0.5, PelvisHeight * 0.5)));
    
    
    // ======================================
    // ARMS
    // ======================================
    
    // Right Arm (defaults to pointing Right -> Angle 0)
    float2 rShoulderP = float2(ShoulderSpread, TorsoHeight * 0.5);
    d = min(d, sdCircleMannequin(p - rShoulderP, JointRadius));
    
    float rArmA1 = RShoulderAngle;
    float2 rArmDir1 = float2(cos(rArmA1), sin(rArmA1));
    float2 rElbowP = rShoulderP + rArmDir1 * UpperArmLength;
    d = min(d, sdRectSegMannequin(p, rShoulderP, rElbowP, UpperArmWidth));
    d = min(d, sdCircleMannequin(p - rElbowP, JointRadius));
    
    float rArmA2 = rArmA1 + RElbowAngle;
    float2 rArmDir2 = float2(cos(rArmA2), sin(rArmA2));
    float2 rWristP = rElbowP + rArmDir2 * LowerArmLength;
    d = min(d, sdRectSegMannequin(p, rElbowP, rWristP, LowerArmWidth));
    d = min(d, sdRectSegMannequin(p, rWristP, rWristP + rArmDir2 * HandLength, HandWidth));
    
    // Left Arm (defaults to pointing Left -> Angle PI)
    float2 lShoulderP = float2(-ShoulderSpread, TorsoHeight * 0.5);
    d = min(d, sdCircleMannequin(p - lShoulderP, JointRadius));
    
    float lArmA1 = PI + LShoulderAngle;
    float2 lArmDir1 = float2(cos(lArmA1), sin(lArmA1));
    float2 lElbowP = lShoulderP + lArmDir1 * UpperArmLength;
    d = min(d, sdRectSegMannequin(p, lShoulderP, lElbowP, UpperArmWidth));
    d = min(d, sdCircleMannequin(p - lElbowP, JointRadius));
    
    float lArmA2 = lArmA1 + LElbowAngle;
    float2 lArmDir2 = float2(cos(lArmA2), sin(lArmA2));
    float2 lWristP = lElbowP + lArmDir2 * LowerArmLength;
    d = min(d, sdRectSegMannequin(p, lElbowP, lWristP, LowerArmWidth));
    d = min(d, sdRectSegMannequin(p, lWristP, lWristP + lArmDir2 * HandLength, HandWidth));
    
    
    // ======================================
    // LEGS
    // ======================================
    
    // Right Leg (defaults to pointing Down -> Angle -PI/2)
    float2 rHipP = float2(HipSpread, -TorsoHeight * 0.5 - PelvisHeight);
    d = min(d, sdCircleMannequin(p - rHipP, JointRadius));
    
    float rLegA1 = -PI * 0.5 + RHipAngle;
    float2 rLegDir1 = float2(cos(rLegA1), sin(rLegA1));
    float2 rKneeP = rHipP + rLegDir1 * UpperLegLength;
    d = min(d, sdRectSegMannequin(p, rHipP, rKneeP, UpperLegWidth));
    d = min(d, sdCircleMannequin(p - rKneeP, JointRadius));
    
    float rLegA2 = rLegA1 + RKneeAngle;
    float2 rLegDir2 = float2(cos(rLegA2), sin(rLegA2));
    float2 rAnkleP = rKneeP + rLegDir2 * LowerLegLength;
    d = min(d, sdRectSegMannequin(p, rKneeP, rAnkleP, LowerLegWidth));
    d = min(d, sdCircleMannequin(p - rAnkleP, JointRadius));
    
    // Right Foot (defaults to pointing outward/Right -> Leg Angle + PI/2)
    float rFootA = rLegA2 + PI * 0.5;
    float2 rFootDir = float2(cos(rFootA), sin(rFootA));
    d = min(d, sdRectSegMannequin(p, rAnkleP, rAnkleP + rFootDir * FootLength, FootWidth));
    
    // Left Leg (defaults to pointing Down -> Angle -PI/2)
    float2 lHipP = float2(-HipSpread, -TorsoHeight * 0.5 - PelvisHeight);
    d = min(d, sdCircleMannequin(p - lHipP, JointRadius));
    
    float lLegA1 = -PI * 0.5 + LHipAngle;
    float2 lLegDir1 = float2(cos(lLegA1), sin(lLegA1));
    float2 lKneeP = lHipP + lLegDir1 * UpperLegLength;
    d = min(d, sdRectSegMannequin(p, lHipP, lKneeP, UpperLegWidth));
    d = min(d, sdCircleMannequin(p - lKneeP, JointRadius));
    
    float lLegA2 = lLegA1 + LKneeAngle;
    float2 lLegDir2 = float2(cos(lLegA2), sin(lLegA2));
    float2 lAnkleP = lKneeP + lLegDir2 * LowerLegLength;
    d = min(d, sdRectSegMannequin(p, lKneeP, lAnkleP, LowerLegWidth));
    d = min(d, sdCircleMannequin(p - lAnkleP, JointRadius));
    
    // Left Foot (defaults to pointing outward/Left -> Leg Angle - PI/2)
    float lFootA = lLegA2 - PI * 0.5;
    float2 lFootDir = float2(cos(lFootA), sin(lFootA));
    d = min(d, sdRectSegMannequin(p, lAnkleP, lAnkleP + lFootDir * FootLength, FootWidth));
    
    
    // ======================================
    // RENDERING & ANTI-ALIASING
    // ======================================
    
    // Map calculated local distance back to UV space dimensions for consistent stroke width
    float distUV = d * safeScale;
    
    // Dynamic anti-aliasing based on screen derivatives
    float aa = fwidth(distUV);
    aa = max(aa, 1e-5);
    
    // Masks for solid fill and unified outer stroke ring
    float fillMask = 1.0 - smoothstep(-aa, aa, distUV);
    float strokeMask = smoothstep(-aa, aa, distUV) - smoothstep(StrokeThickness - aa, StrokeThickness + aa, distUV);
    
    // Apply coloring via additive composition (masks are mutually exclusive geographically)
    float4 cFill = float4(FillColor.rgb, FillColor.a * fillMask);
    float4 cStroke = float4(StrokeColor.rgb, StrokeColor.a * strokeMask);
    
    outColor = cFill + cStroke;
}
