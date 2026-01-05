#ifndef PI
#define PI 3.14159265359
#endif

// --- Helper Functions ---

// Smooth Min (Soft Union)
float smin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / max(k, 0.0001), 0.0, 1.0);
    return lerp(b, a, h) - k * h * (1.0 - h);
}

// Smooth Max (Soft Intersection/Subtraction)
float smax(float a, float b, float k) {
    return -smin(-a, -b, k);
}

// Rounded Box SDF
float sdRoundBox(float2 p, float2 b, float r) {
    float2 q = abs(p) - b + r;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

// Approximate Ellipse SDF (good for non-uniform scaling)
float sdEllipseApprox(float2 p, float2 r) {
    float k0 = length(p / max(r, 0.0001));
    return (k0 - 1.0) * min(r.x, r.y);
}

// Composite Source Over Destination
float4 compositeOver(float4 src, float4 dst) {
    float a = src.a + dst.a * (1.0 - src.a);
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-6);
    return float4(c, a);
}

// --- Main Function ---
// Generates a cartoon fedora hat with adjustable crown, brim, band, and outline.
void FedoraHat_float(float2 UV, float Size, float CrownWidth, float CrownHeight, float CrownIndent, float BrimWidth, float BrimCurvature, float BandThickness, float4 HatColor, float4 BandColor, float OutlineWidth, float4 OutlineColor, out float4 outColor) {
    // 1. Center and Scale UV
    float2 p = (UV - 0.5) * 2.0;
    p /= max(Size, 0.0001);
    
    // 2. Define Dimensions & Anchors
    float halfCW = CrownWidth * 0.5;
    float halfCH = CrownHeight * 0.5;
    float2 crownCenter = float2(0.0, 0.1); // Shift up slightly to fit brim
    float crownBaseY = crownCenter.y - halfCH;
    
    // 3. Crown SDF
    // Base rounded box
    float roundness = 0.15 * CrownWidth;
    float dCrownBase = sdRoundBox(p - crownCenter, float2(halfCW, halfCH), roundness);
    
    // Indent (Concave top)
    // Subtract a sphere from the top center
    // Position the sphere so it cuts into the top edge
    float indentRadius = halfCW * 0.9;
    float2 indentPos = crownCenter + float2(0.0, halfCH + indentRadius - CrownIndent);
    float dIndentSphere = length(p - indentPos) - indentRadius;
    
    // Apply smooth subtraction: max(Crown, -Indent)
    float dCrown = smax(dCrownBase, -dIndentSphere, 0.08);
    
    // 4. Brim SDF
    // Local coordinates for brim, anchored at crown base
    float2 brimP = p - float2(0.0, crownBaseY);
    // Apply curvature: bend Y downwards based on X distance squared
    brimP.y -= -BrimCurvature * (brimP.x * brimP.x);
    
    // Wide flattened ellipse for brim
    float brimThickness = 0.02;
    float dBrim = sdEllipseApprox(brimP, float2(BrimWidth * 0.5, brimThickness));
    
    // 5. Combine Shapes
    // Smooth union to blend brim and crown organically
    float dShape = smin(dCrown, dBrim, 0.04);
    
    // 6. Rendering / Coloring
    float aa = fwidth(dShape);
    
    // -- Mask for Hatband --
    // Band sits at the base of the crown. We check vertical range relative to crown base.
    // We strictly mask it to the Crown shape (dCrown) to avoid painting the brim.
    float bandLocalY = p.y - crownBaseY;
    float inBandY = step(0.0, bandLocalY) * step(bandLocalY, BandThickness);
    // To ensure band doesn't bleed onto the wide brim, we check if we are 'physically' in the crown area
    // Simple approximation: check if dCrown is smaller (dominant) than dBrim
    float isCrownDom = step(dCrown, dBrim + 0.01);
    float bandMask = inBandY * isCrownDom;
    
    // -- Fill Color --
    float4 finalFill = lerp(HatColor, BandColor, bandMask);
    float fillAlpha = 1.0 - smoothstep(0.0, aa, dShape);
    float4 fillLayer = float4(finalFill.rgb, finalFill.a * fillAlpha);
    
    // -- Outline Stroke --
    // Center the stroke on the edge (d=0). Width is total width.
    float halfStroke = max(OutlineWidth, 0.0) * 0.5;
    float strokeDist = abs(dShape) - halfStroke;
    float strokeAlpha = 1.0 - smoothstep(0.0, aa, strokeDist);
    float4 strokeLayer = float4(OutlineColor.rgb, OutlineColor.a * strokeAlpha);
    
    // 7. Composite Stroke over Fill
    outColor = compositeOver(strokeLayer, fillLayer);
}

// ------------------------------------------------------------------------
//  Visual Result
// ------------------------------------------------------------------------
//  This function generates a **stylized cartoon fedora** using 
//  Signed Distance Functions (SDFs).
//
//  The visual result is composed of:
//  - A central **crown** featuring a characteristic concave indentation 
//    (pinch) at the top.
//  - A wide, curved **brim** extending outward from the base of the crown.
//  - A decorative **hat band** (ribbon) wrapping around the bottom of the 
//    crown, distinct from the main hat color.
//
//  The shape features adjustable parameters for the crown dimensions and 
//  indent depth, the width and curvature of the brim, and the thickness of 
//  the hat band.
//
//  The output is a flat-shaded graphic with a cohesive outline that creates
//  a smooth, organic union between the brim and the crown, suitable for 
//  detective icons, noir themes, or character accessories.
// ------------------------------------------------------------------------