void CartoonTulip_float(float2 UV, float Size, float BloomWidth, float BloomHeight, float4 BloomColor, float StemLength, float StemThickness, float4 StemColor, float LeafSize, float LeafAngle, float LeafCurvature, float4 LeafColor, float OutlineThickness, float4 OutlineColor, out float4 outColor) {
    // PLAN:
    // 1) Center UVs and scale coordinate space.
    // 2) Define SDFs for:
    //    - Stem: Vertical capped segment extending down from origin.
    //    - Leaves: Symmetric distorted ellipses attached to the stem.
    //    - Bloom: U-shape (Circle + Box) + 3 Circle lobes on top.
    // 3) Combine shapes using min() (union).
    // 4) Compute color masks (Vegetation vs Bloom).
    // 5) Apply anti-aliasing and outline stroke.
    // 6) Output final composited color.

    // --- Constants & Setup ---
    #ifndef PI
    #define PI 3.14159265359
    #endif

    // 1. Coordinate Setup
    float2 p = (UV - 0.5) / Size;
    // Fix aspect ratio if needed, but usually UV is square in preview or handled by user.
    // We assume isotropic scaling.

    // --- Helper Functions (Inline) ---
    // Rotation matrix
    float c = cos(LeafAngle);
    float s = sin(LeafAngle);
    float2x2 rotMat = float2x2(c, -s, s, c);
    
    // 2. SDF: Stem
    // Stem starts at (0,0) (bloom base) and goes down to (0, -StemLength)
    // Using a vertical box logic for clean connection or segment.
    float2 stemP = p;
    stemP.y += StemLength * 0.5; // Center the segment vertically relative to its length
    float2 stemSize = float2(StemThickness * 0.5, StemLength * 0.5);
    float2 dStemBox = abs(stemP) - stemSize;
    float dStem = length(max(dStemBox, 0.0)) + min(max(dStemBox.x, dStemBox.y), 0.0);
    
    // 3. SDF: Leaves
    // Attached at 60% down the stem
    float2 leafAnchor = float2(0.0, -StemLength * 0.6);
    float2 pLeaf = p - leafAnchor;
    pLeaf.x = abs(pLeaf.x); // Symmetry for left/right leaves
    
    // Apply Rotation (rotate the point in reverse -> -Angle)
    // But since we mirrored x, we rotate outward
    float ca = cos(-LeafAngle);
    float sa = sin(-LeafAngle);
    pLeaf = float2(ca*pLeaf.x - sa*pLeaf.y, sa*pLeaf.x + ca*pLeaf.y);
    
    // Curvature: Bend y based on x
    pLeaf.y -= LeafCurvature * pLeaf.x * pLeaf.x * 2.0;
    
    // Leaf Shape: Ellipsoid centered at (LeafSize/2, 0) to attach at origin
    // Use sdEllipse logic: length((p-c)/r) - 1.0
    float2 leafCenter = float2(LeafSize * 0.5, 0.0);
    float2 leafRadii = float2(LeafSize * 0.5, LeafSize * 0.25);
    float2 qLeaf = (pLeaf - leafCenter) / leafRadii;
    float dLeaf = (length(qLeaf) - 1.0) * min(leafRadii.x, leafRadii.y);
    
    // 4. SDF: Bloom
    // Base U-Shape: A box with a rounded bottom.
    // Dimensions: Width = BloomWidth, Height = BloomHeight.
    // We construct it from a Circle (bottom) and a Box (middle).
    float bloomRadius = BloomWidth * 0.5;
    // The circular bottom cup centered at (0, bloomRadius)
    // Actually let's place the bloom sitting on y=0.
    // Cup center at (0, bloomRadius).
    float dCup = length(p - float2(0.0, bloomRadius)) - bloomRadius;
    
    // The vertical sides box: from y=bloomRadius to y=BloomHeight
    // Center Y of box part: (BloomHeight + bloomRadius) / 2
    // Height of box part: (BloomHeight - bloomRadius)
    float boxH = max(0.0, BloomHeight - bloomRadius);
    float2 boxCenter = float2(0.0, bloomRadius + boxH * 0.5);
    float2 boxSize = float2(bloomRadius, boxH * 0.5);
    float2 dBoxVec = abs(p - boxCenter) - boxSize;
    float dBody = length(max(dBoxVec, 0.0)) + min(max(dBoxVec.x, dBoxVec.y), 0.0);
    
    // Combine Cup and Body
    float dBloomBase = min(dCup, dBody);
    // Clip the bottom of the cup if it goes below 0? No, full U shape is fine.
    // But strictly, dCup goes below 0. If we want a flat bottom we'd intersect, but U-shape is round bottom.
    // Let's assume U-shape means round bottom.

    // Petal Lobes: 3 Circles on top edge (y = BloomHeight)
    float lobeRadius = BloomWidth * 0.25;
    float lobeY = BloomHeight;
    // Center lobe
    float dLobeC = length(p - float2(0.0, lobeY)) - lobeRadius;
    // Side lobes
    float lobeOffset = BloomWidth * 0.35;
    float dLobeL = length(p - float2(-lobeOffset, lobeY)) - lobeRadius;
    float dLobeR = length(p - float2(lobeOffset, lobeY)) - lobeRadius;
    
    float dLobes = min(dLobeC, min(dLobeL, dLobeR));
    float dBloom = min(dBloomBase, dLobes);

    // 5. Composition & Colors
    // Group Vegetation (Stem + Leaves)
    float dVeg = min(dStem, dLeaf);
    
    // Total Shape
    float dShape = min(dBloom, dVeg);
    
    // 6. Rendering
    // Anti-aliasing width
    float aa = fwidth(dShape);
    // Soften AA slightly for cartoon look
    aa = max(aa, 0.005);
    
    // Alpha Mask
    float alpha = 1.0 - smoothstep(0.0, aa, dShape);
    
    // Outline Mask
    float outline = 1.0 - smoothstep(0.0, aa, abs(dShape) - OutlineThickness);
    // Determine fill mask (interior)
    float fillMask = 1.0 - smoothstep(0.0, aa, dShape + OutlineThickness);
    
    // Resolve Colors
    // Decide priority: Bloom on top of Stem/Leaves
    // We use the SDFs to determine which part we are in.
    // To avoid artifacts at seams, we compare the distances.
    // If dBloom < dVeg, we are closer to bloom.
    float isBloom = step(dBloom, dVeg);
    float isLeaf = step(dLeaf, dStem); // Leaves over stem?
    
    float4 vegColor = lerp(StemColor, LeafColor, 1.0 - step(dStem, dLeaf)); // Simple mix
    float4 fillColor = lerp(vegColor, BloomColor, isBloom);
    
    // Combine Outline and Fill
    // We overlay outline on top of fill to ensure clean edges.
    // Actually, standard cartoon: Outline is the border, Fill is inside.
    // Using 'over' operator logic: 
    // Color = OutlineColor * OutlineAlpha + FillColor * (1-OutlineAlpha)
    float3 finalRGB = lerp(fillColor.rgb, OutlineColor.rgb, outline);
    
    // Final Alpha: The shape coverage
    // If outline is opaque, result is opaque. 
    // Using premultiplied alpha logic or standard blending.
    // Here we assume standard blending.
    float finalAlpha = max(alpha, outline * OutlineColor.a); 
    // But wait, outline is centered on edge. 
    // The outer half of outline contributes to alpha.
    // The inner half covers the fill.
    
    // Robust approach:
    // 1. Calculate main shape silhouette alpha.
    float silhouette = 1.0 - smoothstep(0.0, aa, dShape - OutlineThickness * 0.5);
    // 2. Calculate fill alpha (shrunk shape).
    float fillAlpha = 1.0 - smoothstep(0.0, aa, dShape + OutlineThickness * 0.5);
    
    // 3. Composite
    // Background is transparent.
    // Draw Outline
    float4 col = OutlineColor;
    col.a *= silhouette;
    
    // Draw Fill over Outline? No, Fill is inside.
    // Draw Outline, then Fill inside? 
    // Usually: Fill area is dShape < 0. Outline is |dShape| < th.
    // Let's use clean lerp.
    float outlineFactor = smoothstep(0.0, aa, abs(dShape) - OutlineThickness * 0.5);
    // outlineFactor = 0 inside the stroke, 1 outside/inside far.
    // We want 1 on stroke, 0 elsewhere? No.
    // Let's use the 'outline' variable calculated earlier (centered on 0).
    // outline variable is 1 on edge, 0 elsewhere.
    
    // Composite: Start with Fill
    float3 rgb = fillColor.rgb;
    // Blend Outline on top
    rgb = lerp(rgb, OutlineColor.rgb, outline);
    
    outColor = float4(rgb * alpha, alpha);
}

// ------------------------------------------------------------------------
//  Visual Result
// ------------------------------------------------------------------------
//  This function generates a **stylized cartoon tulip** using 
//  Signed Distance Functions (SDFs).
//
//  The visual result is composed of:
//  - A cup-shaped **bloom** featuring a rounded base and three distinct 
//    lobes on the upper edge.
//  - A straight vertical **stem** descending from the center of the bloom.
//  - Two symmetrical, curved **leaves** attached to the lower section of 
//    the stem, angling outwards.
//
//  The shape features adjustable parameters for the bloom's dimensions,
//  stem length and thickness, and the size, angle, and curvature of the leaves.
//  Colors for the bloom, stem, and leaves can be customized independently.
//
//  The output is a flat-shaded floral graphic with a continuous, high-contrast
//  outline, suitable for garden icons, spring-themed UI, or nature patterns.
// ------------------------------------------------------------------------