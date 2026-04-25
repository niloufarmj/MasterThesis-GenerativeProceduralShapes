#ifndef PI
#define PI 3.14159265359
#endif

// --- Helpers ---

// Alpha compositing (src over dst)
inline float4 nm_over(float4 src, float4 dst)
{
    float a = src.a + dst.a * (1.0 - src.a);
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-8);
    return float4(c, a);
}

// Signed distance to a rounded box
inline float sdRoundBox(float2 p, float2 b, float r)
{
    float2 q = abs(p) - b;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

// Signed distance to a wavy line segment with tapered ends
inline float dWavy(float2 p, float2 a, float2 b, float freq, float amp, float thick)
{
    float2 ba = b - a;
    float2 pa = p - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    
    // Taper the wave at the ends so it connects smoothly
    float envelope = sin(h * PI);
    float wave = sin(h * length(ba) * freq) * amp * envelope;
    
    float2 proj = a + h * ba;
    float2 perp = normalize(float2(-ba.y, ba.x));
    float2 pointOnWave = proj + perp * wave;
    
    // Taper the thickness slightly at the ends for a wispy look
    float t = thick * (0.3 + 0.7 * envelope);
    return length(p - pointOnWave) - t;
}

// Draws a shape with a stroke and composites it over the background
inline float4 layerShape(float d, float4 fillColor, float strokeWidth, float4 bg)
{
    float aa = max(fwidth(d), 0.001);
    
    float alphaFill = 1.0 - smoothstep(-aa, aa, d);
    float alphaStrokeTotal = 1.0 - smoothstep(-aa, aa, d - strokeWidth);
    
    // Hollow out the stroke so it sits purely behind/around the fill
    float alphaStrokeOnly = saturate(alphaStrokeTotal - alphaFill);
    
    // Outline is black, but scales with the layer's overall opacity (useful for steam)
    float4 strokeColor = float4(0.0, 0.0, 0.0, 1.0);
    float layerOpacity = fillColor.a;
    
    float4 strokeLayer = float4(strokeColor.rgb, strokeColor.a * alphaStrokeOnly * layerOpacity);
    bg = nm_over(strokeLayer, bg);
    
    float4 fillLayer = float4(fillColor.rgb, alphaFill * layerOpacity);
    bg = nm_over(fillLayer, bg);
    
    return bg;
}

// --- Main Function ---
void CartoonRamenBowl_float(
    float2 UV,
    float BowlWidth,
    float BowlHeight,
    float4 BowlColor,
    float NoodleCount,
    float WaveAmplitude,
    float NoodleThickness,
    float4 NoodleColor,
    float4 EggWhiteColor,
    float4 EggYolkColor,
    float4 LeafColor,
    float SteamOpacity,
    float SteamCurvature,
    float StrokeThickness,
    out float4 outColor)
{
    // PLAN:
    // 1) Recenter UV to (-0.5, 0.5) so (0,0) is the middle of the bowl rim.
    // 2) Draw elements back-to-front using distance fields.
    // 3) Steam curves (wispy lines at the top).
    // 4) Noodles (wavy lines clipped to a dome shape above the bowl).
    // 5) Toppings (Egg, Leaves) placed inside the noodle dome.
    // 6) Bowl body and flared rim (drawn last to cover the lower halves of noodles/toppings, creating the illusion of being inside).

    float2 p = UV - 0.5;
    float4 bg = float4(0.0, 0.0, 0.0, 0.0);
    
    // --- 1. STEAM ---
    float dSteam = 1e9;
    float2 st1 = float2(0.0, 0.2); float2 en1 = float2(0.0, 0.65);
    dSteam = min(dSteam, dWavy(p, st1, en1, 15.0, SteamCurvature, 0.015));
    
    float2 st2 = float2(-0.15, 0.15); float2 en2 = float2(-0.25, 0.55);
    dSteam = min(dSteam, dWavy(p, st2, en2, 12.0, SteamCurvature, 0.012));
    
    float2 st3 = float2(0.18, 0.18); float2 en3 = float2(0.28, 0.6);
    dSteam = min(dSteam, dWavy(p, st3, en3, 14.0, SteamCurvature, 0.01));
    
    bg = layerShape(dSteam, float4(1.0, 1.0, 1.0, SteamOpacity), StrokeThickness, bg);
    
    // --- 2. NOODLES ---
    float dNoodlesLines = 1e9;
    int count = clamp(int(NoodleCount), 1, 15);
    for(int i = 0; i < 15; i++) {
        if (i >= count) break;
        float fracI = float(i) / max(1.0, float(count - 1));
        float yPos = lerp(-0.1, 0.2, fracI);
        float wave = sin((p.x + yPos * 2.0) * 30.0) * WaveAmplitude;
        float dLine = abs(p.y - yPos - wave) - NoodleThickness;
        dNoodlesLines = min(dNoodlesLines, dLine);
    }
    // Confine noodles to a dome region above the bowl
    float dDome = length(p - float2(0.0, 0.02)) - BowlWidth * 0.85;
    float dNoodles = max(dNoodlesLines, dDome);
    
    bg = layerShape(dNoodles, NoodleColor, StrokeThickness, bg);
    
    // --- 3. TOPPINGS (EGG & LEAVES) ---
    // Soft-boiled Egg (Half)
    float2 pEgg = p - float2(-BowlWidth * 0.4, 0.12);
    float angEgg = -0.4;
    float cE = cos(angEgg); float sE = sin(angEgg);
    pEgg = float2(cE * pEgg.x + sE * pEgg.y, -sE * pEgg.x + cE * pEgg.y);
    
    float dEggWhite = sdRoundBox(pEgg, float2(0.04, 0.05), 0.03);
    float dEggYolk = length(pEgg + float2(0.0, -0.01)) - 0.025;
    
    bg = layerShape(dEggWhite, EggWhiteColor, StrokeThickness, bg);
    bg = layerShape(dEggYolk, EggYolkColor, StrokeThickness, bg);
    
    // Leaves
    float dLeaf = 1e9;
    // Leaf 1
    float2 pL1 = p - float2(BowlWidth * 0.35, 0.15);
    float angL1 = 0.6;
    float cL1 = cos(angL1); float sL1 = sin(angL1);
    pL1 = float2(cL1 * pL1.x + sL1 * pL1.y, -sL1 * pL1.x + cL1 * pL1.y);
    float dl1 = max(length(pL1 - float2(0.04, 0.0)) - 0.08, length(pL1 + float2(0.04, 0.0)) - 0.08);
    dLeaf = min(dLeaf, dl1);
    
    // Leaf 2
    float2 pL2 = p - float2(BowlWidth * 0.45, 0.08);
    float angL2 = 1.0;
    float cL2 = cos(angL2); float sL2 = sin(angL2);
    pL2 = float2(cL2 * pL2.x + sL2 * pL2.y, -sL2 * pL2.x + cL2 * pL2.y);
    float dl2 = max(length(pL2 - float2(0.03, 0.0)) - 0.06, length(pL2 + float2(0.03, 0.0)) - 0.06);
    dLeaf = min(dLeaf, dl2);
    
    bg = layerShape(dLeaf, LeafColor, StrokeThickness, bg);
    
    // --- 4. BOWL ---
    // Bowl Body (Pseudo-distance to half-ellipse intersected with y < 0)
    float2 ab = float2(max(BowlWidth, 0.1), max(BowlHeight, 0.1));
    float2 pN = p / ab;
    float l = length(pN);
    float dBody = 0.0;
    if (l < 1e-5) {
        dBody = -min(ab.x, ab.y);
    } else {
        float lenG = length(p / (ab * ab)) / l;
        dBody = (l - 1.0) / lenG;
    }
    // Cut the top perfectly flat at y = 0
    dBody = max(dBody, p.y);
    
    // Flared Rim at the top edge
    float dRim = sdRoundBox(p - float2(0.0, 0.0), float2(BowlWidth + 0.05, 0.015), 0.01);
    
    // Union of body and rim
    float dBowl = min(dBody, dRim);
    
    // Draw the bowl over everything, masking the lower halves of the noodles and toppings
    bg = layerShape(dBowl, BowlColor, StrokeThickness, bg);
    
    outColor = bg;
}