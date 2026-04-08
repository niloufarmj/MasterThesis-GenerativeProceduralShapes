#ifndef PI
#define PI 3.14159265359
#endif

// Rotates a point p by angle (radians) around origin (0,0)
float2 rotate2D(float2 p, float angle) {
    float s = sin(angle);
    float c = cos(angle);
    return float2(p.x * c - p.y * s, p.x * s + p.y * c);
}

// SDF for a box with rounded corners
// p: point, b: half-extents (width/2, height/2), r: corner radius
float sdRoundedBox(float2 p, float2 b, float r) {
    float2 q = abs(p) - b + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

// SDF for a Vesica (intersection of two circles) - perfect for leaves
// p: point, r: circle radius, d: distance from center to circle centers
float sdVesica(float2 p, float r, float d) {
    p = abs(p);
    float b = sqrt(r*r - d*d);
    return ((p.y - b) * d > p.x * b) ? length(p - float2(0.0, b))
                                     : length(p - float2(-d, 0.0)) - r;
}

void CartoonPineapple_float(float2 UV, float Width, float Height, float Curvature, float GridDensity, float GridThickness, float LeafCount, float LeafLength, float LeafSpread, float StrokeThickness, float4 BodyColor, float4 LeafColor, float4 GridColor, float4 StrokeColor, out float4 outColor) {
    // PLAN:
    // 1. Center UV coordinates at (0,0).
    // 2. Define Fruit Body SDF (RoundedBox).
    // 3. Define Leaf Cluster SDF (Loop of rotated Vesicas).
    // 4. Compute Grid Pattern inside the fruit (Diagonal Lines).
    // 5. Combine layers: Leaves on top of Fruit, Fruit contains Grid.
    // 6. Apply colors and outlines using smoothstep for anti-aliasing.

    float2 p = UV - 0.5;
    float aa = fwidth(length(p)); // Anti-aliasing factor based on screen derivatives
    
    // --- 1. FRUIT BODY SDF ---
    // Half-extents for the box
    float2 fruitSize = float2(Width, Height) * 0.5;
    // Clamp curvature to not exceed size
    float rBox = clamp(Curvature, 0.0, min(fruitSize.x, fruitSize.y));
    
    // Fruit is centered at (0, -0.05) to leave room for leaves
    float2 pFruit = p - float2(0.0, -0.05);
    float dFruit = sdRoundedBox(pFruit, fruitSize, rBox);

    // --- 2. LEAF CLUSTER SDF ---
    float dLeaves = 100.0;
    
    // Leaf geometric parameters for sdVesica
    // We derive circle radius (r) and offset (d) from Desired Length and Width
    // Assume Leaf Width is proportional to Length (e.g., 35%)
    float leafW = LeafLength * 0.35;
    float leafL = LeafLength;
    // Math: chord = 2*sqrt(r^2 - d^2) = L, width = 2*(r-d) = W
    // Solved for r: r = (L^2 + W^2) / (4*W)
    // Solved for d: d = r - W/2
    float vR = (leafL*leafL + leafW*leafW) / (4.0 * leafW);
    float vD = vR - (leafW * 0.5);
    
    // Position where leaves attach (top of fruit)
    float2 leafOrigin = pFruit - float2(0.0, fruitSize.y * 0.85); // Slightly sunken into fruit
    
    // Loop to generate leaves
    // Angle range centered around Y-axis
    float startAngle = -LeafSpread * 0.5;
    float angleStep = (LeafCount > 1.5) ? LeafSpread / (LeafCount - 1.0) : 0.0;
    
    // Limit loop for performance (HLSL unrolling)
    int count = clamp(int(LeafCount), 1, 10);
    
    for (int i = 0; i < count; i++) {
        float ang = startAngle + float(i) * angleStep;
        // Rotate point relative to leaf origin
        float2 pRot = rotate2D(leafOrigin, -ang);
        // Offset Y so leaf base is at origin, pointing up
        pRot.y -= LeafLength * 0.4; // Shift center of vesica up
        
        float dist = sdVesica(pRot, vR, vD);
        dLeaves = min(dLeaves, dist);
    }

    // --- 3. GRID PATTERN ---
    // Rotate UVs 45 degrees for diagonal grid
    float2 gridP = rotate2D(pFruit, PI * 0.25);
    // Scale by density
    gridP *= GridDensity;
    // Domain repetition: frac(x) - 0.5 centers the repetition
    float2 gridCell = abs(frac(gridP) - 0.5);
    // Distance to nearest grid line (min of x and y axes)
    // We divide by GridDensity to get back to UV space scale for thickness
    float dGridRaw = min(gridCell.x, gridCell.y);
    float dGrid = (dGridRaw / GridDensity) - (GridThickness * 0.5);
    
    // --- 4. COMPOSITING ---
    // We need to decide pixel color based on SDFs
    
    // Masks for shapes (1.0 = inside, 0.0 = outside)
    float maskFruit = 1.0 - smoothstep(0.0, aa, dFruit);
    float maskLeaves = 1.0 - smoothstep(0.0, aa, dLeaves);
    
    // Masks for outlines (1.0 = on edge)
    // Outline is centered on the shape boundary, thickness = StrokeThickness
    float outlineFruit = 1.0 - smoothstep(0.0, aa, abs(dFruit) - StrokeThickness * 0.5);
    float outlineLeaves = 1.0 - smoothstep(0.0, aa, abs(dLeaves) - StrokeThickness * 0.5);

    // Grid Mask (inside fruit only)
    // Smoothstep for grid lines
    float maskGrid = 1.0 - smoothstep(0.0, aa, dGrid);
    
    // --- LAYER MIXING ---
    // Start with transparent
    float4 layerColor = float4(0, 0, 0, 0);

    // Layer 1: Fruit Body
    // Base Color -> Grid Lines -> Outline
    float3 fruitFill = lerp(BodyColor.rgb, GridColor.rgb, maskGrid * BodyColor.a); 
    // If on outline, use StrokeColor, else use Fill
    // We use 'step' logic with smoothstep for clean blending
    // Logic: if (outline > 0.5) stroke else fill
    float3 fruitFinalRGB = lerp(fruitFill, StrokeColor.rgb, outlineFruit);
    
    // Layer 1 Composite
    // Use max(mask, outline) to include the stroke width in the alpha
    float fruitAlpha = saturate(maskFruit + outlineFruit);
    float4 layerFruit = float4(fruitFinalRGB * fruitAlpha, fruitAlpha);

    // Layer 2: Leaves (On top of fruit)
    float3 leafFinalRGB = lerp(LeafColor.rgb, StrokeColor.rgb, outlineLeaves);
    float leafAlpha = saturate(maskLeaves + outlineLeaves);
    float4 layerLeaf = float4(leafFinalRGB * leafAlpha, leafAlpha);

    // Combine Layers (Leaf over Fruit)
    // Standard alpha blending: out = src + dst * (1 - src.a)
    float3 finalRGB = layerLeaf.rgb + layerFruit.rgb * (1.0 - layerLeaf.a);
    float finalA = layerLeaf.a + layerFruit.a * (1.0 - layerLeaf.a);

    outColor = float4(finalRGB, finalA);
}