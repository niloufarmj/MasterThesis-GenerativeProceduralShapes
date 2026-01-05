#ifndef PI
#define PI 3.14159265359
#endif

// --- Helper Functions ---

// 2D Random
float2 hash22(float2 p) {
    float3 p3 = frac(float3(p.xyx) * float3(.1031, .1030, .0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return frac((p3.xx+p3.yz)*p3.zy);
}

// Signed Distance to an Isosceles Trapezoid
// r1: bottom half-width, r2: top half-width, he: half-height
float sdTrapezoid(float2 p, float r1, float r2, float he) {
    float2 k1 = float2(r2, he);
    float2 k2 = float2(r2 - r1, 2.0 * he);
    p.x = abs(p.x);
    float2 ca = float2(p.x - min(p.x, (p.y < 0.0) ? r1 : r2), abs(p.y) - he);
    float2 cb = p - k1 + k2 * clamp(dot(k1 - p, k2) / dot(k2, k2), 0.0, 1.0);
    float s = (cb.x < 0.0 && ca.y < 0.0) ? -1.0 : 1.0;
    return s * sqrt(min(dot(ca, ca), dot(cb, cb)));
}

// Signed Distance to a Circle
float sdCircle(float2 p, float r) {
    return length(p) - r;
}

// Signed Distance to a Rhombus (Diamond)
float sdRhombus(float2 p, float2 b) {
    p = abs(p);
    float h = clamp(0.5 + 0.5 * (b.x * p.x - b.y * p.y) / (b.x * b.y), 0.0, 1.0);
    return length(p - float2(b.x, b.y) * h) * sign(p.x * b.y + p.y * b.x - b.x * b.y);
}

// Smooth Min for blending shapes
float smin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return lerp(b, a, h) - k * h * (1.0 - h);
}

// --- Main Function ---
// Request: Cartoon cupcake with trapezoid cup, ribbed surface, bulbous cap with lobes, chips.
void CartoonCupcake_float(float2 UV, 
                          float2 CupWidths,   // x=Bottom, y=Top
                          float CupHeight,    // Total Height
                          float4 CupColor,    // Base Color
                          float2 RibProps,    // x=Count, y=Opacity
                          float2 CapSize,     // x=Width, y=Height
                          float2 CapLobes,    // x=Count, y=Size
                          float4 CapColor,    // Frosting Color
                          float3 ChipProps,   // x=Density, y=Size, z=ShapeMix
                          float4 ChipColor,   // Topping Color
                          out float4 outColor) 
{
    // 1. Setup Center Coordinates
    // Center the cupcake vertically based on heights
    float totalH = CupHeight + CapSize.y;
    float yOffset = (CapSize.y - CupHeight) * 0.5;
    float2 p = (UV - 0.5) * 2.0; // Range [-1, 1]
    p.y -= yOffset * 0.5; // Visual centering

    float aa = 0.01; // Soft edge amount

    // --- 2. Cup Shape ---
    // Cup is placed below y=0
    float cupHalfHeight = CupHeight * 0.5;
    float2 pCup = p - float2(0.0, -cupHalfHeight);
    float cupDist = sdTrapezoid(pCup, CupWidths.x * 0.5, CupWidths.y * 0.5, cupHalfHeight);
    float cupAlpha = smoothstep(aa, -aa, cupDist);

    // Cup Ribs Pattern
    // Calculate width at current Y for perspective correctness
    float t_cup = clamp((pCup.y + cupHalfHeight) / CupHeight, 0.0, 1.0);
    float currentWidth = lerp(CupWidths.x, CupWidths.y, t_cup) * 0.5;
    // Map x to [-1,1] relative to current width
    float ribU = pCup.x / max(currentWidth, 0.001);
    // Sine wave pattern for ribs
    float ribPattern = smoothstep(0.0, 1.0, abs(sin(ribU * PI * RibProps.x)));
    // Blend rib color
    float4 finalCupColor = lerp(CupColor, CupColor * 0.8, ribPattern * RibProps.y);
    finalCupColor = float4(finalCupColor.rgb * cupAlpha, cupAlpha);

    // --- 3. Cap (Muffin Top) Shape ---
    // Cap is placed above y=0
    float capHalfHeight = CapSize.y * 0.5;
    // Adjust cap center so the bottom lobes sit near the cup rim
    // Main dome is an ellipse
    float2 pCap = p - float2(0.0, capHalfHeight * 0.6);
    float domeDist = length(pCap / (CapSize * 0.5)) - 1.0;
    // Fix distance metric distortion for ellipse roughly
    domeDist *= min(CapSize.x, CapSize.y) * 0.5;

    // Lobe shapes at the bottom edge of the cap
    float lobeCount = max(1.0, floor(CapLobes.x));
    float lobeSize = CapLobes.y;
    float lobeSpan = CapSize.x * 0.9; // Spanning most of the cap width
    float lobeDist = 100.0;
    
    // Combine lobes
    for(float i = 0.0; i < lobeCount; i++) {
        // Normalized position 0..1
        float t_lobe = i / max(lobeCount - 1.0, 1.0);
        // Map to x position
        float lx = lerp(-lobeSpan * 0.5, lobeSpan * 0.5, t_lobe);
        // Add slight arch to lobes (y offset)
        float ly = sin(t_lobe * PI) * 0.05;
        // Distance to this lobe circle
        float d = sdCircle(p - float2(lx, ly), lobeSize);
        lobeDist = min(lobeDist, d);
    }

    // Combine Dome and Lobes
    float capDist = smin(domeDist, lobeDist, 0.05);
    float capAlpha = smoothstep(aa, -aa, capDist);

    // --- 4. Toppings (Chips) ---
    // Grid based scattering
    float chipDensity = ChipProps.x;
    float2 gridUV = p * chipDensity;
    float2 cellID = floor(gridUV);
    float2 cellUV = frac(gridUV) - 0.5;
    
    // Randomness per cell
    float2 rand = hash22(cellID);
    float2 chipOffset = (rand - 0.5) * 0.6; // Jitter position
    float2 pChip = cellUV - chipOffset;
    
    // Random shape selection
    float chipDist = 1.0;
    float chipSizeLocal = ChipProps.y * chipDensity; // Scale relative to grid
    
    if (rand.x > ChipProps.z) {
        // Diamond shape
        chipDist = sdRhombus(pChip, float2(chipSizeLocal, chipSizeLocal * 1.3));
    } else {
        // Circle shape
        chipDist = sdCircle(pChip, chipSizeLocal);
    }
    
    float chipAlpha = smoothstep(aa * chipDensity, -aa * chipDensity, chipDist);
    
    // Mask chips to only appear inside the cap
    float chipMask = chipAlpha * smoothstep(0.0, 0.05, -capDist); // Hard mask by cap

    // --- 5. Compositing ---
    // Start with background (transparent)
    float4 col = float4(0,0,0,0);

    // Layer 1: Cup
    col = lerp(col, finalCupColor, finalCupColor.a);

    // Layer 2: Cap
    float4 finalCapColor = float4(CapColor.rgb * capAlpha, capAlpha);
    // Alpha blend cap over cup
    float3 outRGB = finalCapColor.rgb + col.rgb * (1.0 - finalCapColor.a);
    float outA = finalCapColor.a + col.a * (1.0 - finalCapColor.a);
    col = float4(outRGB, outA);

    // Layer 3: Toppings
    float4 finalChipColor = float4(ChipColor.rgb * chipMask, chipMask);
    outRGB = finalChipColor.rgb + col.rgb * (1.0 - finalChipColor.a);
    outA = finalChipColor.a + col.a * (1.0 - finalChipColor.a);
    
    outColor = float4(outRGB, outA);
}

// ------------------------------------------------------------------------
//  Visual Result (High-level, parameter-invariant description)
// ------------------------------------------------------------------------
//  This function generates a **stylized 2D cartoon cupcake** using
//  Signed Distance Functions (SDFs).
//
//  The visual result is composed of:
//  - A trapezoidal cup base with a procedural pleated/ribbed texture.
//  - A bulbous, soft frosting cap ("muffin top") formed by a smooth dome
//    blended with scalloped lobes along the bottom edge.
//  - Scattered toppings (chips) on the frosting, which appear randomly
//    as either circles or diamonds.
//
//  The rendering layers these elements (Cup -> Frosting -> Toppings)
//  with soft alpha blending. All dimensions, rib density, frosting shape,
//  and topping density are fully adjustable.
//
//  The output is an anti-aliased RGBA color suitable for food icons,
//  bakery themes, and game rewards.
// ------------------------------------------------------------------------