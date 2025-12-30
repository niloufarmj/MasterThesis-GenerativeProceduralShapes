#ifndef PI
#define PI 3.14159265359
#endif

// Helper for alpha compositing (Source Over Destination)
float4 composite(float4 src, float4 dst) {
    float outA = src.a + dst.a * (1.0 - src.a);
    float3 outRGB = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(outA, 1e-4);
    return float4(outRGB, outA);
}

// Main Function: Cartoon Strawberry with adjustable fruit, seeds, and cap
void CartoonStrawberry_float(float2 UV, float Size, float FruitWidth, float FruitHeight, float4 FruitColor, float SeedDensity, float SeedSize, float4 SeedColor, float CapSize, float CapLobes, float4 CapColor, out float4 outColor) {
    // PLAN:
    // 1) Center UVs and apply overall Size scaling.
    // 2) Generate Fruit Body SDF using a distorted circle (tapered ellipse).
    // 3) Generate Seeds using a staggered grid pattern masked to the fruit.
    // 4) Generate Leafy Cap SDF using polar coordinates (flower/star shape).
    // 5) Composite layers (Fruit -> Seeds -> Cap) for final output.

    // 1. Setup Coordinates
    float2 p = (UV - 0.5) * 2.0;
    p /= max(Size, 0.0001); // Prevent division by zero

    // 2. Fruit Body SDF
    // Distort space to make an egg/strawberry shape: wider top, pointy bottom
    // We shift y slightly so the visual center feels right
    float2 p_body = p;
    p_body.y -= 0.15; 
    
    // Taper factor: scales X based on Y
    // When Y is positive (top), X is scaled down less (wider)
    // When Y is negative (bottom), X is scaled down more (narrower)
    // Base formula: x' = x / (1.0 + k * y)
    float taper = 0.6 + 0.4 * (p_body.y + 1.0); // Simple linear taper
    taper = max(taper, 0.1); // Clamp to avoid glitches
    
    // Apply Width/Height params to the SDF evaluation
    float2 p_fruit = float2(p_body.x / (taper * FruitWidth), p_body.y / FruitHeight);
    float dFruit = length(p_fruit) - 1.0;
    
    // Anti-aliasing for fruit
    float aa = fwidth(dFruit);
    float fruitMask = 1.0 - smoothstep(-aa, aa, dFruit);
    float4 layerFruit = float4(FruitColor.rgb, FruitColor.a * fruitMask);

    // 3. Seeds SDF (Staggered Grid)
    // Offset coordinates to align grid nicely
    float2 p_seeds = p * SeedDensity + 100.0; // +100 to avoid negative floor issues
    float row = floor(p_seeds.y);
    // Shift every other row by 0.5 for staggered pattern
    if (fmod(row, 2.0) >= 1.0) {
        p_seeds.x += 0.5;
    }
    float2 cell = frac(p_seeds) - 0.5;
    // Make seeds oval (taller than wide)
    float dSeed = length(float2(cell.x, cell.y * 0.65)) - SeedSize;
    
    // Seed mask (smoothstep for spot edges)
    float seedAlpha = 1.0 - smoothstep(-0.05, 0.05, dSeed);
    // Clip seeds to stay strictly inside the fruit
    seedAlpha *= fruitMask;
    float4 layerSeeds = float4(SeedColor.rgb, SeedColor.a * seedAlpha);

    // 4. Cap (Calyx) SDF
    // Position cap at the top of the fruit
    float2 p_cap = p - float2(0.0, FruitHeight * 0.75);
    // Polar coordinates for star shape
    float angle = atan2(p_cap.x, p_cap.y); // 0 is Up
    float r = length(p_cap);
    // Star radius modulation
    float radius_cap = CapSize + (CapSize * 0.3) * cos(angle * CapLobes);
    float dCap = r - radius_cap;
    
    float capAlpha = 1.0 - smoothstep(-aa, aa, dCap);
    float4 layerCap = float4(CapColor.rgb, CapColor.a * capAlpha);

    // 5. Composition (Painter's Algorithm)
    // Background is transparent
    float4 result = float4(0, 0, 0, 0);
    
    // Draw Fruit
    result = composite(layerFruit, result);
    // Draw Seeds on top of Fruit
    result = composite(layerSeeds, result);
    // Draw Cap on top of everything
    result = composite(layerCap, result);

    outColor = result;
}