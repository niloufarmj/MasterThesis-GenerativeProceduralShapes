/* 
  Cartoon Bitten Apple SDF Generator
  User Request: Cartoon bitten apple icon with adjustable size, width, height, color, bite radius/pos, leaf size/angle, and outline.
*/

#ifndef PI
#define PI 3.14159265359
#endif

// --- Helper Functions ---

// 2D Rotation matrix
float2 nm_rotate(float2 p, float angle) {
    float c = cos(angle);
    float s = sin(angle);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

// Polynomial Smooth Min (for organic blending)
float nm_smin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return lerp(b, a, h) - k * h * (1.0 - h);
}

// Circle SDF
float nm_sdCircle(float2 p, float r) {
    return length(p) - r;
}

// Vesica SDF (Lens shape) - intersection of two circles
// r = radius of circles, d = offset from center. Shape is vertical.
float nm_sdVesica(float2 p, float r, float d) {
    p = abs(p);
    float b = sqrt(r * r - d * d);
    return ((p.y - b) * d > p.x * b) ? length(p - float2(0.0, b))
                                     : length(p - float2(-d, 0.0)) - r;
}

// --- Main Function ---

void CartoonBittenApple_float(
    float2 UV,
    float Size,
    float AppleWidth,
    float AppleHeight,
    float4 AppleColor,
    float4 LeafColor,
    float4 OutlineColor,
    float OutlineThickness,
    float BiteRadius,
    float BiteOffsetY,
    float LeafSize,
    float LeafAngle,
    out float4 outColor)
{
    // PLAN:
    // 1. Center UVs to (-1, 1) range and scale by Size.
    // 2. Build Apple Body SDF using 3 circles (one bottom, two top lobes) smooth-blended.
    // 3. Build Bite SDF (circle) and subtract from Body.
    // 4. Build Leaf SDF (vesica/lens), translate above apple and rotate.
    // 5. Union Leaf and Bitten Body.
    // 6. Calculate Outline and Fill masks.
    // 7. Composite colors (Outline > Leaf/Apple Fill).

    // 1. Setup Domain
    float2 p = (UV - 0.5) * 2.0;
    p /= max(Size, 0.001); // Avoid divide by zero

    // 2. Apple Body Construction
    // Bottom body circle
    float rBottom = AppleWidth * 0.55;
    float2 posBottom = float2(0.0, -AppleHeight * 0.25);
    float dBottom = nm_sdCircle(p - posBottom, rBottom);

    // Top Lobes (Left and Right)
    float rLobe = AppleWidth * 0.38;
    float2 posLobeL = float2(-AppleWidth * 0.3, AppleHeight * 0.28);
    float2 posLobeR = float2(AppleWidth * 0.3, AppleHeight * 0.28);
    
    float dLobeL = nm_sdCircle(p - posLobeL, rLobe);
    float dLobeR = nm_sdCircle(p - posLobeR, rLobe);
    
    // Smooth blend lobes, then blend with bottom
    float dLobes = nm_smin(dLobeL, dLobeR, 0.05);
    float dAppleRaw = nm_smin(dBottom, dLobes, 0.2); // Higher k for smooth body merge

    // 3. Bite Subtraction
    // Bite is a circle on the right side
    float2 bitePos = float2(AppleWidth * 0.55, AppleHeight * 0.1 + BiteOffsetY);
    float dBite = nm_sdCircle(p - bitePos, BiteRadius);
    
    // Subtract bite: max(d, -dBite)
    float dAppleBitten = max(dAppleRaw, -dBite);

    // 4. Leaf Construction
    // Position leaf floating above the apple
    float2 leafBasePos = float2(0.0, AppleHeight * 0.65);
    float2 pLeaf = p - leafBasePos;
    
    // Rotate leaf
    pLeaf = nm_rotate(pLeaf, LeafAngle);
    
    // Leaf Shape (Vesica)
    // r = curvature radius, d = offset. Ensure d < r for valid lens.
    float rLeaf = max(LeafSize, 0.01);
    float dLeafOffset = rLeaf * 0.65; // Controls width of the lens
    float dLeaf = nm_sdVesica(pLeaf, rLeaf, dLeafOffset);

    // 5. Final SDF Composition (Union of Apple and Leaf)
    // We keep them separate for coloring, but 'dFinal' represents the whole shape distance
    float dFinal = min(dAppleBitten, dLeaf);

    // 6. Rendering / Masks
    // Anti-aliasing width
    float aa = fwidth(dFinal);
    aa = max(aa, 0.001); // Safety for preview window

    // Fill Mask (Inside the shape)
    float fillMask = smoothstep(aa, -aa, dFinal);
    
    // Outline Mask (Band around the edge)
    float outlineWidthHalf = max(OutlineThickness, 0.0) * 0.5;
    float outlineDist = abs(dFinal) - outlineWidthHalf;
    float outlineMask = smoothstep(aa, -aa, outlineDist);

    // 7. Color Compositing
    // Determine which fill color to use (Apple or Leaf) based on which SDF is closer
    // We use a sharp transition step since they are detached or distinct parts
    float isLeaf = step(dLeaf, dAppleBitten); 
    float3 fillColorRGB = lerp(AppleColor.rgb, LeafColor.rgb, isLeaf);
    float fillAlpha = lerp(AppleColor.a, LeafColor.a, isLeaf);

    // Base color is the fill
    float4 result = float4(fillColorRGB, fillAlpha);
    
    // Apply Outline on top
    // Outline replaces the pixel if outlineMask is high
    // Use straight interpolation for color, but preserve alpha logic
    // This ensures outline is fully opaque if OutlineColor.a is 1
    result.rgb = lerp(result.rgb, OutlineColor.rgb, outlineMask);
    result.a = max(result.a * fillMask, outlineMask * OutlineColor.a); // Combine coverage

    // Mask the entire shape (Background transparency)
    // The shape exists where either fill or outline exists
    float shapeMask = max(fillMask, outlineMask);

    // Final Premultiplied Output
    outColor = float4(result.rgb * shapeMask, result.a * shapeMask);
}