void CartoonFlame_float(float2 UV, float Size, float Layer1Offset, float Layer2Offset, float Tips, float Sharpness, float Curvature, float OutlineWidth, float4 ColorOuter, float4 ColorMiddle, float4 ColorInner, float4 ColorOutline, out float4 outColor)
{
    // PLAN:
    // 1. Center UVs at (0.5, 0.5) and scale by Size.
    // 2. Apply domain distortion (bend) for curvature/asymmetry.
    // 3. Compute polar coordinates (angle, radius) where angle 0 is UP.
    // 4. Calculate Flame SDF: Circle base + Cosine wave tips masked by height (y).
    // 5. Compute masks for 4 layers: Outline, Outer, Middle, Inner using offsets.
    // 6. Composite colors from back to front using lerp for a gradient/layered effect.

    // 1. Center and Scale
    float2 p = (UV - 0.5) * 2.0;
    p /= max(Size, 0.0001); // Prevent div by zero

    // 2. Distortion (Curvature/Asymmetry)
    // Bend the flame body based on height (y). Only bend the upper part.
    // A quadratic offset creates a nice wind-blown effect.
    float bendAmount = Curvature * 0.3 * pow(max(0.0, p.y + 0.4), 2.0);
    p.x -= bendAmount;

    // 3. Polar Coordinates
    // atan2(x, y) results in 0 at +y (Top), +/- PI at -y (Bottom)
    float angle = atan2(p.x, p.y);
    float r = length(p);

    // 4. Shape Definition (SDF)
    // Base shape is a circle of radius 1.0 (d = r - 1.0)
    // We perturb this distance field to create tongues.
    
    // Height mask: We want the base to remain round and the top to be distorted.
    float verticalMask = smoothstep(-0.3, 0.8, p.y);
    
    // Wave function for tips: Cosine ensures a peak at angle 0 (Top)
    float wave = cos(angle * Tips);
    
    // Apply distortion: Subtracting from distance extends the shape outward.
    float distortion = wave * Sharpness * verticalMask;
    float d = r - 1.0 - distortion;

    // 5. Anti-aliasing and Layer Masks
    // Calculate screen-space derivatives for consistent edge softness
    float aa = fwidth(d);
    aa = max(aa, 0.001); // Safety floor for derivative

    // Mask generation: 1.0 = Inside, 0.0 = Outside
    // Uses smoothstep for AA edges.
    
    // Outline Layer (Largest): Covers everything up to OutlineWidth
    float maskOutline = 1.0 - smoothstep(OutlineWidth - aa, OutlineWidth + aa, d);
    
    // Outer Layer (Main Flame): Boundary at d = 0
    float maskOuter = 1.0 - smoothstep(0.0 - aa, 0.0 + aa, d);
    
    // Middle Layer: Deeper inside (d < -Layer1Offset)
    float threshMiddle = -max(Layer1Offset, 0.0);
    float maskMiddle = 1.0 - smoothstep(threshMiddle - aa, threshMiddle + aa, d);
    
    // Inner Layer: Deepest inside (d < -Layer2Offset)
    float threshInner = -max(Layer2Offset, 0.0);
    float maskInner = 1.0 - smoothstep(threshInner - aa, threshInner + aa, d);

    // 6. Composite Colors
    // Start with transparent background
    float4 col = float4(0.0, 0.0, 0.0, 0.0);
    
    // Painter's Algorithm: Blend layers on top of each other
    
    // Draw Outline
    col = lerp(col, ColorOutline, maskOutline);
    
    // Draw Outer Layer over Outline
    // We multiply mask by alpha to handle transparency blending if needed
    col = lerp(col, ColorOuter, maskOuter * ColorOuter.a);
    
    // Draw Middle Layer over Outer
    col = lerp(col, ColorMiddle, maskMiddle * ColorMiddle.a);
    
    // Draw Inner Layer over Middle
    col = lerp(col, ColorInner, maskInner * ColorInner.a);

    // Output final color
    outColor = col;
}