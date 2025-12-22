#ifndef PI
#define PI 3.14159265359
#endif

// --- Helpers ---

// Signed Distance to a Box
inline float crown_sdBox(float2 p, float2 b) {
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// Signed Distance to a Circle
inline float crown_sdCircle(float2 p, float r) {
    return length(p) - r;
}

// Signed Distance to an Isosceles Triangle
// q.x = half width, q.y = height. Tip at (0, height), base centered at (0,0)
inline float crown_sdIsoTriangle(float2 p, float2 q) {
    p.x = abs(p.x);
    float2 a = p - q * clamp(dot(p, q) / dot(q, q), 0.0, 1.0);
    float2 b = p - q * float2(clamp(p.x / q.x, 0.0, 1.0), 1.0);
    float k = sign(q.y);
    float d = min(dot(a, a), dot(b, b));
    float s = max(k * (p.x * q.y - p.y * q.x), k * (p.y - q.y));
    return sqrt(d) * sign(s);
}

// --- Main Function ---
// Draws a playful cartoon crown with a curved base, rounded spikes, and jewel tips.
void CartoonCrown_float(
    float2 UV,
    float NumSpikes,
    float CrownWidth,
    float SpikeHeight,
    float BaseThickness,
    float JewelRadius,
    float4 BaseColor,
    float4 SpikeColor,
    float4 JewelColor,
    out float4 outColor
) {
    // PLAN:
    // 1) Center UVs and apply a parabolic bend to curve the entire crown (soft look).
    // 2) Define SDF for the Base Band (rounded box at bottom).
    // 3) Define SDF for Spikes using domain repetition (rounded triangles).
    // 4) Define SDF for Jewels at the tips of the repeated spikes.
    // 5) Composite layers: Spikes (back) -> Base (middle) -> Jewels (front).

    // 1) Coordinates
    float2 p = UV - 0.5;
    
    // Global Bend: Shift Y down based on X squared to curve the crown upwards (smile shape)
    p.y -= 0.2 * p.x * p.x;

    // 2) Base Band SDF
    // Placed at the bottom. Since y=0 is our pivot, we center the band at -BaseThickness/2
    float2 baseSize = float2(CrownWidth * 0.5, BaseThickness * 0.5);
    float2 baseCenter = float2(0.0, -BaseThickness * 0.5);
    // Subtract 0.02 for rounded corners
    float dBase = crown_sdBox(p - baseCenter, baseSize) - 0.02;

    // 3) Spikes and Jewels Logic
    // Calculate spacing for N spikes
    float safeCount = max(1.0, floor(NumSpikes));
    float cellWidth = CrownWidth / safeCount;
    
    // Domain Repetition: map x range to cell indices
    // Shift x so indices start from left
    float xShifted = p.x + CrownWidth * 0.5;
    float id = floor(xShifted / cellWidth);
    float xLocal = xShifted - (id + 0.5) * cellWidth; // Center x in the cell
    
    // Valid spike check (only draw within the count)
    bool isValid = (id >= 0.0 && id < safeCount);

    // Spike SDF
    // Dimensions: Width is slightly less than cell width for separation. Height is input.
    float spikeHalfW = (cellWidth * 0.85) * 0.5;
    float2 spikeDims = float2(spikeHalfW, SpikeHeight);
    
    // Local point for spike (base at y=0)
    float2 pSpike = float2(xLocal, p.y);
    // Subtract 0.03 for soft rounded corners
    float dSpike = crown_sdIsoTriangle(pSpike, spikeDims) - 0.03;
    
    // Push invalid spikes out of view
    if (!isValid) dSpike = 100.0;

    // Jewel SDF
    // Placed at the tip of the spike: (0, SpikeHeight)
    float2 pJewel = float2(xLocal, p.y - SpikeHeight);
    float dJewel = crown_sdCircle(pJewel, JewelRadius);
    if (!isValid) dJewel = 100.0;

    // 4) Rendering / Compositing
    // Soft anti-aliasing
    float aa = 0.005;
    
    float maskBase = 1.0 - smoothstep(0.0, aa, dBase);
    float maskSpike = 1.0 - smoothstep(0.0, aa, dSpike);
    float maskJewel = 1.0 - smoothstep(0.0, aa, dJewel);

    // Pre-multiply alpha for correct blending
    float4 colBase = float4(BaseColor.rgb * maskBase, BaseColor.a * maskBase);
    float4 colSpike = float4(SpikeColor.rgb * maskSpike, SpikeColor.a * maskSpike);
    float4 colJewel = float4(JewelColor.rgb * maskJewel, JewelColor.a * maskJewel);

    // Layer Order: Spikes (Back) -> Base (Middle) -> Jewels (Front)
    // Standard Over Operator: result = src + dst * (1 - src.a)
    
    // 1. Spikes background
    float4 layer1 = colSpike;
    
    // 2. Base over Spikes
    float4 layer2 = colBase + layer1 * (1.0 - colBase.a);
    
    // 3. Jewels over Base
    float4 finalCol = colJewel + layer2 * (1.0 - colJewel.a);

    outColor = finalCol;
}