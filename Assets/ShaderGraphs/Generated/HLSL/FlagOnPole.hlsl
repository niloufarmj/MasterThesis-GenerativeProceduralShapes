#ifndef PI
#define PI 3.14159265359
#endif

// Helper: Signed Distance to a Box
float nm_sdBox(float2 p, float2 b) {
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// Helper: Alpha Blend (Source Over Destination)
// Returns Straight RGB and Alpha
float4 nm_blend(float4 src, float4 dst) {
    float finalAlpha = src.a + dst.a * (1.0 - src.a);
    float3 finalRGB = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(finalAlpha, 1e-6);
    return float4(finalRGB, finalAlpha);
}

// USER REQUEST: A small flag on a pole with a wavy flag shape, adjustable size/pole height/flag width.
void FlagOnPole_float(float2 UV, float2 Center, float PoleHeight, float PoleWidth, float2 FlagSize, float WaveFreq, float WaveAmp, float WavePhase, float4 PoleColor, float4 FlagColor, out float4 outColor) {
    // PLAN:
    // 1. Center coordinates at the base of the pole (UV - Center).
    // 2. Define Pole SDF as a vertical box rising from the center.
    // 3. Define Flag SDF as a box attached to the top-right of the pole.
    // 4. Apply sine-wave domain distortion to the Flag SDF for the wavy effect.
    // 5. Compute AA masks and blend Pole over Flag.

    float2 p = UV - Center;

    // --- Pole SDF ---
    // Pole is centered at x=0, extends from y=0 to y=PoleHeight
    float2 poleHalf = float2(PoleWidth * 0.5, PoleHeight * 0.5);
    float2 poleCenter = float2(0.0, PoleHeight * 0.5);
    float dPole = nm_sdBox(p - poleCenter, poleHalf);

    // --- Flag SDF ---
    // Flag attached to right side of pole (x > PoleWidth/2)
    // Flag top aligned with pole top (y = PoleHeight)
    float flagW = FlagSize.x;
    float flagH = FlagSize.y;
    float2 flagCenterBase = float2((PoleWidth * 0.5) + (flagW * 0.5), PoleHeight - (flagH * 0.5));
    
    // Apply Wavy Distortion to Flag Domain
    float2 pFlag = p;
    // Calculate relative X coordinate along the flag (0.0 at attachment point)
    float xRel = pFlag.x - (PoleWidth * 0.5);
    // Ramp up wave amplitude away from the pole so it stays attached
    float waveRamp = smoothstep(0.0, flagW * 0.5, xRel);
    float wave = sin(xRel * WaveFreq - WavePhase) * WaveAmp * waveRamp;
    pFlag.y -= wave;

    float dFlag = nm_sdBox(pFlag - flagCenterBase, float2(flagW * 0.5, flagH * 0.5));

    // --- Rendering ---
    float aa = fwidth(length(p));
    // AA Masks (0.0 = transparent, 1.0 = opaque)
    float poleMask = 1.0 - smoothstep(-aa, aa, dPole);
    float flagMask = 1.0 - smoothstep(-aa, aa, dFlag);

    // Colors with coverage alpha
    float4 srcPole = float4(PoleColor.rgb, PoleColor.a * poleMask);
    float4 dstFlag = float4(FlagColor.rgb, FlagColor.a * flagMask);

    // Composite: Pole draws OVER Flag
    float4 res = nm_blend(srcPole, dstFlag);

    // Final Output (Premultiplied Alpha: RGB * Alpha, Alpha)
    outColor = float4(res.rgb * res.a, res.a);
}