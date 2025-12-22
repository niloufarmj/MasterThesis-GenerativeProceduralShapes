#ifndef PI
#define PI 3.14159265359
#endif

// SDF for a Box (2D)
float sdBox(float2 p, float2 b) {
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

void WavyFlagShape_float(float2 UV, float Size, float PoleHeight, float2 FlagSize, float PoleThickness, float WaveFrequency, float WaveAmplitude, float WaveSpeed, float Time, float4 PoleColor, float4 FlagColor, out float4 outColor) {
    // PLAN:
    // 1) Center UVs and scale by Size parameter.
    // 2) Define SDF for the Pole (vertical box).
    // 3) Define SDF for the Flag (horizontal box) relative to Pole.
    // 4) Apply sine wave distortion to Flag's Y coordinate based on distance from Pole.
    // 5) Combine shapes using smoothstep AA and alpha blending (Pole over Flag).

    // 1. Center and Scale
    float2 p = UV - 0.5;
    p /= max(Size, 0.0001);

    // 2. Pole SDF
    // Position pole slightly left to center the composition
    float poleX = -FlagSize.x * 0.4;
    float2 poleCenter = float2(poleX, 0.0);
    float2 poleExtents = float2(PoleThickness * 0.5, PoleHeight * 0.5);
    float dPole = sdBox(p - poleCenter, poleExtents);

    // 3. Flag Layout
    // Align top of flag with top of pole
    float flagTopY = poleExtents.y;
    float flagCenterY = flagTopY - (FlagSize.y * 0.5);
    // Align left of flag with right of pole
    float flagLeftX = poleX + poleExtents.x;
    float flagCenterX = flagLeftX + (FlagSize.x * 0.5);
    
    float2 pFlag = p - float2(flagCenterX, flagCenterY);

    // 4. Wave Distortion
    // Distance from the attachment point (local left edge is at -width/2)
    float distFromAttach = pFlag.x + (FlagSize.x * 0.5);
    
    // Dampen wave at the pole so it stays attached
    float waveMask = saturate(distFromAttach / max(FlagSize.x * 0.5, 0.001));
    
    // Calculate Sine Wave (moves with Time)
    float wave = sin(distFromAttach * WaveFrequency - Time * WaveSpeed) * WaveAmplitude * waveMask;
    pFlag.y -= wave;
    
    // Calculate Flag SDF
    float dFlag = sdBox(pFlag, FlagSize * 0.5);

    // 5. Anti-aliasing and Composition
    float aa = 0.005;
    float maskPole = smoothstep(aa, -aa, dPole);
    float maskFlag = smoothstep(aa, -aa, dFlag);

    // Effective Alpha (incorporate input color alpha)
    float aPole = maskPole * PoleColor.a;
    float aFlag = maskFlag * FlagColor.a;

    // Blend Pole OVER Flag (Standard Over Operator)
    // FinalAlpha = SrcA + DstA * (1 - SrcA)
    float outAlpha = aPole + aFlag * (1.0 - aPole);
    
    // Premultiplied RGB blending
    float3 outRGB = (PoleColor.rgb * aPole) + (FlagColor.rgb * aFlag * (1.0 - aPole));

    outColor = float4(outRGB, outAlpha);
}