#ifndef PI
#define PI 3.14159265359
#endif

// --- Helper Functions ---

// Signed Distance to a 2D Trapezoid
// p: point relative to center
// w1: bottom half-width (at -h)
// w2: top half-width (at +h)
// h: half-height
float candy_sdTrapezoid(float2 p, float w1, float w2, float h) {
    float2 k1 = float2(w2, h);
    float2 k2 = float2(w2 - w1, 2.0 * h);
    p.x = abs(p.x);
    float2 ca = float2(p.x - min(p.x, (p.y < 0.0) ? w1 : w2), abs(p.y) - h);
    float2 cb = p - k1 + k2 * clamp(dot(k1 - p, k2) / dot(k2, k2), 0.0, 1.0);
    float s = (cb.x < 0.0 && ca.y < 0.0) ? -1.0 : 1.0;
    return s * sqrt(min(dot(ca, ca), dot(cb, cb)));
}

// Helper to mix colors with alpha compositing (Source Over Destination)
float4 candy_composite(float4 src, float4 dst) {
    float outA = src.a + dst.a * (1.0 - src.a);
    float3 outRGB = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(outA, 1e-4);
    return float4(outRGB, outA);
}

// --- Main Function ---
// Draws a cartoon wrapped candy with circular body, stripes, and wavy fan wrappers.
// REQUEST: Circular body, vertical stripes, fan-shaped twists, clean outlines.
void CartoonCandyShape_float(
    float2 UV,
    float2 Center,
    float Rotation,
    float BodyRadius,
    float4 BodyColor,
    float StripeCount,
    float StripeThickness,
    float4 StripeColor,
    float WrapperLength,
    float WrapperSpread,
    float4 WrapperColor,
    float StrokeWidth,
    float4 StrokeColor,
    out float4 outColor)
{
    // PLAN:
    // 1) Center and rotate UV coordinates.
    // 2) Compute SDF for the circular Body.
    // 3) Compute SDF for the Wrappers (Trapezoids with wavy ends).
    // 4) Combine Body and Wrapper SDFs (Union).
    // 5) Generate Masks: Shape, Stroke, Body Fill, Stripe Pattern, Wrapper Details.
    // 6) Composite layers: Stroke > Stripes > Body > Wrapper Details > Wrapper Base.

    // 1. Transform Coordinates
    float2 p = UV - Center;
    float c = cos(Rotation);
    float s = sin(Rotation);
    p = float2(p.x * c - p.y * s, p.x * s + p.y * c);

    // 2. Body SDF (Circle)
    float dBody = length(p) - BodyRadius;

    // 3. Wrapper SDF
    // Use symmetry to draw both left and right wrappers at once
    float2 q = p;
    q.x = abs(q.x);
    // Shift local coordinate so wrapper starts at the body edge
    q.x -= BodyRadius * 0.95; // Slight overlap for better connection

    // Trapezoid Setup
    // We map the wrapper (horizontal) to the trapezoid function (vertical Y-up)
    // Wrapper X axis -> Trapezoid Y axis
    // Wrapper Y axis -> Trapezoid X axis
    float twistHalfWidth = BodyRadius * 0.3; // Narrow connection point
    float spreadHalfWidth = WrapperSpread;   // Wide fan end
    float wrapLen = WrapperLength;
    
    // Center the trapezoid shape in the Y-axis of the SDF function
    // The trapezoid function is centered at (0,0). Our wrapper extends from 0 to wrapLen.
    // So we shift q.x by -wrapLen/2
    float2 trapP = float2(q.y, q.x - wrapLen * 0.5);
    
    // Calculate basic trapezoid SDF
    // Extend height slightly to allow for the wavy cut to define the edge cleanly
    float dTrap = candy_sdTrapezoid(trapP, twistHalfWidth, spreadHalfWidth, wrapLen * 0.6);

    // Create Wavy/Zigzag Cut at the end
    // The end of the wrapper is at q.x = wrapLen
    // We create a boundary: x > wrapLen + wave
    float waveFreq = 20.0;
    float waveAmp = wrapLen * 0.1;
    float wave = waveAmp * sin(q.y * waveFreq / BodyRadius);
    float dCut = q.x - (wrapLen + wave);

    // Intersect trapezoid with the wavy cut plane
    float dWrapper = max(dTrap, dCut);

    // 4. Combine Shapes (Union)
    float dShape = min(dBody, dWrapper);

    // 5. Masks & Patterns
    float aa = fwidth(dShape); // Anti-aliasing width
    
    // Main Silhouette Mask
    float maskShape = 1.0 - smoothstep(0.0, aa, dShape);
    
    // Stroke/Outline Mask
    // Outline sits on the edge of dShape
    float halfStroke = StrokeWidth * 0.5;
    float maskStroke = smoothstep(halfStroke + aa, halfStroke, abs(dShape));
    
    // Body Mask (for layering)
    // We want the body to appear 'on top' of the wrapper
    float maskBodyFill = 1.0 - smoothstep(0.0, aa, dBody);

    // Wrapper Detail Pattern (Crinkle lines)
    // Using sine waves rotated slightly or horizontal along the wrapper
    float crinkle = sin(q.y * 40.0) * sin(q.x * 20.0);
    float maskCrinkle = smoothstep(0.5, 0.6, crinkle) * 0.3; // Subtle shading
    
    // Stripe Pattern (Vertical stripes on body)
    // Pattern based on world X (relative to center)
    // Use centered p.x for stripes
    float stripeSignal = sin(p.x * StripeCount + PI/2.0);
    // StripeThickness controls the width of the stripe band (0 to 1)
    float stripeThresh = 1.0 - clamp(StripeThickness, 0.0, 1.0);
    float maskStripes = smoothstep(stripeThresh, stripeThresh + 0.1, abs(stripeSignal));
    // Clip stripes to body only
    maskStripes *= maskBodyFill;

    // 6. Composition
    // Start with transparent background
    float4 color = float4(0.0, 0.0, 0.0, 0.0);

    // A. Draw Wrapper (Base)
    // Mask for wrapper part: It is the shape where body is NOT
    // But we can just draw wrapper everywhere inside maskShape, then cover with body
    float4 colWrap = WrapperColor;
    // Add crinkles to wrapper color
    colWrap.rgb = lerp(colWrap.rgb, colWrap.rgb * 0.8, maskCrinkle);
    // Apply shape mask to alpha
    colWrap.a *= maskShape;
    color = candy_composite(colWrap, color);

    // B. Draw Body (Over Wrapper)
    float4 colBody = float4(BodyColor.rgb, BodyColor.a * maskBodyFill);
    color = candy_composite(colBody, color);

    // C. Draw Stripes (Over Body)
    float4 colStripe = float4(StripeColor.rgb, StripeColor.a * maskStripes);
    color = candy_composite(colStripe, color);

    // D. Draw Stroke (Over All)
    // The stroke follows the combined silhouette
    float4 colStroke = float4(StrokeColor.rgb, StrokeColor.a * maskStroke * maskShape);
    // Note: maskShape fades out at the edge, maskStroke fades in/out at the edge.
    // To keep outline crisp, we can just use maskStroke directly if we want the line centered on the edge.
    // But usually we want the line contained or centered. Here centered is fine.
    // Re-calculate pure stroke layer without shape clipping to avoid double-fading artifact:
    float maskStrokePure = smoothstep(halfStroke + aa, halfStroke, abs(dShape));
    colStroke = float4(StrokeColor.rgb, StrokeColor.a * maskStrokePure);
    
    color = candy_composite(colStroke, color);

    outColor = color;
}

// ------------------------------------------------------------------------
//  Visual Result (High-level, parameter-invariant description)
// ------------------------------------------------------------------------
//  This function generates a **stylized 2D wrapped candy** using
//  Signed Distance Functions (SDFs).
//
//  The visual result is composed of:
//  - A central circular body representing the hard candy.
//  - Two symmetric fan-shaped wrapper twists extending from the sides.
//  - The wrappers feature jagged (zigzag) cut edges and subtle crinkle details.
//
//  The styling includes a procedural stripe pattern on the central body
//  and a consistent outline around the entire silhouette. All elements
//  (stripe density, wrapper spread, colors, rotation) are fully adjustable.
//
//  The output is an anti-aliased RGBA color suitable for holiday themes,
//  reward icons, and game items.
// ------------------------------------------------------------------------