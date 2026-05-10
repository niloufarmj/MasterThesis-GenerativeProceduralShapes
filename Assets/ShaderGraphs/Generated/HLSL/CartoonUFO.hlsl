// PLAN:
// 1) Translate UVs to center and apply global Rotation.
// 2) Construct layers back-to-front: Flames -> Antennae -> Alien -> Dome -> Saucer -> Lights.
// 3) Use SDFs for all parts: sdRoundBox for Saucer, sdEllipseApprox for Dome, sdCapsule for Alien.
// 4) Apply a consistent drawLayer function to give each shape a customizable, thick outer outline and sharp solid/transparent fill.
// 5) Accumulate colors using standard alpha compositing (nm_over).

#ifndef PI
#define PI 3.14159265359
#endif

// --- Helpers ---

// Straight-alpha over operator
inline float4 nm_over(float4 top, float4 bottom) {
    float a = top.a + bottom.a * (1.0 - top.a);
    float3 c = (top.rgb * top.a + bottom.rgb * bottom.a * (1.0 - top.a)) / max(a, 1e-8);
    return float4(c, a);
}

// Draw a shape with its fill and stroke
inline float4 drawLayer(float d, float4 fillCol, float4 strokeCol, float strokeW, float4 baseCol) {
    float aa = 0.0025; // crisp, consistent anti-aliasing
    float fillMask = smoothstep(aa, -aa, d);
    float totalMask = smoothstep(strokeW + aa, strokeW - aa, d);
    float strokeMask = saturate(totalMask - fillMask);

    float4 outCol = baseCol;
    // Stroke goes over the background
    outCol = nm_over(float4(strokeCol.rgb, strokeCol.a * strokeMask), outCol);
    // Fill goes over the stroke
    outCol = nm_over(float4(fillCol.rgb, fillCol.a * fillMask), outCol);
    return outCol;
}

// Basic SDFs
inline float sdCapsule(float2 p, float2 a, float2 b, float r) {
    float2 pa = p - a, ba = b - a;
    float h = saturate(dot(pa, ba) / dot(ba, ba));
    return length(pa - ba * h) - r;
}

