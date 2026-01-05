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

#ifndef PI
#define PI 3.14159265359
#endif

#ifndef TAU
#define TAU 6.28318530718
#endif

// --- Helper Functions ---

float donut_hash12(float2 p) {
    float3 p3  = frac(float3(p.xyx) * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return frac((p3.x + p3.y) * p3.z);
}

float2 donut_hash22(float2 p) {
    float3 p3 = frac(float3(p.xyx) * float3(.1031, .1030, .0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return frac((p3.xx+p3.yz)*p3.zy);
}

float donut_sdSegment(float2 p, float2 a, float2 b) {
    float2 pa = p - a, ba = b - a;
    float h = saturate(dot(pa, ba) / dot(ba, ba));
    return length(pa - ba * h);
}

// --- SDF Logic (Extracted for RAG Reusability) ---

// Calculates the base Dough Ring
float sdDonutBody(float2 p, float outerR, float innerR) {
    float len = length(p);
    float dOuter = len - outerR;
    float dInner = innerR - len; // Negative inside hole
    return max(dOuter, dInner);
}

// Calculates the Wavy Icing layer
float sdDonutIcing(float2 p, float outerR, float innerR, float waviness, float freq) {
    float len = length(p);
    float angle = atan2(p.y, p.x);
    
    // Icing covers ~80% of the donut width by default
    float icingBaseRadius = lerp(innerR, outerR, 0.8);
    float icingWave = sin(angle * freq) * waviness;
    
    float dIcingEdge = len - (icingBaseRadius + icingWave);
    float dHole = innerR - len;
    
    return max(dIcingEdge, dHole);
}

// Calculates the distance to the closest Sprinkle
// Returns float2(distance, color_variant_0_or_1)
float2 sdSprinklePattern(float2 p, float count, float2 params, float innerR, float outerR) {
    float dMin = 1000.0;
    float colorVariant = 0.0;
    
    int loopCount = clamp(int(count), 0, 32);
    
    for(int i = 0; i < 32; i++) {
        if (i >= loopCount) break;
        
        // Random seed
        float2 seed = float2(float(i) * 12.34, float(i) * 45.67);
        float2 rndPos = donut_hash22(seed);
        
        // Polar Position
        float a = rndPos.x * TAU;
        float r = lerp(innerR + 0.05, outerR - 0.05, rndPos.y);
        float2 pos = float2(cos(a), sin(a)) * r;
        
        // Orientation
        float orient = donut_hash12(seed + 1.0) * TAU;
        float2 dir = float2(cos(orient), sin(orient));
        
        // Geometry
        float halfLen = max(params.y, 0.01) * 0.5;
        float thickness = max(params.x, 0.001);
        float2 sa = pos - dir * halfLen;
        float2 sb = pos + dir * halfLen;
        
        float dSingle = donut_sdSegment(p, sa, sb) - thickness;
        
        if (dSingle < dMin) {
            dMin = dSingle;
            // Determine color variant based on hash
            colorVariant = step(0.5, donut_hash12(seed + 2.0));
        }
    }
    return float2(dMin, colorVariant);
}

// --- Main Function ---
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
    // 1. Coordinate Setup
    float safeSize = max(Size, 0.001);
    float2 p = (UV - 0.5) / safeSize;

    // 2. Compute SDFs (Using Helpers)
    float dBody = sdDonutBody(p, OuterRadius, InnerRadius);
    float dIcing = sdDonutIcing(p, OuterRadius, InnerRadius, IcingWaviness, IcingFrequency);
    
    // Sprinkles (Distance and Color ID)
    float2 sprinkleInfo = sdSprinklePattern(p, SprinkleCount, SprinkleParams, InnerRadius, OuterRadius);
    float dSprinkles = sprinkleInfo.x;
    float colID = sprinkleInfo.y;
    float3 activeSprinkleColor = (colID > 0.5) ? SprinkleColor2.rgb : SprinkleColor1.rgb;

    // 3. Rendering
    float aa = max(fwidth(dBody), 0.001);

    // Masks
    float alphaBody = 1.0 - smoothstep(0.0, aa, dBody);
    
    // Icing Mask (Clipped to Body)
    float alphaIcing = 1.0 - smoothstep(0.0, aa, dIcing);
    alphaIcing *= alphaBody; 
    
    // Sprinkle Mask (Clipped to Body)
    float alphaSprinkle = 1.0 - smoothstep(0.0, aa, dSprinkles);
    alphaSprinkle *= alphaBody;

    // Outline Mask
    float halfStroke = max(OutlineThickness, 0.0) * 0.5;
    float dTotal = dBody - halfStroke;
    float alphaTotal = 1.0 - smoothstep(0.0, aa, dTotal);
    
    float dOutline = abs(dBody) - halfStroke;
    float alphaOutline = 1.0 - smoothstep(0.0, aa, dOutline);

    // 4. Compositing
    // Fill Color (Mix Dough -> Icing -> Sprinkles)
    float3 fillRGB = DoughColor.rgb;
    fillRGB = lerp(fillRGB, IcingColor.rgb, alphaIcing / max(alphaBody, 0.001));
    fillRGB = lerp(fillRGB, activeSprinkleColor, alphaSprinkle / max(alphaBody, 0.001));
    
    // Apply Outline
    float3 finalRGB = lerp(fillRGB, OutlineColor.rgb, alphaOutline);
    
    // Output
    outColor = float4(finalRGB * alphaTotal, alphaTotal);
}