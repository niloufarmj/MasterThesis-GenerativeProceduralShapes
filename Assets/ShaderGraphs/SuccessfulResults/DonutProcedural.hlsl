#ifndef PI
#define PI 3.14159265359
#endif

#ifndef TAU
#define TAU 6.28318530718
#endif

// --- Helper Functions ---

// Hash functions for procedural randomness
float donut_hash12(float2 p)
{
    float3 p3 = frac(float3(p.xyx) * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return frac((p3.x + p3.y) * p3.z);
}

float2 donut_hash22(float2 p)
{
    float3 p3 = frac(float3(p.xyx) * float3(.1031, .1030, .0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return frac((p3.xx + p3.yz) * p3.zy);
}

// SDF for a capsule (sprinkle)
float donut_sdSegment(float2 p, float2 a, float2 b)
{
    float2 pa = p - a, ba = b - a;
    float h = saturate(dot(pa, ba) / dot(ba, ba));
    return length(pa - ba * h);
}

// Main Donut Function
// Draws a cartoon donut with ring body, wavy icing, sprinkles, and outline.
void DonutProcedural_float(
    float2 UV,
    float Size,
    float OuterRadius,
    float InnerRadius,
    float4 DoughColor,
    float4 IcingColor,
    float IcingWaviness,
    float IcingFrequency,
    float SprinkleCount,
    float2 SprinkleParams, // x = thickness, y = length
    float4 SprinkleColor1,
    float4 SprinkleColor2,
    float OutlineThickness,
    float4 OutlineColor,
    out float4 outColor)
{
    // PLAN:
    // 1) Center and scale UV coordinates.
    // 2) Compute Dough SDF (ring) and Icing SDF (wavy ring).
    // 3) Loop to compute minimum SDF for sprinkles and determine their color.
    // 4) Compute AA masks for all layers (Dough, Icing, Sprinkles, Outline).
    // 5) Composite layers back-to-front or using standard alpha blending.

    // 1) Coordinate Setup
    float safeSize = max(Size, 0.001);
    float2 p = (UV - 0.5) / safeSize;
    
    // 2) Dough SDF (Torus / Ring)
    // A 2D ring is defined by the space between Outer and Inner radius
    // We use a single SDF value that is negative inside the ring
    float len = length(p);
    // Dist to outer edge
    float dOuter = len - OuterRadius;
    // Dist to inner hole (inverted so negative is inside dough)
    float dInner = InnerRadius - len;
    // Intersection: max of both constraints. If either is positive, we are outside.
    float dBody = max(dOuter, dInner);

    // 3) Icing SDF
    // Icing covers the top part, we simulate this as a wavy radius overlay
    // Angle for waviness
    float angle = atan2(p.y, p.x);
    // Base icing covers ~80% of the donut width by default, plus waves
    float icingBaseRadius = lerp(InnerRadius, OuterRadius, 0.8);
    float icingWave = sin(angle * IcingFrequency) * IcingWaviness;
    float dIcingEdge = len - (icingBaseRadius + icingWave);
    // Icing also stops at the inner hole
    float dIcing = max(dIcingEdge, dInner);

    // 4) Sprinkles SDF
    // We iterate a fixed number of times to place sprinkles
    float dSprinkles = 1000.0;
    float3 activeSprinkleColor = float3(0, 0, 0);
    
    // Limit loop to avoid TDR, clamp user input
    int count = clamp(int(SprinkleCount), 0, 32);
    
    // Fixed max iteration for unroll consistency
    for (int i = 0; i < 32; i++)
    {
        if (i >= count)
            break;
        
        // Random properties based on index
        float2 seed = float2(float(i) * 12.34, float(i) * 45.67);
        float2 rndPos = donut_hash22(seed);
        
        // Random polar position within the dough area
        float a = rndPos.x * TAU;
        // Distribute radially between Inner and Outer (with some padding)
        float r = lerp(InnerRadius + 0.05, OuterRadius - 0.05, rndPos.y);
        float2 pos = float2(cos(a), sin(a)) * r;
        
        // Random orientation
        float orient = donut_hash12(seed + 1.0) * TAU;
        float2 dir = float2(cos(orient), sin(orient));
        
        // Capsule start/end
        float hL = max(SprinkleParams.y, 0.01) * 0.5;
        float thick = max(SprinkleParams.x, 0.001);
        float2 sa = pos - dir * hL;
        float2 sb = pos + dir * hL;
        
        // SDF for this sprinkle
        float dSingle = donut_sdSegment(p, sa, sb) - thick;
        
        // Smooth union or hard union? Hard is fine for sprinkles.
        if (dSingle < dSprinkles)
        {
            dSprinkles = dSingle;
            // Pick color based on another hash
            float colHash = donut_hash12(seed + 2.0);
            activeSprinkleColor = (colHash > 0.5) ? SprinkleColor2.rgb : SprinkleColor1.rgb;
        }
    }

    // 5) Rendering / Compositing
    // We use fwidth for consistent anti-aliasing
    float aa = fwidth(dBody);
    aa = max(aa, 0.001);

    // Alpha masks (0 = transparent, 1 = opaque)
    // Body mask
    float alphaBody = 1.0 - smoothstep(0.0, aa, dBody);
    
    // Icing mask (clipped to body so it doesn't spill out invisible areas if configured weirdly)
    float alphaIcing = 1.0 - smoothstep(0.0, aa, dIcing);
    alphaIcing *= alphaBody; // Ensure icing stays on body
    
    // Sprinkle mask
    float alphaSprinkle = 1.0 - smoothstep(0.0, aa, dSprinkles);
    alphaSprinkle *= alphaBody; // Ensure sprinkles stay on body

    // Outline mask (border around the body)
    // We want the outline centered on the edge, or outside. 
    // "Consistent outline" usually implies a stroke over the silhouette.
    // Standard stroke SDF: abs(dBody) - width
    float halfStroke = max(OutlineThickness, 0.0) * 0.5;
    float dOutline = abs(dBody) - halfStroke;
    float alphaOutline = 1.0 - smoothstep(0.0, aa, dOutline);

    // Composite colors
    // Start with transparent
    float4 result = float4(0, 0, 0, 0);

    // Layer 1: Dough
    float4 colDough = float4(DoughColor.rgb, 1.0);
    // Blend dough over background (using dough alpha)
    // Since background is empty, premultiplied result is just (Color * alpha, alpha)
    result = float4(colDough.rgb * alphaBody, alphaBody);

    // Layer 2: Icing
    // Blend Icing over Dough
    // Mix logic: result = lerp(result, Icing, alphaIcing)
    // We need to handle alpha carefully. Since icing is inside body, alpha max is body alpha.
    result.rgb = lerp(result.rgb, IcingColor.rgb, alphaIcing);

    // Layer 3: Sprinkles
    result.rgb = lerp(result.rgb, activeSprinkleColor, alphaSprinkle);

    // Layer 4: Outline
    // Outline draws on top of everything at the edges
    // We use standard 'over' operator logic for the outline as a separate layer
    float4 colOutline = float4(OutlineColor.rgb, 1.0);
    
    // Standard composition: Out = Source + Dest * (1 - SourceAlpha)
    // But here we just want to interpolate the RGB where the outline exists
    // However, outline might extend OUTSIDE the body (increasing total alpha)
    
    // Let's compute a specific 'coverage' for the whole shape including outline
    // The total silhouette is determined by (dBody - halfStroke)
    float dTotal = dBody - halfStroke;
    float alphaTotal = 1.0 - smoothstep(0.0, aa, dTotal);
    
    // Re-composite for correctness:
    // 1. Fill Color (Dough + Icing + Sprinkles)
    float3 fillRGB = DoughColor.rgb;
    fillRGB = lerp(fillRGB, IcingColor.rgb, alphaIcing / max(alphaBody, 0.001));
    fillRGB = lerp(fillRGB, activeSprinkleColor, alphaSprinkle / max(alphaBody, 0.001));
    
    // 2. Stroke logic
    // Where are we? Inside fill? Inside stroke?
    // A simple approach for cartoon outlines: 
    // If we are in the stroke zone, use stroke color. Else use fill.
    // Stroke zone is where alphaOutline > 0
    
    // Interpolate final RGB
    float3 finalRGB = lerp(fillRGB, OutlineColor.rgb, alphaOutline);
    
    // Final output
    outColor = float4(finalRGB * alphaTotal, alphaTotal);
}

// ------------------------------------------------------------------------
//  Visual Result (High-level, parameter-invariant description)
// ------------------------------------------------------------------------
//  This function generates a **stylized 2D cartoon donut** using
//  Signed Distance Functions (SDFs).
//
//  The visual result is composed of:
//  - A circular ring-shaped dough body (torus) with adjustable inner and
//    outer radii.
//  - A wavy icing layer overlaid on top of the dough, featuring adjustable
//    coverage, wave frequency, and amplitude.
//  - A procedural scattering of capsule-shaped sprinkles on the icing surface,
//    with randomized position, rotation, and color selection.
//
//  The rendering composites these layers with a consistent outline around
//  the entire silhouette. All elements are procedurally generated, allowing
//  infinite variations of sprinkles without texture maps[cite: 1017].
//
//  The output is an anti-aliased RGBA color suitable for food items,
//  collectible game assets, and dessert icons.
// ------------------------------------------------------------------------