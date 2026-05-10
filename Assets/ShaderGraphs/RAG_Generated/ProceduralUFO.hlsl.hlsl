#ifndef PI
#define PI 3.14159265359
#endif

// --- Helpers ---

// SDF for Ellipse with gradient correction for even outline thickness
float ufo_sdEllipse(float2 p, float2 ab) {
    float2 e = p / max(ab, 0.0001);
    float len = length(e);
    if(len == 0.0) return -min(ab.x, ab.y);
    float f = len - 1.0;
    float2 grad = e / (ab * len);
    return f / length(grad);
}

// SDF for Line Segment (Capsule base)
float ufo_sdSegment(float2 p, float2 a, float2 b) {
    float2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}

// Alpha blending (Source Over Destination)
float4 ufo_over(float4 src, float4 dst) {
    float a = src.a + dst.a * (1.0 - src.a);
    // Pre-multiply alpha internally for correct straight-RGB blending
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-6);
    return float4(c, a);
}

// Helper to draw an outlined shape cleanly
void ufo_DrawLayer(inout float4 bg, float d, float outlineW, float4 colFill, float4 colOut, float aa) {
    // 1. Draw outer outline
    float mOut  = 1.0 - smoothstep(-aa, aa, d - outlineW);
    float4 outLayer = float4(colOut.rgb, saturate(colOut.a) * mOut);
    bg = ufo_over(outLayer, bg);
    
    // 2. Draw inner fill
    float mFill = 1.0 - smoothstep(-aa, aa, d);
    float4 fillLayer = float4(colFill.rgb, saturate(colFill.a) * mFill);
    bg = ufo_over(fillLayer, bg);
}

// Flame 3-color gradient generator
float4 ufo_GetFlameColor(float t, float4 c1, float4 c2, float4 c3) {
    if (t < 0.5) return lerp(c1, c2, t * 2.0);
    return lerp(c2, c3, (t - 0.5) * 2.0);
}

