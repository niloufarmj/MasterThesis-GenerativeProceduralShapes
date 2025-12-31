#ifndef PI
#define PI 3.14159265359
#endif

// --- Helpers ---

// Signed distance to a box
float sdBox(float2 p, float2 b) {
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// 2D Rotation
float2 rotate(float2 p, float angle) {
    float c = cos(angle);
    float s = sin(angle);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

// Lens SDF (Intersection of two circles)
// Creates a shape with length L (along X) and width W (along Y)
float sdLens(float2 p, float L, float W) {
    // Clamp dimensions to prevent math errors
    L = max(L, 0.001);
    W = max(W, 0.001);
    
    // Derive circle parameters
    // The lens is formed by the intersection of two circles centered on the Y-axis
    // k is the Y-offset of the circle centers
    float k = (L * L - W * W) / (4.0 * W);
    float R = W * 0.5 + k;
    
    // Intersection of circle at (0, -k) and circle at (0, k)
    float d1 = length(p - float2(0.0, -k)) - R;
    float d2 = length(p - float2(0.0, k)) - R;
    
    // Intersection = max
    return max(d1, d2);
}

// --- Main Function ---
// User Request: A cartoon sunflower with adjustable disk, pointed petals, stem, and leaves.
// PLAN:
// 1. Center UVs at (0,0).
// 2. Define shapes: Stem, Leaves, Petals, Center.
// 3. Stem: Box SDF extending downwards.
// 4. Leaves: Lens SDFs attached to stem, rotated.
// 5. Petals: Lens SDFs repeated radially around center.
// 6. Center: Circle SDF.
// 7. Composite colors using smoothstep masks and painter's algorithm (back-to-front).

void CartoonSunflower_float(
    float2 UV,
    float DiskRadius,
    float4 DiskColor,
    float PetalCount,
    float PetalLength,
    float PetalWidth,
    float4 PetalColor,
    float StemThickness,
    float4 StemColor,
    float LeafSize,
    float LeafAngle,
    float4 LeafColor,
    out float4 outColor)
{
    // 1. Coordinates
    float2 p = UV - 0.5;
    float aa = 0.005; // Anti-aliasing softness

    // 2. Stem SDF
    // Vertical box extending downwards from slightly below the center
    float stemHeight = 1.0;
    float2 stemOffset = float2(0.0, -stemHeight * 0.5 - DiskRadius * 0.5);
    float dStem = sdBox(p - stemOffset, float2(StemThickness * 0.5, stemHeight * 0.5));
    float maskStem = smoothstep(aa, -aa, dStem);

    // 3. Leaves SDF
    // Two leaves attached to the stem
    // Leaf 1 (Right side)
    float2 attachPoint = float2(0.0, -DiskRadius - 0.2);
    float2 pLeaf1 = rotate(p - attachPoint, -LeafAngle);
    pLeaf1.x -= LeafSize * 0.5; // Offset so leaf starts at stem
    float dLeaf1 = sdLens(pLeaf1, LeafSize, LeafSize * 0.4);
    
    // Leaf 2 (Left side)
    float2 pLeaf2 = rotate(p - attachPoint, LeafAngle);
    pLeaf2.x += LeafSize * 0.5; // Mirror offset
    float dLeaf2 = sdLens(pLeaf2, LeafSize, LeafSize * 0.4);
    
    float dLeaves = min(dLeaf1, dLeaf2);
    float maskLeaves = smoothstep(aa, -aa, dLeaves);

    // 4. Petals SDF
    // Radial repetition
    float n = max(3.0, floor(PetalCount));
    float angle = atan2(p.y, p.x);
    float sectorAngle = 2.0 * PI / n;
    // Find nearest sector index
    float sector = floor(angle / sectorAngle + 0.5);
    // Rotate p to the local coordinate system of the petal
    float rotAngle = sector * sectorAngle;
    float2 pPetal = rotate(p, -rotAngle);
    
    // Position the petal: start at disk radius, extend outward
    pPetal.x -= DiskRadius + PetalLength * 0.5;
    float dPetals = sdLens(pPetal, PetalLength, PetalWidth);
    float maskPetals = smoothstep(aa, -aa, dPetals);

    // 5. Center Disk SDF
    float dDisk = length(p) - DiskRadius;
    float maskDisk = smoothstep(aa, -aa, dDisk);

    // 6. Composition (Painter's Algorithm)
    // Layer order: Stem -> Leaves -> Petals -> Disk
    
    // Start with transparent background
    float4 col = float4(0.0, 0.0, 0.0, 0.0);
    
    // Layer Stem
    col = lerp(col, float4(StemColor.rgb, 1.0), maskStem * StemColor.a);
    
    // Layer Leaves
    col = lerp(col, float4(LeafColor.rgb, 1.0), maskLeaves * LeafColor.a);
    
    // Layer Petals
    col = lerp(col, float4(PetalColor.rgb, 1.0), maskPetals * PetalColor.a);
    
    // Layer Disk
    col = lerp(col, float4(DiskColor.rgb, 1.0), maskDisk * DiskColor.a);

    // Output final color (pre-multiplied alpha logic handled by lerp above implicitly for visual comp)
    // Ensure output alpha is correct for blending
    float combinedAlpha = saturate(maskStem * StemColor.a + maskLeaves * LeafColor.a + maskPetals * PetalColor.a + maskDisk * DiskColor.a);
    
    // Final assignment
    outColor = col;
    // Fix alpha channel for proper transparency usage in shader graph
    outColor.a = combinedAlpha;
}