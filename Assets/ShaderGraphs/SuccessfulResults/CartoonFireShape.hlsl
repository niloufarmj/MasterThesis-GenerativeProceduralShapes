// PLAN:
// 1) Center UV coordinates.
// 2) Apply domain distortion to create a flame/egg silhouette (wider bottom, narrow top).
// 3) Calculate Signed Distance Field (SDF) for the base flame shape.
// 4) Compute 4 masks based on SDF thresholds: Outline, Outer, Mid, Core.
// 5) Composite the 4 color layers using smoothstep AA and alpha blending.

#ifndef PI
#define PI 3.14159265359
#endif

void CartoonFireShape_float(float2 UV, float2 Center, float Size, float4 ColorCore, float4 ColorMid, float4 ColorOuter, float4 ColorOutline, float OutlineWidth, float LayerSpacing, out float4 outColor) {
    // 1. Center coordinates
    float2 p = UV - Center;
    
    // 2. Shape Distortion (Flame/Egg Silhouette)
    // Shift local Y down so the flame sits nicely within the UV bounds
    p.y += Size * 0.4;
    
    // Anisotropic scaling: Scale X based on Y height
    // As Y increases (top), we scale X up (making the shape coordinate space larger -> shape visual narrower)
    // As Y decreases (bottom), we scale X down (shape visual wider)
    float normalizedY = p.y / max(Size, 0.001);
    float shapingFactor = 1.0 + 0.6 * (normalizedY + 0.5);
    shapingFactor = max(0.1, shapingFactor); // Prevent negative scaling artifacts
    
    float2 q = p;
    q.x *= shapingFactor;

    // 3. Calculate Base SDF
    float d = length(q) - Size;

    // 4. Compute Anti-Aliasing Width
    // Use fwidth for pixel-perfect AA, with fallback for preview windows
    float aa = fwidth(d);
    if (aa < 0.0001) aa = 0.005;

    // 5. Generate Layer Masks using smoothstep for soft edges
    // Layer 0: Outline (Extends outside the base shape by OutlineWidth)
    // Range: [0, OutlineWidth]
    float maskOutline = 1.0 - smoothstep(OutlineWidth - aa, OutlineWidth, d);
    
    // Layer 1: Outer Fire (Base shape surface)
    // Range: [0, -infinity]
    float maskOuter = 1.0 - smoothstep(0.0 - aa, 0.0, d);
    
    // Layer 2: Middle Fire (Inset by LayerSpacing)
    float maskMid = 1.0 - smoothstep(-LayerSpacing - aa, -LayerSpacing, d);
    
    // Layer 3: Core Fire (Inset by 2 * LayerSpacing)
    float maskCore = 1.0 - smoothstep(-2.0 * LayerSpacing - aa, -2.0 * LayerSpacing, d);

    // 6. Composite Colors (Painter's Algorithm / Layering)
    // Start with transparent background
    float4 finalColor = float4(0, 0, 0, 0);

    // Draw Outline
    // We use standard alpha blending logic: lerp(background, foreground, foregroundAlpha)
    finalColor = lerp(finalColor, ColorOutline, maskOutline * ColorOutline.a);
    
    // Draw Outer Layer (on top of outline)
    finalColor = lerp(finalColor, ColorOuter, maskOuter * ColorOuter.a);
    
    // Draw Middle Layer (on top of outer)
    finalColor = lerp(finalColor, ColorMid, maskMid * ColorMid.a);
    
    // Draw Core Layer (on top of middle)
    finalColor = lerp(finalColor, ColorCore, maskCore * ColorCore.a);

    // Final Output
    outColor = finalColor;
}