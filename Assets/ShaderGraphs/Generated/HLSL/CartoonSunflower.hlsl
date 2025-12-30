/* 
  Cartoon Sunflower Generator
  Renders a 2D sunflower with adjustable central disk, radial petals, stem, and leaves.
*/

// Helper: Box Signed Distance Field
float sdBox_Sunflower(float2 p, float2 b) {
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// Helper: 2D Rotation
float2 rotate_Sunflower(float2 p, float angle) {
    float c = cos(angle);
    float s = sin(angle);
    return float2(c*p.x - s*p.y, s*p.x + c*p.y);
}

void CartoonSunflower_float(float2 UV, float DiskRadius, float4 DiskColor, float PetalCount, float2 PetalSize, float4 PetalColor, float StemThickness, float4 StemColor, float2 LeafSize, float LeafVerticalPos, float4 LeafColor, out float4 outColor) {
    // PLAN:
    // 1. Center UV coordinates (0.5, 0.5).
    // 2. Compute SDF for the Stem (vertical box extending down).
    // 3. Compute SDF for Leaves (symmetric, rotated ellipses attached to stem).
    // 4. Compute SDF for Petals (polar domain repetition, rotated ellipses).
    // 5. Compute SDF for Central Disk (circle).
    // 6. Use fwidth() for adaptive anti-aliasing on all shapes.
    // 7. Layer colors: Stem -> Leaves -> Petals -> Disk.

    #ifndef PI
    #define PI 3.14159265359
    #endif

    float2 p = UV - 0.5;

    // --- 1. Stem ---
    // Vertical box centered at y=-0.5 with height 0.5 (spanning y=0 to y=-1)
    float2 stemSize = float2(StemThickness * 0.5, 0.5);
    float2 stemPos = p - float2(0.0, -0.5);
    float dStem = sdBox_Sunflower(stemPos, stemSize);

    // --- 2. Leaves ---
    // Symmetry across Y axis to draw two leaves
    float2 q = p;
    q.x = abs(q.x);
    // Offset leaf attachment point relative to stem surface and vertical pos
    float2 leafAnchor = float2(StemThickness * 0.5, LeafVerticalPos);
    q -= leafAnchor;
    // Rotate leaf outwards (approx 35 degrees)
    q = rotate_Sunflower(q, -0.6);
    // Ellipse shape approximation
    // LeafSize.x = Width, LeafSize.y = Length
    // Radii: x corresponds to Length (local x axis), y to Width
    float2 leafRadii = float2(LeafSize.y, LeafSize.x) * 0.5;
    // Shift center so leaf starts at anchor
    float2 leafCenter = float2(leafRadii.x, 0.0);
    // Scaled distance field (using length/radius - 1)
    float dLeaf = length((q - leafCenter) / max(leafRadii, 0.001)) - 1.0;

    // --- 3. Petals ---
    float n = max(3.0, floor(PetalCount));
    float angleStep = 2.0 * PI / n;
    float currentAngle = atan2(p.y, p.x);
    // Determine which angular sector we are in
    float sector = floor(currentAngle / angleStep + 0.5);
    float sectorAngle = sector * angleStep;
    // Rotate p into the local coordinate system of the petal
    float2 pPetal = rotate_Sunflower(p, -sectorAngle);
    // Petal shape: Ellipse
    // PetalSize.x = Width, PetalSize.y = Length
    float2 petalRadii = float2(PetalSize.y, PetalSize.x) * 0.5;
    // Position petal at the edge of the disk, slightly sunken in for connection
    float2 petalPos = float2(DiskRadius + petalRadii.x * 0.7, 0.0);
    float dPetal = length((pPetal - petalPos) / max(petalRadii, 0.001)) - 1.0;

    // --- 4. Central Disk ---
    float dDisk = length(p) - DiskRadius;

    // --- 5. Compositing & Anti-Aliasing ---
    // Use fwidth to determine edge softness based on screen-space derivatives
    // This handles the non-uniform scaling of the ellipse SDFs correctly
    float maskStem  = smoothstep(0.0, -max(fwidth(dStem), 0.001), dStem);
    float maskLeaf  = smoothstep(0.0, -max(fwidth(dLeaf), 0.001), dLeaf);
    float maskPetal = smoothstep(0.0, -max(fwidth(dPetal), 0.001), dPetal);
    float maskDisk  = smoothstep(0.0, -max(fwidth(dDisk), 0.001), dDisk);

    // Initialize color (transparent background)
    float4 col = float4(0, 0, 0, 0);

    // Layer 1: Stem (Back)
    col = lerp(col, StemColor, maskStem);

    // Layer 2: Leaves (On top of stem)
    col = lerp(col, LeafColor, maskLeaf);

    // Layer 3: Petals (Behind disk, but cover background/stem)
    col = lerp(col, PetalColor, maskPetal);

    // Layer 4: Disk (Front)
    col = lerp(col, DiskColor, maskDisk);

    outColor = col;
}