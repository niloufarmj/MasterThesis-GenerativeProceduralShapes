#ifndef PI
#define PI 3.14159265359
#endif

// --- Helper Functions ---
// Standard 2D rotation around the origin
float2 rotate(float2 p, float angle) {
    float c = cos(angle);
    float s = sin(angle);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

// Smooth Minimum for merging shapes organically
float smin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return lerp(b, a, h) - k * h * (1.0 - h);
}

// Signed Distance to a Box
float sdBox(float2 p, float2 b) {
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// Signed Distance to an Ellipse (IQ's approximation)
float sdEllipse(float2 p, float2 r) {
    float k0 = length(p / r);
    float k1 = length(p / (r * r));
    return k0 * (k0 - 1.0) / k1;
}

// --- Main Function ---
// Draws a cartoon tulip with adjustable blossom shape, stem, and leaves
void CartoonTulip_float(
    float2 UV,
    float2 BlossomSize,
    float OpeningAngle,
    float4 BlossomColor,
    float StemThickness,
    float4 StemColor,
    float2 LeafSize,
    float LeafHeight,
    float LeafCurvature,
    out float4 outColor)
{
    // PLAN:
    // 1) Normalize UVs to center the flower base.
    // 2) Create Stem SDF (vertical box).
    // 3) Create Leaf SDF (two symmetrical, bent ellipses attached to stem).
    // 4) Create Blossom SDF (Union of 3 petals: 1 center, 2 rotated/shifted sides).
    // 5) Composite colors with anti-aliasing (Blossom over Leaves over Stem).

    // 1. Coordinate Setup
    float2 p = UV - 0.5;
    // Shift y so (0,0) is roughly the base of the flower head
    // This makes the flower center screen relative to the blossom
    p.y += 0.1; 

    // 2. Stem Generation
    // Stem extends downwards from y=0
    float stemLen = 0.6;
    // Center the stem box vertically relative to its length
    float2 pStem = p - float2(0.0, -stemLen * 0.5);
    float dStem = sdBox(pStem, float2(StemThickness * 0.5, stemLen * 0.5));

    // 3. Leaf Generation
    // Determine attachment point on stem (0.0 = bottom of stem, 1.0 = top)
    float attachY = -stemLen * (1.0 - clamp(LeafHeight, 0.0, 1.0));
    
    // Transform for leaves
    float2 pLeaf = p - float2(0.0, attachY);
    pLeaf.x = abs(pLeaf.x); // Symmetry for two leaves
    
    // Rotate leaves outward (approx 45 degrees + curvature influence)
    float leafBaseAngle = 0.6; // ~35 degrees
    pLeaf = rotate(pLeaf, -leafBaseAngle);
    
    // Apply bending (parabolic distortion)
    // p.x represents width, p.y represents length after rotation
    pLeaf.x -= LeafCurvature * 2.0 * (pLeaf.y * pLeaf.y);
    
    // Offset ellipse so the pivot (0,0) is at the bottom tip
    float2 actualLeafSize = max(LeafSize, float2(0.01, 0.01));
    pLeaf.y -= actualLeafSize.y; // Shift center up by half length
    
    // Leaf SDF
    float dLeaf = sdEllipse(pLeaf, float2(actualLeafSize.x * 0.5, actualLeafSize.y));

    // Union Stem and Leaves (Greenery)
    // Use smin for a smooth joint where leaf meets stem
    float dGreenery = smin(dStem, dLeaf, 0.03);

    // 4. Blossom Generation
    // Base of blossom is at p=(0,0). 
    float2 pBlossom = p;
    float2 bSize = max(BlossomSize, float2(0.01, 0.01));

    // Center Petal (Main body)
    // Shift up slightly so the ellipse center is proper
    float2 pCenterPetal = pBlossom - float2(0.0, bSize.y * 0.5);
    float dCenter = sdEllipse(pCenterPetal, float2(bSize.x * 0.5, bSize.y * 0.6));

    // Side Petals (The "Cup" shape)
    // Mirror X, Rotate, and shift outwards to create the tulip opening
    float2 pSide = pBlossom;
    pSide.x = abs(pSide.x);
    // Pivot is near bottom, rotate outward by OpeningAngle
    pSide.y -= bSize.y * 0.2; // Move pivot up slightly
    pSide = rotate(pSide, -OpeningAngle);
    pSide.y += bSize.y * 0.2; // Restore pivot
    
    // Shift side petals outward to widen the cup
    pSide.x -= bSize.x * 0.25;
    pSide.y -= bSize.y * 0.5; // Center vertically like main petal
    
    float dSide = sdEllipse(pSide, float2(bSize.x * 0.35, bSize.y * 0.6));

    // Smooth union of petals to form a single cup
    // A slightly larger k gives a smoother, more organic blossom shape
    float dBlossom = smin(dCenter, dSide, 0.08);

    // 5. Compositing
    float aa = fwidth(p.y); // Analytic anti-aliasing width
    aa = max(aa, 0.001);

    // Masks (1.0 = opaque, 0.0 = transparent)
    float maskGreen = smoothstep(aa, -aa, dGreenery);
    float maskBlossom = smoothstep(aa, -aa, dBlossom);

    // Layering: Start with transparent
    float4 result = float4(0,0,0,0);
    
    // Draw Greenery
    result = lerp(result, StemColor, maskGreen * StemColor.a);
    
    // Draw Blossom (on top of stem)
    // We do a standard alpha blend over the existing color
    float4 bCol = BlossomColor;
    float alphaB = maskBlossom * bCol.a;
    
    // Simple alpha compositing: Color = Source*Alpha + Dest*(1-Alpha)
    result.rgb = bCol.rgb * alphaB + result.rgb * (1.0 - alphaB);
    result.a = max(result.a, alphaB); // Keep max alpha

    outColor = result;
}