// --- Main Shader Function ---
void ProceduralUFO_float(
    float2 UV,
    float Tilt,
    float OutlineWidth,
    float DomeWidth,
    float DomeHeight,
    float BodyWidth,
    float BodyHeight,
    float AlienSize,
    float AntennaLength,
    float AntennaTipRadius,
    float WindowRadius,
    float WindowCount,
    float FlameSize,
    float FlameZigzag,
    float FlameLayers,
    float FlameLayerSpacing,
    float4 ColorOutline,
    float4 ColorDome,
    float4 ColorBody,
    float4 ColorAlien,
    float4 ColorFace,
    float4 ColorWindow,
    float4 ColorFlame1,
    float4 ColorFlame2,
    float4 ColorFlame3,
    out float4 outColor
) {
    // Center Coordinates
    float2 p = UV - 0.5;
    
    // Apply Global Tilt (Rotate Coordinates)
    float c_rot = cos(-Tilt);
    float s_rot = sin(-Tilt);
    p = float2(p.x * c_rot - p.y * s_rot, p.x * s_rot + p.y * c_rot);

    // Anti-aliasing width
    float aa = length(fwidth(p)) * 1.5;
    aa = max(aa, 0.001);
    
    // Background initialization (Transparent)
    float4 bg = float4(0.0, 0.0, 0.0, 0.0);

    // --------------------------------------------------------
    // 1. FLAME (Back Layer)
    // --------------------------------------------------------
    float2 pF = p - float2(0.0, -0.15);
    pF.x -= pF.y * 0.4; // Simulate wind/motion bend to the left
    float angleF = atan2(pF.x, -pF.y); // Angle: 0 is straight down
    
    // Generate jagged tips that only apply to the bottom half
    float waveF = cos(angleF * FlameZigzag);
    float maskF = smoothstep(0.05, -0.25, pF.y);
    float rF = FlameSize * (1.0 + waveF * 0.3 * maskF);
    float dFlameOuter = length(pF) - rF;

    // Draw Flame Outline
    float mFOut = 1.0 - smoothstep(-aa, aa, dFlameOuter - OutlineWidth);
    bg = ufo_over(float4(ColorOutline.rgb, ColorOutline.a * mFOut), bg);

    // Draw Flame Fill Layers
    int numLayers = clamp((int)FlameLayers, 1, 10);
    for(int j = 0; j < 10; j++) {
        if (j >= numLayers) break;
        float offset = j * FlameLayerSpacing;
        float dF = dFlameOuter + offset;
        float mF = 1.0 - smoothstep(-aa, aa, dF);
        
        float t = numLayers > 1 ? (float)j / (float)(numLayers - 1) : 0.0;
        float4 cLayer = ufo_GetFlameColor(t, ColorFlame1, ColorFlame2, ColorFlame3);
        bg = ufo_over(float4(cLayer.rgb, saturate(cLayer.a) * mF), bg);
    }

    // --------------------------------------------------------
    // 2. DOME (Middle-Back Layer)
    // --------------------------------------------------------
    float dDome = ufo_sdEllipse(p - float2(0.0, 0.02), float2(DomeWidth, DomeHeight));
    // Cut the bottom of the dome so it doesn't protrude under the UFO body
    dDome = max(dDome, -(p.y + 0.02)); 
    ufo_DrawLayer(bg, dDome, OutlineWidth, ColorDome, ColorOutline, aa);

    // --------------------------------------------------------
    // 3. ALIEN BODY (Middle Layer)
    // --------------------------------------------------------
    float dHead = ufo_sdEllipse(p - float2(0.0, 0.02), float2(AlienSize, AlienSize * 0.8));
    
    float antStartY = 0.02 + AlienSize * 0.6;
    float antEndY = antStartY + AntennaLength;
    float dAnt1 = ufo_sdSegment(p, float2(AlienSize * 0.3, antStartY), float2(AlienSize * 0.8, antEndY)) - 0.005;
    float dAnt2 = ufo_sdSegment(p, float2(-AlienSize * 0.3, antStartY), float2(-AlienSize * 0.8, antEndY)) - 0.005;
    float dAntBall1 = length(p - float2(AlienSize * 0.8, antEndY)) - AntennaTipRadius;
    float dAntBall2 = length(p - float2(-AlienSize * 0.8, antEndY)) - AntennaTipRadius;
    
    // Merge head, antennae stalks, and balls into a single smooth distance field
    float dAlien = min(dHead, min(min(dAnt1, dAnt2), min(dAntBall1, dAntBall2)));
    dAlien = max(dAlien, -(p.y + 0.02)); // Cut bottom to fit behind UFO base
    ufo_DrawLayer(bg, dAlien, OutlineWidth, ColorAlien, ColorOutline, aa);

    // --------------------------------------------------------
    // 4. ALIEN FACE (Front of Alien)
    // --------------------------------------------------------
    // Eyes
    float eyeX = AlienSize * 0.4;
    float eyeY = 0.02 + AlienSize * 0.1;
    float dEye1 = length(p - float2(eyeX, eyeY)) - 0.01;
    float dEye2 = length(p - float2(-eyeX, eyeY)) - 0.01;
    float dEyes = min(dEye1, dEye2);
    float mEyes = 1.0 - smoothstep(-aa, aa, dEyes);
    bg = ufo_over(float4(ColorFace.rgb, ColorFace.a * mEyes), bg);

    // Smile
    float2 pSmile = p - float2(0.0, 0.02 - AlienSize * 0.1);
    float dSmileArc = abs(length(pSmile) - 0.015) - 0.004;
    dSmileArc = max(dSmileArc, pSmile.y); // Keep only the bottom arc to form a smile
    float mSmile = 1.0 - smoothstep(-aa, aa, dSmileArc);
    bg = ufo_over(float4(ColorFace.rgb, ColorFace.a * mSmile), bg);

    // Cheeks (Soft Pink Highlights)
    float cheekX = AlienSize * 0.7;
    float cheekY = 0.02 - AlienSize * 0.05;
    float dCheek1 = length(p - float2(cheekX, cheekY)) - 0.008;
    float dCheek2 = length(p - float2(-cheekX, cheekY)) - 0.008;
    float dCheeks = min(dCheek1, dCheek2);
    float mCheeks = 1.0 - smoothstep(-aa, aa, dCheeks);
    float4 colorCheek = float4(1.0, 0.6, 0.7, 0.8);
    bg = ufo_over(float4(colorCheek.rgb, colorCheek.a * mCheeks), bg);

    // --------------------------------------------------------
    // 5. UFO BODY (Front Layer)
    // --------------------------------------------------------
    float dBody = ufo_sdEllipse(p - float2(0.0, -0.05), float2(BodyWidth, BodyHeight));
    ufo_DrawLayer(bg, dBody, OutlineWidth, ColorBody, ColorOutline, aa);

    // --------------------------------------------------------
    // 6. WINDOWS (Topmost Layer)
    // --------------------------------------------------------
    float dWindows = 1e5;
    int numWin = clamp((int)WindowCount, 0, 10);
    for(int i = 0; i < 10; i++) {
        if (i >= numWin) break;
        float span = BodyWidth * 0.6; // Spread across 60% of body width
        float t = numWin > 1 ? (float)i / (float)(numWin - 1) : 0.5;
        float xPos = lerp(-span, span, t);
        float dW = length(p - float2(xPos, -0.05)) - WindowRadius;
        dWindows = min(dWindows, dW);
    }
    ufo_DrawLayer(bg, dWindows, OutlineWidth, ColorWindow, ColorOutline, aa);

    // Output final composite
    outColor = bg;
}
