#ifndef PI
#define PI 3.14159265359
#endif

// Helper: squared length of vector
float dot2(float2 z) {
    return dot(z, z);
}

// SDF for a Heart shape (based on Inigo Quilez)
// Returns: negative inside, positive outside
float sdHeart(float2 p) {
    p.x = abs(p.x);
    // Upper lobes
    if (p.y + p.x > 1.0)
        return sqrt(dot2(p - float2(0.25, 0.75))) - sqrt(2.0)/4.0;
    // Lower point
    return sqrt(min(dot2(p - float2(0.00, 1.00)),
                    dot2(p - 0.5 * max(p.x + p.y, 0.0)))) * sign(p.x - p.y);
}

// Main Function: Concentric Heart Shape
// PLAN:
// 1) Center UVs and apply rotation.
// 2) Apply scale and aspect ratio adjustments.
// 3) Offset coordinate to center the heart shape visually.
// 4) Calculate Signed Distance Field (SDF).
// 5) Invert distance for 'inside' logic and generate concentric bands.
// 6) Compute smooth masks for bands and outer edge.
// 7) Apply color gradient and output.
void ConcentricHeartShape_float(
    float2 UV,
    float2 Center,
    float Size,
    float2 Proportions,
    float Rotation,
    float BandCount,
    float BandThickness,
    float4 InnerColor,
    float4 OuterColor,
    out float4 outColor
) {
    // 1. Center and Rotate
    float2 p = UV - Center;
    
    float c = cos(Rotation);
    float s = sin(Rotation);
    p = float2(c * p.x + s * p.y, -s * p.x + c * p.y);
    
    // 2. Scale and Proportions
    // Scale 'p' so that the shape fits the Size.
    // Size of 1.0 roughly fills the screen.
    p /= max(Size, 0.001);
    
    // Adjust for aspect ratio (width vs height)
    // Proportions.x controls width, .y controls height
    p /= max(Proportions, 0.001);
    
    // 3. Visual Centering
    // The mathematical heart SDF sits roughly at y=[0, 1] with tip at (0,0).
    // We shift y by +0.5 to move the visual center to (0,0).
    p.y += 0.5;
    
    // 4. Calculate SDF
    float d = sdHeart(p);
    
    // 5. Band Logic
    // Convert to positive distance inside the shape
    float distInside = -d;
    
    // Analytic Anti-Aliasing width
    float aa = fwidth(distInside);
    
    // 6. Masks
    // Outer shape edge mask (0 outside, 1 inside)
    float shapeMask = smoothstep(-aa, 0.0, distInside);
    
    // Concentric Bands
    // Map distance to repeating band intervals
    float bandCoords = distInside * max(BandCount, 1.0);
    float bandVal = frac(bandCoords);
    
    // Band AA (relative to band frequency)
    float bandAA = fwidth(bandCoords);
    
    // Create the band fill based on thickness (0 to 1)
    // Fills from the start of the interval up to Thickness
    float bandMask = smoothstep(BandThickness + bandAA, BandThickness, bandVal);
    // Combine with 'step(0, bandVal)' implicit in smoothstep range, 
    // but we need to ensure the gap is transparent.
    // Logic: if bandVal < Thickness -> 1, else -> 0.
    // Note: bandMask is 1 when bandVal is small (start of band).
    
    // 7. Coloring
    // Gradient from center (high distInside) to edge (low distInside)
    // Normalize roughly: Heart radius is approx 0.6 in SDF space.
    float gradT = saturate(distInside * 1.5);
    float4 finalRGB = lerp(OuterColor, InnerColor, gradT);
    
    // Final Composition
    float finalAlpha = shapeMask * bandMask;
    
    // Pre-multiply alpha for correct blending if needed, or output straight alpha
    // Standard Unity UI/Sprite usually expects straight alpha in shader graph if Blend Mode is Alpha.
    // Here we output (RGB * Alpha, Alpha) pattern just in case.
    outColor = float4(finalRGB.rgb * finalAlpha, finalAlpha);
}