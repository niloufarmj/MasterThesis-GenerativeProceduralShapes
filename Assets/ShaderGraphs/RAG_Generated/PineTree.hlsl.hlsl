#ifndef PI
#define PI 3.14159265359
#endif

// --- Helpers ---

// Signed distance to a box
float sdBox(float2 p, float2 b) {
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// Signed distance to an isosceles triangle
// Tip is at origin. If q.y is negative, it points UP.
float sdIsoscelesTriangle(float2 p, float2 q) {
    p.x = abs(p.x);
    float2 a = p - q * clamp(dot(p, q) / dot(q, q), 0.0, 1.0);
    float2 b = p - q * float2(clamp(p.x / q.x, 0.0, 1.0), 1.0);
    float k = sign(q.y);
    float d = min(dot(a, a), dot(b, b));
    float s = max(k * (p.x * q.y - p.y * q.x), k * (p.y - q.y));
    return sqrt(d) * sign(s);
}

// --- Main Function ---
void PineTree_float(
    float2 UV,
    float TopY, float TopW, float TopH,
    float MidY, float MidW, float MidH,
    float BotY, float BotW, float BotH,
    float TrunkY, float TrunkW, float TrunkH,
    float CornerRadius, float RimHeight,
    float4 ColorTopLeft, float4 ColorTopRight,
    float4 ColorMidLeft, float4 ColorMidRight,
    float4 ColorBotLeft, float4 ColorBotRight,
    float4 ColorTrunkLeft, float4 ColorTrunkRight,
    float4 ColorRim,
    out float4 outColor
) {
    // Center coordinates to [-0.5, 0.5]
    float2 p = UV - 0.5;
    
    // Anti-aliasing factor
    float aa = fwidth(length(p));
    if (aa == 0.0) aa = 0.005;
    
    // Start with transparent background
    float4 finalColor = float4(0.0, 0.0, 0.0, 0.0);
    
    // --- TRUNK (Back layer) ---
    float dTrunk = sdBox(p - float2(0.0, TrunkY), float2(TrunkW, TrunkH) - 0.005) - 0.005;
    float trunkMask = 1.0 - smoothstep(0.0, aa, dTrunk);
    float trunkShade = smoothstep(-aa, aa, p.x);
    float4 trunkColor = lerp(ColorTrunkLeft, ColorTrunkRight, trunkShade);
    finalColor = lerp(finalColor, trunkColor, trunkMask);
    
    // --- BOTTOM TIER ---
    float2 pBot = p - float2(0.0, BotY);
    float dBot = sdIsoscelesTriangle(pBot, float2(BotW, -BotH)) - CornerRadius;
    float botMask = 1.0 - smoothstep(0.0, aa, dBot);
    float botRimY = -BotH - CornerRadius + RimHeight;
    float botRimMask = 1.0 - smoothstep(botRimY, botRimY + aa, pBot.y);
    float botShade = smoothstep(-aa, aa, pBot.x);
    float4 botColorBase = lerp(ColorBotLeft, ColorBotRight, botShade);
    float4 botColor = lerp(botColorBase, ColorRim, botRimMask);
    finalColor = lerp(finalColor, botColor, botMask);
    
    // --- MIDDLE TIER ---
    float2 pMid = p - float2(0.0, MidY);
    float dMid = sdIsoscelesTriangle(pMid, float2(MidW, -MidH)) - CornerRadius;
    float midMask = 1.0 - smoothstep(0.0, aa, dMid);
    float midRimY = -MidH - CornerRadius + RimHeight;
    float midRimMask = 1.0 - smoothstep(midRimY, midRimY + aa, pMid.y);
    float midShade = smoothstep(-aa, aa, pMid.x);
    float4 midColorBase = lerp(ColorMidLeft, ColorMidRight, midShade);
    float4 midColor = lerp(midColorBase, ColorRim, midRimMask);
    finalColor = lerp(finalColor, midColor, midMask);
    
    // --- TOP TIER (Front layer) ---
    float2 pTop = p - float2(0.0, TopY);
    float dTop = sdIsoscelesTriangle(pTop, float2(TopW, -TopH)) - CornerRadius;
    float topMask = 1.0 - smoothstep(0.0, aa, dTop);
    float topRimY = -TopH - CornerRadius + RimHeight;
    float topRimMask = 1.0 - smoothstep(topRimY, topRimY + aa, pTop.y);
    float topShade = smoothstep(-aa, aa, pTop.x);
    float4 topColorBase = lerp(ColorTopLeft, ColorTopRight, topShade);
    float4 topColor = lerp(topColorBase, ColorRim, topRimMask);
    finalColor = lerp(finalColor, topColor, topMask);
    
    outColor = finalColor;
}
