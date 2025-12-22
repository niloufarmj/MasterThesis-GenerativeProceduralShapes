#ifndef PI
#define PI 3.14159265359
#endif

// --- Helpers ---

// Rotate a vector p by angle a (radians)
float2 rotate(float2 p, float a) {
    float c = cos(a);
    float s = sin(a);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

// Signed Distance to a Circle
float sdCircle(float2 p, float r) {
    return length(p) - r;
}

// Signed Distance to a Heart (Inigo Quilez)
// Returns d < 0 inside. Tip is at (0,0), lobes roughly up to y=1.0
float sdHeart(float2 p) {
    p.x = abs(p.x);
    // Adjust p to align the heart shape correctly
    if (p.y + p.x > 1.0)
        return sqrt(dot(p - float2(0.25, 0.75), p - float2(0.25, 0.75))) - sqrt(2.0)/4.0;
    return sqrt(min(dot(p - float2(0.00, 1.00), p - float2(0.00, 1.00)),
                    dot(p - 0.5 * max(p.x + p.y, 0.0), p - 0.5 * max(p.x + p.y, 0.0)))) * sign(p.x - p.y);
}

// Straight-alpha composite: src over dst
float4 composite(float4 src, float4 dst) {
    return src + dst * (1.0 - src.a);
}

// --- Main Function ---
// User Request: A simple cartoon flower with heart-shaped petals (fully filled), center circle, and clean outline.
void CartoonFlowerHeartPetals_float(
    float2 UV,
    float2 Center,
    float Size,
    float PetalCount,
    float PetalSize,
    float PetalSpread,
    float CenterRadius,
    float Rotation,
    float OutlineThickness,
    float4 PetalColor,
    float4 CenterColor,
    float4 OutlineColor,
    out float4 outColor)
{
    // PLAN:
    // 1. Center and Scale UV coordinates.
    // 2. Loop to construct Petals SDF by uniting rotated Heart SDFs.
    // 3. Construct Center Circle SDF.
    // 4. Combine Petals and Center for the silhouette.
    // 5. Compute masks for fill and outline.
    // 6. Composite layers: Petals -> Center -> Outline.

    // 1. Setup Coordinate Space
    float2 p = (UV - Center);
    // Scale correction: Size 1.0 = fills decent portion of screen
    // We work in unscaled space and divide dimensions by Size or multiply p
    // Let's multiply p to keep SDF Euclidean relative to Size
    p = p / max(Size, 0.0001);

    // Apply Global Rotation
    p = rotate(p, Rotation);

    // 2. Petals SDF (Union of Hearts)
    float dPetals = 100.0;
    // Clamp loop count to avoid compile issues (max 12 petals)
    int count = clamp((int)PetalCount, 1, 12);
    float angleStep = (2.0 * PI) / float(count);

    for (int i = 0; i < 12; i++) {
        if (i >= count) break;

        float theta = float(i) * angleStep;
        
        // Rotate p into the petal's frame
        // We rotate p by -theta so the current petal aligns with the positive X axis
        float2 pRot = rotate(p, -theta);
        
        // Standard Heart points UP (Y+). We want it pointing OUT (X+).
        // So we interpret (x,y) as (y, -x) effectively, or rotate -90 degrees.
        // Also apply Offset (Spread) and Scale (PetalSize).
        // Transformation:
        // 1. Shift X by -Spread (so heart tip starts at Spread distance)
        // 2. Rotate -90 (swap X/Y logic for SDF input)
        // 3. Scale
        
        float2 pHeart;
        pHeart.x = pRot.y;          // Map Y to Heart X (width)
        pHeart.y = pRot.x - PetalSpread; // Map X to Heart Y (height), offset by spread
        
        // Scale the coordinate for the SDF, then scale the distance back
        float scale = max(PetalSize, 0.001);
        float d = sdHeart(pHeart / scale) * scale;
        
        dPetals = min(dPetals, d);
    }

    // 3. Center Circle SDF
    // Center radius is relative to the Size scale
    float dCenter = sdCircle(p, CenterRadius);

    // 4. Combined Silhouette (Union)
    float dSilhouette = min(dPetals, dCenter);

    // 5. Anti-aliasing width
    // fwidth gives screen-space derivative for smooth edges regardless of zoom
    float aa = fwidth(dSilhouette);
    aa = max(aa, 0.001);

    // 6. Masks
    // Fill Masks (1.0 = inside)
    float maskPetals = 1.0 - smoothstep(0.0, aa, dPetals);
    float maskCenter = 1.0 - smoothstep(0.0, aa, dCenter);
    
    // Outline Mask (1.0 = on edge)
    // Outline is centered on the shape boundary
    float halfWidth = OutlineThickness * 0.5;
    float dOutline = abs(dSilhouette) - halfWidth;
    float maskOutline = 1.0 - smoothstep(0.0, aa, dOutline);

    // 7. Composition
    // Start with transparent
    float4 col = float4(0,0,0,0);

    // Layer 1: Petals
    float4 layerPetals = float4(PetalColor.rgb, 1.0) * maskPetals * PetalColor.a;
    
    // Layer 2: Center (Composite OVER petals)
    float4 layerCenter = float4(CenterColor.rgb, 1.0) * maskCenter * CenterColor.a;
    
    // Blend Center over Petals
    // We use a simple mix logic: if inside center, use center, else petals
    // To blend nicely at edges of center:
    float4 fillComposite = composite(layerCenter, layerPetals);

    // Layer 3: Outline (Composite OVER fill)
    float4 layerOutline = float4(OutlineColor.rgb, 1.0) * maskOutline * OutlineColor.a;
    
    // Final Combine
    outColor = composite(layerOutline, fillComposite);
}