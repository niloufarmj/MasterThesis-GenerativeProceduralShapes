/*
  Candy Cane Shape with SDF
  - J-shaped tubular body (Vertical stem + Top 180-degree hook)
  - Rounded ends (capsule-like)
  - Adjustable size, stem height, hook radius, tube thickness
  - Diagonal alternating stripes with adjustable angle/width
  - Consistent outline
*/

#ifndef PI
#define PI 3.14159265359
#endif

// --- Helpers ---

// Distance to a line segment from a to b
float sdSegment(float2 p, float2 a, float2 b) {
    float2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}

// Distance to the upper semicircle of radius r centered at origin
// Defined for y >= 0 as circle distance, y < 0 as distance to endpoints
float sdUpperSemicircle(float2 p, float r) {
    // If we are in the upper half, it's a standard circle distance
    if (p.y >= 0.0) return abs(length(p) - r);
    // If in the lower half, the closest point on the arc is the endpoint (r, 0)
    // We use abs(p.x) to handle both left (-r,0) and right (r,0) endpoints symmetrically
    return distance(float2(abs(p.x), p.y), float2(r, 0.0));
}

// --- Main Function ---
void CandyCaneShape_float(
    float2 UV,
    float Size,
    float StemHeight,
    float HookRadius,
    float TubeThickness,
    float StripeWidth,
    float StripeAngle,
    float4 Color1,
    float4 Color2,
    float OutlineWidth,
    float4 OutlineColor,
    out float4 outColor
) {
    // PLAN:
    // 1) Center and scale UVs. Align shape so mass is centered.
    // 2) Define Skeleton: Vertical Segment + Upper Semicircle.
    // 3) Calculate Signed Distance (SDF) to skeleton.
    // 4) Subtract TubeRadius to get Body SDF (rounded ends come for free).
    // 5) Generate Stripe Pattern using rotated coordinates.
    // 6) Calculate Fill Mask and Outline Mask.
    // 7) Composite colors (Outline -> Fill).

    // 1) Coordinates
    float2 p = (UV - 0.5) * 2.0; // Remap to -1..1
    // Apply overall scale
    float scale = max(Size, 0.001);
    p /= scale;

    // Center the shape vertically
    // Shape spans from +HookRadius (top) to -StemHeight (bottom)
    // Midpoint is (HookRadius - StemHeight) / 2.0
    float verticalShift = (HookRadius - StemHeight) * 0.5;
    p.y -= verticalShift;

    // 2) Skeleton SDF Construction
    // We model the cane with the Hook centered at (0,0) locally for the arc,
    // and the Stem connected to the right side at (HookRadius, 0).
    
    // Stem: Vertical line from (HookRadius, 0) down to (HookRadius, -StemHeight)
    float dStem = sdSegment(p, float2(HookRadius, 0.0), float2(HookRadius, -StemHeight));
    
    // Hook: Upper semicircle centered at (0,0) with radius HookRadius
    float dHook = sdUpperSemicircle(p, HookRadius);
    
    // Combine: The skeleton is the union of the stem and the hook
    float dSkeleton = min(dStem, dHook);

    // 3) Body SDF
    // Subtract half-thickness to create the tubular surface
    float tubeRadius = TubeThickness * 0.5;
    float dBody = dSkeleton - tubeRadius;

    // 4) Stripe Pattern
    // Rotate position for diagonal stripes
    float s = sin(StripeAngle);
    float c = cos(StripeAngle);
    float2 rotatedP = float2(p.x * c - p.y * s, p.x * s + p.y * c);
    
    // Generate stripes using sine wave
    float width = max(StripeWidth, 0.001);
    float freq = PI / width;
    float stripePattern = sin(rotatedP.y * freq);
    // Smooth transition for stripes (optional, using hard step for classic vector look)
    // float stripeFactor = step(0.0, stripePattern);
    // Using smoothstep for better quality at arbitrary angles
    float stripeFactor = smoothstep(-0.01, 0.01, stripePattern);
    
    float4 fillColor = lerp(Color1, Color2, stripeFactor);

    // 5) Masks & Anti-aliasing
    // Compute AA width based on derivatives for crisp edges at any scale
    float aa = fwidth(dBody);
    
    // Outline Mask (Outer shell)
    // The outline sits outside the body. Effectively Body expanded by OutlineWidth.
    float dOutline = dBody - max(OutlineWidth, 0.0);
    float maskOutline = 1.0 - smoothstep(0.0, aa, dOutline);
    
    // Fill Mask (Inner body)
    float maskFill = 1.0 - smoothstep(0.0, aa, dBody);

    // 6) Composite
    // Draw Outline first, then Fill on top
    // Since we are in a single pass, we mix colors based on masks
    
    // Base is OutlineColor masked by maskOutline
    // Overlaid is fillColor masked by maskFill
    float4 finalColor = lerp(float4(OutlineColor.rgb, 1.0), fillColor, maskFill);
    
    // Final Alpha is determined by the largest mask (Outline)
    // We multiply the color alpha by the coverage mask
    float finalAlpha = maskOutline * OutlineColor.a; // Simplified alpha logic assuming outline defines shape
    
    // For correct transparency blending: 
    // If fill is transparent, we see outline behind? Usually outline is just a border.
    // Standard "Stroke" logic: Color = maskFill * Fill + (maskOutline - maskFill) * Stroke
    float3 rgb = lerp(OutlineColor.rgb, fillColor.rgb, maskFill);
    
    // Output
    outColor = float4(rgb * finalAlpha, finalAlpha);
}