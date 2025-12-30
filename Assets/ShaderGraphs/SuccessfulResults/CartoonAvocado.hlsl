/* 
  Cartoon Avocado SDF
  Generates a pear-shaped avocado half with adjustable body, distinct skin layer,
  flesh, and a circular seed (pit). Features clean outlines and flat 2D cartoon style.
*/

#ifndef CARTOON_AVOCADO_INCLUDED
#define CARTOON_AVOCADO_INCLUDED

// Smooth min function for organic shape blending (Polynomial smin)
float avo_smin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / max(k, 0.0001), 0.0, 1.0);
    return lerp(b, a, h) - k * h * (1.0 - h);
}

#endif

void CartoonAvocado_float(
    float2 UV,
    float Size,
    float4 ShapeParams, // x: BotRadius, y: TopRadius, z: Offset, w: Blend
    float4 SeedParams,  // x: Radius, y: OffsetY, z: unused, w: unused
    float4 StyleParams, // x: SkinThickness, y: StrokeWidth
    float4 SkinColor,
    float4 FleshColor,
    float4 SeedColor,
    float4 StrokeColor,
    out float4 outColor)
{
    // PLAN:
    // 1. Center UVs at (0.5, 0.5) and scale by Size to ensure visibility.
    // 2. Build Pear Body SDF using two circles offset vertically and smoothly blended.
    // 3. Build Seed SDF using a single offset circle.
    // 4. Calculate Anti-Aliasing width based on screen derivatives.
    // 5. Composite layers using painter's algorithm: Stroke -> Skin -> Flesh -> Seed.
    // 6. Output final color with premultiplied alpha pattern.

    // --- 1. Coordinate Setup ---
    // Center UVs and normalize scale. 
    // Size = 1.0 means the -0.5 to 0.5 UV space maps to -0.5 to 0.5 coordinates.
    // Division by max(Size, 0.001) ensures scaling works intuitively (larger Size = larger object).
    float2 p = (UV - 0.5) / max(Size, 0.001);

    // --- 2. Body SDF (Pear Shape) ---
    float botR = max(ShapeParams.x, 0.0); // Bottom circle radius
    float topR = max(ShapeParams.y, 0.0); // Top circle radius
    float vOff = ShapeParams.z;           // Vertical offset from center
    float blend = max(ShapeParams.w, 0.001); // Smooth blend factor

    // Position circles: Top is shifted up, Bottom shifted down
    float dBot = length(p - float2(0.0, -vOff)) - botR;
    float dTop = length(p - float2(0.0, vOff)) - topR;
    
    // Smooth union (smin) of the two circles creates the pear shape
    float dBody = avo_smin(dBot, dTop, blend);

    // --- 3. Seed SDF ---
    float seedR = max(SeedParams.x, 0.0);
    float seedY = SeedParams.y;
    float dSeed = length(p - float2(0.0, seedY)) - seedR;

    // --- 4. Anti-Aliasing & Style ---
    // Calculate pixel-perfect AA width
    float aa = fwidth(dBody);
    if (aa < 0.0001) aa = 0.005; // Fallback for safe preview

    float strokeW = max(StyleParams.y, 0.0);
    float skinThick = max(StyleParams.x, 0.0);

    // --- 5. Compositing (Painter's Algorithm) ---
    // Start with transparent black. We accumulate RGB and Alpha.
    float3 finalRGB = float3(0.0, 0.0, 0.0);
    
    // Layer 1: Body Stroke (Outer Shell)
    // Drawn where dBody < strokeWidth
    float maskBodyStroke = smoothstep(strokeW + aa, strokeW - aa, dBody);
    finalRGB = lerp(finalRGB, StrokeColor.rgb, maskBodyStroke);

    // Layer 2: Skin (Main Body)
    // Drawn where dBody < 0.0. This draws over the inner part of the stroke.
    float maskSkin = smoothstep(aa, -aa, dBody);
    finalRGB = lerp(finalRGB, SkinColor.rgb, maskSkin);

    // Layer 3: Flesh (Inner Body)
    // Drawn where dBody < -skinThickness. Draws over the skin.
    float maskFlesh = smoothstep(-skinThick + aa, -skinThick - aa, dBody);
    finalRGB = lerp(finalRGB, FleshColor.rgb, maskFlesh);

    // Layer 4: Seed Stroke
    // Drawn where dSeed < strokeWidth
    float maskSeedStroke = smoothstep(strokeW + aa, strokeW - aa, dSeed);
    finalRGB = lerp(finalRGB, StrokeColor.rgb, maskSeedStroke);

    // Layer 5: Seed Fill
    // Drawn where dSeed < 0.0
    float maskSeedFill = smoothstep(aa, -aa, dSeed);
    finalRGB = lerp(finalRGB, SeedColor.rgb, maskSeedFill);

    // --- 6. Final Output ---
    // Determine final alpha based on the outermost visible pixels (strokes)
    // Because we lerped RGB starting from black, finalRGB is already pre-multiplied by coverage.
    float finalAlpha = max(maskBodyStroke, maskSeedStroke);
    
    outColor = float4(finalRGB, finalAlpha);
}