inline float sdRoundBox(float2 p, float2 b, float r) {
    float2 q = abs(p) - b;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

inline float sdEllipseApprox(float2 p, float2 ab) {
    float a = max(ab.x, 1e-8);
    float b = max(ab.y, 1e-8);
    float x = p.x, y = p.y;
    float F = (x * x) / (a * a) + (y * y) / (b * b) - 1.0;
    float gradLen = 2.0 * sqrt((x * x) / (a * a * a * a) + (y * y) / (b * b * b * b));
    return (gradLen > 1e-8) ? (F / gradLen) : -min(a, b);
}

inline float flameDist(float2 p, float w, float h, float jag, float den) {
    float py = -p.y; // flames go downwards (negative Y)
    float taper = max(0.0, 1.0 - py / h);
    float px = abs(p.x) + sin(py * den) * jag * taper;
    float d = max(px - w * taper, py - h);
    return d;
}

// --- Main Function ---
void CartoonUFO_float(
    float2 UV, 
    float Rotation,
    
    float SaucerWidth, float SaucerHeight, float SaucerCurve, float4 SaucerColor,
    float LightCount, float LightRadius, float LightSpacing, float4 LightColor,
    float DomeWidth, float DomeHeight, float DomeBaseCurve, float4 DomeColor,
    
    float AlienHeadHeight, float AlienTopRadius, float4 AlienColor,
    float EyeRadius, float EyeSpacing, float4 EyeColor,
    float BlushRadius, float BlushSpacing, float4 BlushColor,
    float MouthCurve, float MouthWidth, float4 MouthColor,
    float AntLength, float AntThickness, float AntCurve, float AntBulbRadius, float4 AntColor,
    
    float FlameWidth, float FlameHeight, float FlameJaggedness, float FlameDensity,
    float4 FlameOuterColor, float4 FlameMidColor, float4 FlameInnerColor,
    
    float StrokeWidth, float4 StrokeColor,
    out float4 outColor
) {
    // Center UV
    float2 p = UV - 0.5;
    
    // Rotate entire ship
    float c = cos(Rotation);
    float s = sin(Rotation);
    p = float2(c * p.x + s * p.y, -s * p.x + c * p.y);

    float4 col = float4(0, 0, 0, 0);

    // --- 1. Rocket Flames (Back Layer) ---
    float2 pFlame = p - float2(0.0, -SaucerHeight); // start below saucer
    
    float d_flameO = flameDist(pFlame, FlameWidth, FlameHeight, FlameJaggedness, FlameDensity);
    col = drawLayer(d_flameO, FlameOuterColor, StrokeColor, StrokeWidth, col);
    
    float d_flameM = flameDist(pFlame, FlameWidth * 0.7, FlameHeight * 0.7, FlameJaggedness * 0.8, FlameDensity * 1.2);
    col = drawLayer(d_flameM, FlameMidColor, StrokeColor, StrokeWidth, col);
    
    float d_flameI = flameDist(pFlame, FlameWidth * 0.4, FlameHeight * 0.4, FlameJaggedness * 0.5, FlameDensity * 1.5);
    col = drawLayer(d_flameI, FlameInnerColor, StrokeColor, StrokeWidth, col);

    // --- 2. Alien Antennae ---
    float alienBaseY = 0.05;
    float2 antBase = float2(AlienTopRadius * 0.5, alienBaseY + AlienHeadHeight + AlienTopRadius * 0.5);
    float2 pAnt = p;
    pAnt.x = abs(pAnt.x); // Symmetry for two antennae
    float2 pa = pAnt - antBase;
    pa.x -= AntCurve * pa.y * pa.y; // Bend outward
    
    float d_stem = sdCapsule(pa, float2(0, 0), float2(0, AntLength), AntThickness);
    float d_bulb = length(pa - float2(0, AntLength)) - AntBulbRadius;
    float d_ant = min(d_stem, d_bulb);
    col = drawLayer(d_ant, AntColor, StrokeColor, StrokeWidth, col);

    // --- 3. Alien Head ---
    float d_head = sdCapsule(p, float2(0, alienBaseY), float2(0, alienBaseY + AlienHeadHeight), AlienTopRadius);
    col = drawLayer(d_head, AlienColor, StrokeColor, StrokeWidth, col);

    // --- 4. Alien Face (Fill only, no outer stroke) ---
    float aa = 0.0025;
    // Eyes
    float d_eyes = length(float2(abs(p.x) - EyeSpacing, p.y - (alienBaseY + AlienHeadHeight * 0.5 + 0.04))) - EyeRadius;
    col = nm_over(float4(EyeColor.rgb, EyeColor.a * smoothstep(aa, -aa, d_eyes)), col);

    // Blush
    float d_blush = sdEllipseApprox(float2(abs(p.x) - BlushSpacing, p.y - (alienBaseY + AlienHeadHeight * 0.5 + 0.01)), float2(BlushRadius, BlushRadius * 0.5));
    col = nm_over(float4(BlushColor.rgb, BlushColor.a * smoothstep(aa, -aa, d_blush)), col);

    // Mouth
    float2 pMouth = p - float2(0, alienBaseY + AlienHeadHeight * 0.5);
    float mouthYOffset = MouthCurve * pMouth.x * pMouth.x;
    float d_mouth = abs(pMouth.y - mouthYOffset) - 0.003; // thickness
    d_mouth = max(d_mouth, abs(pMouth.x) - MouthWidth);   // bound width
    col = nm_over(float4(MouthColor.rgb, MouthColor.a * smoothstep(aa, -aa, d_mouth)), col);

    // --- 5. Glass Dome (Over Alien) ---
    float d_dome = sdEllipseApprox(p, float2(DomeWidth, DomeHeight));
    // Cut off dome base with optional curvature
    float domeBaseCut = -p.y + DomeBaseCurve * p.x * p.x;
    d_dome = max(d_dome, domeBaseCut);
    col = drawLayer(d_dome, DomeColor, StrokeColor, StrokeWidth, col);

    // --- 6. Saucer Base (Frontmost Main Body) ---
    float2 saucerHalfSize = float2(SaucerWidth, SaucerHeight) - SaucerCurve;
    float d_saucer = sdRoundBox(p, saucerHalfSize, SaucerCurve);
    col = drawLayer(d_saucer, SaucerColor, StrokeColor, StrokeWidth, col);

    // --- 7. Saucer Lights ---
    float d_lights = 1e5;
    float maxL = clamp(floor(LightCount), 1.0, 20.0);
    float halfL = (maxL - 1.0) * 0.5;
    // Unroll limit via max safe loop
    for(float i = -10.0; i <= 10.0; i += 1.0) {
        if (i < -halfL || i > halfL) continue;
        float2 pL = float2(p.x - i * LightSpacing, p.y - (-SaucerHeight * 0.5));
        d_lights = min(d_lights, length(pL) - LightRadius);
    }
    // Render lights slightly smaller strokes to look clean
    col = drawLayer(d_lights, LightColor, StrokeColor, StrokeWidth * 0.5, col);

    outColor = col;
}