#ifndef PI
#define PI 3.14159265359
#endif

// --- Helper Functions ---

// 2D Rotation
float2 rotate(float2 p, float a) {
    float c = cos(a);
    float s = sin(a);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

// Signed Distance to a Line Segment
float sdSegment(float2 p, float2 a, float2 b) {
    float2 pa = p - a;
    float2 ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}

// Signed Pseudo-Distance to an Axis-Aligned Ellipse
float sdEllipseApprox(float2 p, float2 halfAxes) {
    float a = max(halfAxes.x, 1e-6);
    float b = max(halfAxes.y, 1e-6);
    float x = abs(p.x);
    float y = abs(p.y);
    
    // Implicit equation F = x^2/a^2 + y^2/b^2 - 1
    float F = (x * x) / (a * a) + (y * y) / (b * b) - 1.0;
    
    // Gradient length approx
    float gradLen = 2.0 * sqrt((x * x) / (a * a * a * a) + (y * y) / (b * b * b * b));
    
    return F / max(gradLen, 1e-6);
}

// --- Main Function ---
// User Request: A cartoon cherry pair with symmetric fruits, stems, leaves, and optional faces.

void CartoonCherryPair_float(
    float2 UV,
    float FruitRadius,
    float4 FruitColor,
    float StemLength,
    float StemThickness,
    float StemAngle,
    float4 StemColor,
    float2 LeafSize,
    float LeafAngle,
    float4 LeafColor,
    float FaceSize,
    out float4 outColor)
{
    // PLAN:
    // 1. Center UV coordinates to (0.5, 0.5) and offset vertically to center the cherries.
    // 2. Define the geometry: Junction point, Fruit centers derived from StemAngle/Length.
    // 3. Compute SDFs for Stems (segments), Leaves (ellipses), and Fruits (circles).
    // 4. Compute Face SDFs (eyes, mouth, blush) relative to fruit centers, if FaceSize > 0.
    // 5. Composite colors using smoothstep anti-aliasing and standard alpha blending.

    // 1. Setup Coordinates
    float2 p = UV - 0.5;
    p.y -= 0.1; // Shift composition up slightly
    
    // Anti-aliasing width
    float aa = fwidth(length(p));
    aa = max(aa, 0.001);

    // 2. Geometry Definitions
    float2 junction = float2(0.0, 0.2); // Top connection point

    // Calculate fruit positions based on stem angle and length
    // StemAngle is deviation from vertical (0 = straight down)
    float sa = sin(StemAngle);
    float ca = cos(StemAngle);
    
    float2 dirR = float2(sa, -ca);  // Right stem direction
    float2 dirL = float2(-sa, -ca); // Left stem direction
    
    float2 fruitPosR = junction + dirR * StemLength;
    float2 fruitPosL = junction + dirL * StemLength;

    // 3. Shape SDFs
    
    // --- Stems ---
    float dStemR = sdSegment(p, junction, fruitPosR);
    float dStemL = sdSegment(p, junction, fruitPosL);
    // Combine stems and subtract thickness
    float dStems = min(dStemR, dStemL) - StemThickness;

    // --- Leaves ---
    // Leaves attach at junction, rotated by LeafAngle
    // Leaf local origin is at the attachment point
    float2 pLeaf = p - junction;
    
    // Right Leaf (Rotate CW)
    float2 pLR = rotate(pLeaf, -LeafAngle);
    // Offset by radius.x so the edge touches the origin (junction)
    float dLeafR = sdEllipseApprox(pLR - float2(LeafSize.x, 0.0), LeafSize);
    
    // Left Leaf (Rotate CCW)
    float2 pLL = rotate(pLeaf, LeafAngle);
    float dLeafL = sdEllipseApprox(pLL - float2(-LeafSize.x, 0.0), LeafSize);
    
    float dLeaves = min(dLeafR, dLeafL);

    // --- Fruits ---
    float dFruitR = length(p - fruitPosR) - FruitRadius;
    float dFruitL = length(p - fruitPosL) - FruitRadius;
    float dFruits = min(dFruitR, dFruitL);

    // 4. Face Features (Masks)
    float maskEyes = 0.0;
    float maskMouth = 0.0;
    float maskBlush = 0.0;
    
    if (FaceSize > 0.01) {
        // Scaling factors for features
        float fs = clamp(FaceSize, 0.1, 2.0);
        
        // Offsets relative to fruit center
        float eyeX = FruitRadius * 0.35;
        float eyeY = FruitRadius * 0.1;
        float eyeRad = FruitRadius * 0.12 * fs;
        
        float mouthY = -FruitRadius * 0.1;
        float mouthRad = FruitRadius * 0.3 * fs;
        float mouthThick = FruitRadius * 0.05 * fs;
        
        float blushX = FruitRadius * 0.55;
        float blushRad = FruitRadius * 0.25 * fs;

        // Helper macro or inline logic for features on a specific fruit point 'q'
        // To keep it valid HLSL without lambdas, we repeat logic for L and R
        
        // --- Right Face ---
        float2 qR = p - fruitPosR;
        // Eyes (two small circles)
        float dEyesR = min(length(qR - float2(eyeX, eyeY)), 
                           length(qR - float2(-eyeX, eyeY))) - eyeRad;
        
        // Mouth (Smile: Lower part of a ring)
        float2 mouthCenter = float2(0.0, mouthY + mouthRad * 0.5);
        float dMouthRingR = abs(length(qR - mouthCenter) - mouthRad) - mouthThick;
        float dMouthBoxR = -(qR.y - mouthCenter.y); // Cut top half
        float dMouthR = max(dMouthRingR, -dMouthBoxR);
        
        // Blush (Distance to centers)
        float dBlushDistR = min(length(qR - float2(blushX, 0)), length(qR - float2(-blushX, 0)));

        // --- Left Face ---
        float2 qL = p - fruitPosL;
        float dEyesL = min(length(qL - float2(eyeX, eyeY)), 
                           length(qL - float2(-eyeX, eyeY))) - eyeRad;
                           
        float dMouthRingL = abs(length(qL - mouthCenter) - mouthRad) - mouthThick;
        float dMouthBoxL = -(qL.y - mouthCenter.y);
        float dMouthL = max(dMouthRingL, -dMouthBoxL);
        
        float dBlushDistL = min(length(qL - float2(blushX, 0)), length(qL - float2(-blushX, 0)));

        // Combine
        float dEyes = min(dEyesR, dEyesL);
        float dMouth = min(dMouthR, dMouthL);
        float dBlushDist = min(dBlushDistR, dBlushDistL);
        
        // Generate Masks
        maskEyes = 1.0 - smoothstep(0.0, aa, dEyes);
        maskMouth = 1.0 - smoothstep(0.0, aa, dMouth);
        // Soft blush gradient
        maskBlush = 1.0 - smoothstep(0.0, blushRad, dBlushDist);
    }

    // 5. Composition (Painter's Algorithm)
    // Initialize with transparent
    float4 col = float4(0.0, 0.0, 0.0, 0.0);
    
    // Draw Stems
    float maskStems = 1.0 - smoothstep(0.0, aa, dStems);
    col = lerp(col, StemColor, maskStems * StemColor.a);
    
    // Draw Leaves
    float maskLeaves = 1.0 - smoothstep(0.0, aa, dLeaves);
    col = lerp(col, LeafColor, maskLeaves * LeafColor.a);
    
    // Draw Fruits
    float maskFruits = 1.0 - smoothstep(0.0, aa, dFruits);
    col = lerp(col, FruitColor, maskFruits * FruitColor.a);
    
    // Draw Face Features (Overlaid on fruits)
    if (FaceSize > 0.01) {
        float4 FaceColor = float4(0.15, 0.1, 0.1, 1.0); // Dark color for eyes/mouth
        float4 BlushColor = float4(1.0, 0.6, 0.7, 0.6); // Soft pink blush
        
        // Add Blush (additive or mix)
        col = lerp(col, float4(BlushColor.rgb, 1.0), maskBlush * BlushColor.a);
        
        // Add Eyes and Mouth
        float maskFeatures = max(maskEyes, maskMouth);
        col = lerp(col, FaceColor, maskFeatures * FaceColor.a);
    }

    outColor = col;
}

// ------------------------------------------------------------------------
//  Visual Result (High-level, parameter-invariant description)
// ------------------------------------------------------------------------
//  This function generates a **stylized 2D cartoon cherry pair** using
//  Signed Distance Functions (SDFs).
//
//  The visual result is composed of:
//  - Two symmetric circular fruit bodies connected by linear stems to a
//    central top junction.
//  - Two elliptical leaves attached at the junction point.
//  - Optional "Kawaii" facial features (eyes, smile, and blush) drawn
//    on each fruit.
//
//  The rendering uses a flat cartoon style with distinct colors for stems,
//  leaves, and fruits. The geometry (stem angle, leaf size, face scale)
//  is fully adjustable.
//
//  The output is an anti-aliased RGBA color suitable for game items,
//  slot machine icons, and cute UI elements.
// ------------------------------------------------------------------------