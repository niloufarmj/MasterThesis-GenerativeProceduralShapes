#ifndef PI
#define PI 3.14159265359
#endif

float mnq_sdBox(float2 p, float2 halfSize) {
    float2 d = abs(p) - halfSize;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

float mnq_sdOrientedBox(float2 p, float2 pivot, float angle, float length_box, float width_box) {
    float c_a = cos(angle);
    float s_a = sin(angle);
    float2 center = pivot + float2(c_a, s_a) * (length_box * 0.5);
    float2 localP = p - center;
    float2 rotP = float2(c_a * localP.x + s_a * localP.y, -s_a * localP.x + c_a * localP.y);
    return mnq_sdBox(rotP, float2(length_box * 0.5, width_box * 0.5));
}

void mnq_addShape(float d, inout float dFill, inout float dStroke) {
    dFill = min(dFill, d);
    dStroke = min(dStroke, abs(d));
}

void TechnicalMannequinShape_float(
    float2 UV,
    float2 Center,
    float Scale,
    float HeadRadius,
    float2 NeckSize,
    float2 TorsoSize,
    float2 PelvisSize,
    float ShoulderSpread,
    float HipSpread,
    float JointRadius,
    float2 UpperArmSize,
    float2 LowerArmSize,
    float2 HandSize,
    float2 UpperLegSize,
    float2 LowerLegSize,
    float2 FootSize,
    float LShoulderAngle,
    float RShoulderAngle,
    float LElbowAngle,
    float RElbowAngle,
    float LHipAngle,
    float RHipAngle,
    float LKneeAngle,
    float RKneeAngle,
    float4 FillColor,
    float4 StrokeColor,
    float StrokeThickness,
    out float4 outColor
) {
    float2 p = UV - Center;
    p /= max(Scale, 0.001);

    float dFill = 1e5;
    float dStroke = 1e5;

    // Spine: Torso, Pelvis, Neck, Head
    float dTorso = mnq_sdBox(p, TorsoSize * 0.5);
    mnq_addShape(dTorso, dFill, dStroke);

    float2 pelvisCenter = float2(0.0, -(TorsoSize.y + PelvisSize.y) * 0.5);
    float2 pPelvis = p - pelvisCenter;
    mnq_addShape(mnq_sdBox(pPelvis, PelvisSize * 0.5), dFill, dStroke);

    float2 neckCenter = float2(0.0, (TorsoSize.y + NeckSize.y) * 0.5);
    mnq_addShape(mnq_sdBox(p - neckCenter, NeckSize * 0.5), dFill, dStroke);

    float2 headCenter = neckCenter + float2(0.0, NeckSize.y * 0.5 + HeadRadius);
    mnq_addShape(length(p - headCenter) - HeadRadius, dFill, dStroke);

    // Base Angles
    float rArmBase = 0.0;
    float lArmBase = PI;
    float legBase = -PI / 2.0;

    // Right Arm
    float2 rShoulderPos = float2(ShoulderSpread, TorsoSize.y * 0.5);
    float rArmAngle = rArmBase + RShoulderAngle;
    float2 rElbowPos = rShoulderPos + float2(cos(rArmAngle), sin(rArmAngle)) * UpperArmSize.x;
    float rLowerAngle = rArmAngle + RElbowAngle;
    float2 rHandPivot = rElbowPos + float2(cos(rLowerAngle), sin(rLowerAngle)) * LowerArmSize.x;

    mnq_addShape(length(p - rShoulderPos) - JointRadius, dFill, dStroke);
    mnq_addShape(mnq_sdOrientedBox(p, rShoulderPos, rArmAngle, UpperArmSize.x, UpperArmSize.y), dFill, dStroke);
    mnq_addShape(length(p - rElbowPos) - JointRadius, dFill, dStroke);
    mnq_addShape(mnq_sdOrientedBox(p, rElbowPos, rLowerAngle, LowerArmSize.x, LowerArmSize.y), dFill, dStroke);
    mnq_addShape(mnq_sdOrientedBox(p, rHandPivot, rLowerAngle, HandSize.x, HandSize.y), dFill, dStroke);

    // Left Arm
    float2 lShoulderPos = float2(-ShoulderSpread, TorsoSize.y * 0.5);
    float lArmAngle = lArmBase + LShoulderAngle;
    float2 lElbowPos = lShoulderPos + float2(cos(lArmAngle), sin(lArmAngle)) * UpperArmSize.x;
    float lLowerAngle = lArmAngle + LElbowAngle;
    float2 lHandPivot = lElbowPos + float2(cos(lLowerAngle), sin(lLowerAngle)) * LowerArmSize.x;

    mnq_addShape(length(p - lShoulderPos) - JointRadius, dFill, dStroke);
    mnq_addShape(mnq_sdOrientedBox(p, lShoulderPos, lArmAngle, UpperArmSize.x, UpperArmSize.y), dFill, dStroke);
    mnq_addShape(length(p - lElbowPos) - JointRadius, dFill, dStroke);
    mnq_addShape(mnq_sdOrientedBox(p, lElbowPos, lLowerAngle, LowerArmSize.x, LowerArmSize.y), dFill, dStroke);
    mnq_addShape(mnq_sdOrientedBox(p, lHandPivot, lLowerAngle, HandSize.x, HandSize.y), dFill, dStroke);

    // Right Leg
    float2 rHipPos = pelvisCenter + float2(HipSpread, -PelvisSize.y * 0.5);
    float rLegAngle = legBase + RHipAngle;
    float2 rKneePos = rHipPos + float2(cos(rLegAngle), sin(rLegAngle)) * UpperLegSize.x;
    float rLowerLegAngle = rLegAngle + RKneeAngle;
    float2 rAnklePos = rKneePos + float2(cos(rLowerLegAngle), sin(rLowerLegAngle)) * LowerLegSize.x;
    float rFootAngle = rLowerLegAngle + PI / 2.0;

    mnq_addShape(length(p - rHipPos) - JointRadius, dFill, dStroke);
    mnq_addShape(mnq_sdOrientedBox(p, rHipPos, rLegAngle, UpperLegSize.x, UpperLegSize.y), dFill, dStroke);
    mnq_addShape(length(p - rKneePos) - JointRadius, dFill, dStroke);
    mnq_addShape(mnq_sdOrientedBox(p, rKneePos, rLowerLegAngle, LowerLegSize.x, LowerLegSize.y), dFill, dStroke);
    mnq_addShape(length(p - rAnklePos) - JointRadius, dFill, dStroke);
    mnq_addShape(mnq_sdOrientedBox(p, rAnklePos, rFootAngle, FootSize.x, FootSize.y), dFill, dStroke);

    // Left Leg
    float2 lHipPos = pelvisCenter + float2(-HipSpread, -PelvisSize.y * 0.5);
    float lLegAngle = legBase + LHipAngle;
    float2 lKneePos = lHipPos + float2(cos(lLegAngle), sin(lLegAngle)) * UpperLegSize.x;
    float lLowerLegAngle = lLegAngle + LKneeAngle;
    float2 lAnklePos = lKneePos + float2(cos(lLowerLegAngle), sin(lLowerLegAngle)) * LowerLegSize.x;
    float lFootAngle = lLowerLegAngle - PI / 2.0;

    mnq_addShape(length(p - lHipPos) - JointRadius, dFill, dStroke);
    mnq_addShape(mnq_sdOrientedBox(p, lHipPos, lLegAngle, UpperLegSize.x, UpperLegSize.y), dFill, dStroke);
    mnq_addShape(length(p - lKneePos) - JointRadius, dFill, dStroke);
    mnq_addShape(mnq_sdOrientedBox(p, lKneePos, lLowerLegAngle, LowerLegSize.x, LowerLegSize.y), dFill, dStroke);
    mnq_addShape(length(p - lAnklePos) - JointRadius, dFill, dStroke);
    mnq_addShape(mnq_sdOrientedBox(p, lAnklePos, lFootAngle, FootSize.x, FootSize.y), dFill, dStroke);

    // Anti-aliasing scaling
    float aa = fwidth(p.x) * 1.5;
    if (aa < 0.0001) aa = 0.001;

    // Masks
    float fillMask = 1.0 - smoothstep(-aa, aa, dFill);
    float strokeMask = 1.0 - smoothstep(StrokeThickness * 0.5 - aa, StrokeThickness * 0.5 + aa, dStroke);

    // Alpha Compositing (Stroke over Fill)
    float strokeAlpha = strokeMask * StrokeColor.a;
    float fillAlpha = fillMask * FillColor.a;

    float outA = strokeAlpha + fillAlpha * (1.0 - strokeAlpha);
    float3 outRGB = (StrokeColor.rgb * strokeAlpha + FillColor.rgb * fillAlpha * (1.0 - strokeAlpha)) / max(outA, 1e-6);

    outColor = float4(outRGB, outA);
}
