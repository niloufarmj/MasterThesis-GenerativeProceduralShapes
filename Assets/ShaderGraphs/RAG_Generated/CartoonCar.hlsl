#ifndef CARTOON_CAR_SDF
#define CARTOON_CAR_SDF

// --- Helpers ---
inline float sdBox(float2 p, float2 b) {
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

inline float sdRoundBox(float2 p, float2 b, float r) {
    return sdBox(p, b - r) - r;
}

inline float sdCircle(float2 p, float r) {
    return length(p) - r;
}

// Alpha compositing: Source Over Destination
inline float4 car_over(float4 src, float4 dst) {
    float a = src.a + dst.a * (1.0 - src.a);
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-8);
    return float4(c, a);
}

// --- Main Function ---
void CartoonCar_float(
    float2 UV,
    float2 Center,
    float Scale,
    float4 BodyColor,
    float4 WindowColor,
    float4 TireColor,
    float4 RimColor,
    float4 DetailColor,
    float4 HeadlightColor,
    float4 TaillightColor,
    float BodyWidth,
    float BodyHeight,
    float CabinWidth,
    float CabinHeight,
    float WheelRadius,
    float WheelSpacing,
    out float4 outColor
) {
    // 1) Space mapping
    float2 p = UV - Center;
    p /= max(Scale, 0.0001);
    
    // Analytic anti-aliasing width
    float aa = fwidth(p.x);
    if (aa < 0.0001) aa = 0.001;
    
    // 2) Relative Dimensions & Positions
    float BodyOffsetY = -BodyHeight * 0.2;
    float2 CabinOffset = float2(-BodyWidth * 0.05, BodyOffsetY + BodyHeight * 0.5 + CabinHeight * 0.5 - BodyHeight * 0.15);
    
    float BodyRadius = min(0.08, min(BodyWidth, BodyHeight) * 0.5);
    float CabinRadius = min(0.08, min(CabinWidth, CabinHeight) * 0.5);
    
    float WheelY = BodyOffsetY - BodyHeight * 0.4;
    float2 w1 = float2(-WheelSpacing * 0.5, WheelY); // Rear wheel
    float2 w2 = float2(WheelSpacing * 0.5, WheelY);  // Front wheel
    float WheelWellRadius = WheelRadius + max(0.01, WheelRadius * 0.2);
    float RimRadius = WheelRadius * 0.4;
    
    // 3) Base Body & Cabin SDF
    float dLower = sdRoundBox(p - float2(0.0, BodyOffsetY), float2(BodyWidth * 0.5, BodyHeight * 0.5), BodyRadius);
    float dCabin = sdRoundBox(p - CabinOffset, float2(CabinWidth * 0.5, CabinHeight * 0.5), CabinRadius);
    float dBodyRaw = min(dLower, dCabin); // Smooth union of lower body and cabin
    
    // Subtract Wheel Wells (creates cutouts in the body)
    float dWell1 = sdCircle(p - w1, WheelWellRadius);
    float dWell2 = sdCircle(p - w2, WheelWellRadius);
    float dWells = min(dWell1, dWell2);
    float dBody = max(dBodyRaw, -dWells);
    
    // 4) Wheels SDF
    float dTires = min(sdCircle(p - w1, WheelRadius), sdCircle(p - w2, WheelRadius));
    float dRims = min(sdCircle(p - w1, RimRadius), sdCircle(p - w2, RimRadius));
    
    // 5) Windows SDF
    float winW = CabinWidth * 0.2;
    float winH = CabinHeight * 0.35;
    float dWinRear = sdRoundBox(p - (CabinOffset + float2(-winW - CabinWidth * 0.05, CabinHeight * 0.05)), float2(winW, winH), CabinRadius * 0.5);
    float dWinFront = sdRoundBox(p - (CabinOffset + float2(winW + CabinWidth * 0.05, CabinHeight * 0.05)), float2(winW, winH), CabinRadius * 0.5);
    float dWindows = min(dWinRear, dWinFront);
    
    // 6) Details SDF (Door, Handle, Lights)
    float doorHalfW = BodyWidth * 0.15;
    float doorHalfH = BodyHeight * 0.55;
    float2 doorPos = float2(CabinOffset.x, BodyOffsetY + BodyHeight * 0.1);
    float dDoorRaw = sdRoundBox(p - doorPos, float2(doorHalfW, doorHalfH), BodyRadius * 0.8);
    float strokeThickness = max(0.003, min(BodyWidth, BodyHeight) * 0.015);
    float dDoorStroke = abs(dDoorRaw) - strokeThickness;
    // Clip door outline to stay strictly inside the main body
    float dDoor = max(dDoorStroke, dBodyRaw + 0.01);
    
    float2 handlePos = doorPos + float2(-doorHalfW * 0.6, doorHalfH * 0.4);
    float dHandle = sdRoundBox(p - handlePos, float2(BodyWidth * 0.04, BodyHeight * 0.03), BodyHeight * 0.03);
    float dDetails = min(dDoor, dHandle);
    
    float2 headlightPos = float2(BodyWidth * 0.45, BodyOffsetY + BodyHeight * 0.2);
    float dHeadlight = sdRoundBox(p - headlightPos, float2(BodyWidth * 0.02, BodyHeight * 0.15), BodyWidth * 0.02);
    
    float2 taillightPos = float2(-BodyWidth * 0.45, BodyOffsetY + BodyHeight * 0.25);
    float dTaillight = sdRoundBox(p - taillightPos, float2(BodyWidth * 0.015, BodyHeight * 0.18), BodyWidth * 0.015);
    
    // 7) Mask Generation
    float tireMask = 1.0 - smoothstep(-aa, aa, dTires);
    float rimMask = 1.0 - smoothstep(-aa, aa, dRims);
    float bodyMask = 1.0 - smoothstep(-aa, aa, dBody);
    float windowMask = 1.0 - smoothstep(-aa, aa, dWindows);
    float detailMask = 1.0 - smoothstep(-aa, aa, dDetails);
    float headlightMask = 1.0 - smoothstep(-aa, aa, dHeadlight);
    float taillightMask = 1.0 - smoothstep(-aa, aa, dTaillight);
    
    // 8) Layering Colors
    float4 layerTire = float4(TireColor.rgb, saturate(TireColor.a) * tireMask);
    float4 layerRim = float4(RimColor.rgb, saturate(RimColor.a) * rimMask);
    float4 layerBody = float4(BodyColor.rgb, saturate(BodyColor.a) * bodyMask);
    float4 layerWindow = float4(WindowColor.rgb, saturate(WindowColor.a) * windowMask);
    float4 layerDetail = float4(DetailColor.rgb, saturate(DetailColor.a) * detailMask);
    float4 layerHeadlight = float4(HeadlightColor.rgb, saturate(HeadlightColor.a) * headlightMask);
    float4 layerTaillight = float4(TaillightColor.rgb, saturate(TaillightColor.a) * taillightMask);
    
    // 9) Composition (Painter's Algorithm: Back to Front)
    float4 comp = float4(0.0, 0.0, 0.0, 0.0);
    comp = car_over(layerTire, comp);      // Draw wheels first
    comp = car_over(layerRim, comp);       // Draw rims over wheels
    comp = car_over(layerBody, comp);      // Draw body (cutouts reveal wheels)
    comp = car_over(layerWindow, comp);    // Draw windows over body
    comp = car_over(layerDetail, comp);    // Draw doors/handles over body
    comp = car_over(layerHeadlight, comp); // Draw front light over body
    comp = car_over(layerTaillight, comp); // Draw back light over body
    
    outColor = comp;
}
#endif