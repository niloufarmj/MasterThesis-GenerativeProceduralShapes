// User Request: A simple progress bar with two rectangles (inner/outer), editable dimensions, color, corner radius, padding, and fill.

#ifndef PI
#define PI 3.14159265359
#endif

// --- Helper Functions ---

// Alpha Blending (Source Over Destination)
float4 blend_over(float4 src, float4 dst) {
    float finalA = src.a + dst.a * (1.0 - src.a);
    // Prevent division by zero in alpha compositing
    float3 finalRGB = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(finalA, 0.00001);
    return float4(finalRGB, finalA);
}

// Signed Distance to a Rounded Box
// p: sample position (centered)
// b: half-extents (width/2, height/2)
// r: corner radius
float sdRoundedBox(float2 p, float2 b, float r) {
    float2 q = abs(p) - b + r;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

// --- Main Function ---
// PLAN:
// 1. Center UV coordinates to (0,0).
// 2. Compute Outer Rectangle (Background) SDF and Mask.
// 3. Compute Inner Rectangle (Fill) dimensions based on Fill amount and Padding.
// 4. Offset Inner Rectangle center so it expands from left to right.
// 5. Compute Inner SDF and Mask.
// 6. Composite Inner layer OVER Outer layer using alpha blending.

void ProgressBarShape_float(float2 UV, float Width, float Height, float Fill, float Padding, float OuterRadius, float InnerRadius, float4 OuterColor, float4 InnerColor, out float4 outColor) {
    // 1. Center UV coordinates
    float2 p = UV - 0.5;
    
    // 2. Outer Rectangle (Background)
    float2 outerSize = float2(max(Width, 0.0), max(Height, 0.0));
    float2 outerHalf = outerSize * 0.5;
    
    // Clamp outer radius to ensure it fits within the box
    float rOuter = min(OuterRadius, min(outerHalf.x, outerHalf.y));
    rOuter = max(rOuter, 0.0);
    
    float dOuter = sdRoundedBox(p, outerHalf, rOuter);
    
    // Calculate Anti-Aliasing (AA) width using screen-space derivatives
    float aa = fwidth(dOuter);
    aa = max(aa, 0.0001); // fallback for constant cases
    
    float outerMask = 1.0 - smoothstep(-aa, aa, dOuter);
    float4 outerLayer = float4(OuterColor.rgb, OuterColor.a * outerMask);
    
    // 3. Inner Rectangle (Fill)
    // Calculate maximum possible inner size after padding
    float2 innerMaxHalf = (outerSize - 2.0 * Padding) * 0.5;
    innerMaxHalf = max(innerMaxHalf, 0.0);
    
    // Apply fill ratio (0 to 1) to width only
    float fillRatio = saturate(Fill);
    float2 innerHalf = float2(innerMaxHalf.x * fillRatio, innerMaxHalf.y);
    
    // 4. Offset Inner Position (Expand from Left)
    // Outer Left Edge X = -outerHalf.x
    // Inner Start X = -outerHalf.x + Padding
    // Inner Center X = Inner Start X + currentHalfWidth
    float innerCenterX = -outerHalf.x + Padding + innerHalf.x;
    float2 pInner = p - float2(innerCenterX, 0.0);
    
    // Clamp inner radius
    float rInner = min(InnerRadius, min(innerHalf.x, innerHalf.y));
    rInner = max(rInner, 0.0);
    
    float dInner = sdRoundedBox(pInner, innerHalf, rInner);
    
    float innerMask = 1.0 - smoothstep(-aa, aa, dInner);
    float4 innerLayer = float4(InnerColor.rgb, InnerColor.a * innerMask);
    
    // 6. Composite Layers (Inner over Outer)
    outColor = blend_over(innerLayer, outerLayer);
}

// ------------------------------------------------------------------------
//  Visual Result (High-level, parameter-invariant description)
// ------------------------------------------------------------------------
//  This function generates a **customizable UI progress bar** using
//  Signed Distance Functions (SDFs).
//
//  The visual result is composed of:
//  - An **Outer Container**: A rounded rectangle serving as the background track.
//  - An **Inner Fill**: A smaller rounded rectangle that expands horizontally 
//    from left to right based on a "Fill" percentage.
//
//  The geometry features adjustable dimensions, corner radii (independent for 
//  inner/outer), and padding between the fill and the container. 
//
//  The output is an anti-aliased RGBA color suitable for HUDs (health/mana bars),
//  loading screens, and interface sliders.
// ------------------------------------------------------------------------