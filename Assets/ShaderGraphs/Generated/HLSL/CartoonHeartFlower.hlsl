#ifndef PI
#define PI 3.14159265359
#endif

// Helper: Squared length
float dot2(float2 v) { return dot(v,v); }

// Helper: Heart Signed Distance Function (Tip at 0,0)
// Returns negative inside, positive outside
float sdHeart(float2 p) {
    p.x = abs(p.x);
    // Upper lobes area
    if( p.y + p.x > 1.0 )
        return sqrt(dot2(p - float2(0.25, 0.75))) - sqrt(2.0)/4.0;
    // Lower tip area
    return sqrt(min(dot2(p - float2(0.00, 1.00)),
                    dot2(p - 0.5 * max(p.x + p.y, 0.0)))) * sign(p.x - p.y);
}

// Helper: Safe color blending (Source Over)
float4 blend(float4 dest, float4 src) {
    return float4(lerp(dest.rgb, src.rgb, src.a), 1.0 - (1.0 - dest.a) * (1.0 - src.a));
}

// Main Function: Cartoon Heart Flower
// Request: Heart-shaped petals pointing to a round center, cartoon style.
void CartoonHeartFlower_float(float2 UV, float PetalCount, float PetalLength, float PetalWidth, float CenterRadius, float4 PetalColor, float4 CenterColor, float4 OutlineColor, float OutlineWidth, out float4 outColor) {
    // PLAN:
    // 1) Center UVs at (0,5, 0.5).
    // 2) Compute angular repetition to create petals.
    // 3) Evaluate Heart SDF for the current sector (and neighbors for correct blending).
    // 4) Compute Center Circle SDF.
    // 5) Apply smoothstep for anti-aliased masks (fill and outline).
    // 6) Composite layers: Petals -> Center -> Outlines.

    float2 p = UV - 0.5;
    float aa = 0.005; // Anti-aliasing width

    // --- 1. Petals SDF ---
    // We evaluate the heart SDF in polar sectors. To handle overlap correctly,
    // we check the current sector and its immediate neighbors.
    
    float an = (2.0 * PI) / max(1.0, PetalCount);
    float currentAngle = atan2(p.y, p.x);
    float currentSector = round(currentAngle / an);
    
    float dPetals = 100.0;
    
    // Check neighbor sectors (-1, 0, 1) to handle petal overlap smoothly
    for(int i = -1; i <= 1; i++) {
        float sectorIndex = currentSector + float(i);
        float sectorAngle = sectorIndex * an;
        
        // Rotate space so this sector aligns with the X axis (Radial axis)
        float c = cos(sectorAngle);
        float s = sin(sectorAngle);
        float2 pRot = float2(c * p.x + s * p.y, -s * p.x + c * p.y);
        
        // Map radial space to heart space
        // Heart SDF: Y is up (lobes), X is width. Tip at (0,0).
        // pRot: X is radial (distance from center). Y is tangential (width).
        // So we swap axes: Heart Y <= pRot.X, Heart X <= pRot.Y
        float2 pHeart = float2(pRot.y, pRot.x);
        
        // Scale the heart shape
        // We divide coordinate by size, then multiply result by size to preserve metric
        float2 scale = float2(max(0.001, PetalWidth), max(0.001, PetalLength));
        float dist = sdHeart(pHeart / scale) * min(scale.x, scale.y);
        
        dPetals = min(dPetals, dist);
    }

    // --- 2. Center SDF ---
    float dCenter = length(p) - CenterRadius;

    // --- 3. Compute Masks ---
    // Petals
    float petalFillMask = 1.0 - smoothstep(0.0, aa, dPetals);
    float petalStrokeMask = 1.0 - smoothstep(0.0, aa, abs(dPetals) - OutlineWidth);
    
    // Center
    float centerFillMask = 1.0 - smoothstep(0.0, aa, dCenter);
    float centerStrokeMask = 1.0 - smoothstep(0.0, aa, abs(dCenter) - OutlineWidth);

    // --- 4. Composition ---
    // We start with transparent, then layer: Petal Outline -> Petal Fill -> Center Outline -> Center Fill
    // Using simple lerp for opaque look (Cartoon style)
    
    float4 col = float4(0, 0, 0, 0);
    
    // Layer 1: Petals (Outline then Fill to ensure fill covers inner half of stroke if desired, 
    // but for cartoon bold lines, usually we want Stroke on top of Fill)
    // Let's do: Fill, then Stroke (border)
    
    // Petal Fill
    col = lerp(col, PetalColor, petalFillMask);
    // Petal Outline (Composite on top)
    col = lerp(col, OutlineColor, petalStrokeMask * OutlineColor.a);
    
    // Layer 2: Center (On top of petals)
    // Center Fill
    col = lerp(col, CenterColor, centerFillMask);
    // Center Outline
    col = lerp(col, OutlineColor, centerStrokeMask * OutlineColor.a);
    
    // Final Alpha (Approximation for transparency)
    float finalAlpha = max(petalStrokeMask, centerStrokeMask);
    outColor = float4(col.rgb * finalAlpha, finalAlpha);
}