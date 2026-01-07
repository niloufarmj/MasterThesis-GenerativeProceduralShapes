/* 
  Cartoon Number 3 Shape
  - Constructs a '3' using two arc SDFs connected with a smooth union.
  - Supports adjustable width, height, thickness, smoothness, and outline.
*/

#ifndef PI
#define PI 3.14159265359
#endif

// --- Helpers ---

// Rotation matrix helper
float2 Rotate2D(float2 p, float angle) {
    float s = sin(angle);
    float c = cos(angle);
    return float2(p.x * c - p.y * s, p.x * s + p.y * c);
}

// Smooth Minimum (polynomial) for organic blending
float smin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / max(k, 1e-5), 0.0, 1.0);
    return lerp(b, a, h) - k * h * (1.0 - h);
}

// Signed Distance to an Arc (symmetric around Y axis)
// p: sample point
// sc: float2(sin(aperture/2), cos(aperture/2))
// ra: radius
// Returns distance to the arc spine (0 thickness)
float sdArcSpine(float2 p, float2 sc, float ra) {
    p.x = abs(p.x);
    // Determine if we are in the arc sector or the empty sector
    return ((sc.y * p.x > sc.x * p.y) ? length(p - sc * ra) : abs(length(p) - ra));
}

// --- Main Function ---
void CartoonNumber3_float(
    float2 UV,
    float Width,
    float Height,
    float Thickness,
    float OutlineWidth,
    float Smoothness,
    float4 Color,
    float4 OutlineColor,
    out float4 outColor)
{
    // PLAN:
    // 1) Center and scale UV coordinates based on Width/Height.
    // 2) Define two arc segments for the top and bottom of the '3'.
    // 3) Rotate arcs so they open to the left.
    // 4) Combine arcs using smooth minimum (smin) to create a connected spine.
    // 5) Subtract thickness to create the solid shape.
    // 6) Compute outline and fill masks using smoothstep AA.
    // 7) Composite colors.

    // 1. Center and Scale
    float2 center = float2(0.5, 0.5);
    float2 p = UV - center;
    
    // Apply dimension scaling (inverted so larger Width param = larger visual)
    // Avoid divide by zero
    float2 scale = 1.0 / max(float2(Width, Height), 0.001);
    p *= scale;

    // Correct distance field distortion from non-uniform scaling
    // We multiply the final distance by the smallest scale factor to approximate metric distance
    float distScale = min(Width, Height);

    // 2. Setup Arcs
    // The '3' is formed by two arcs vertically stacked.
    // We place them so they meet near the center.
    // Radius is roughly 1/4 of total normalized height (since we scaled p, height is effectively 1.0 in local space)
    float radius = 0.25;
    
    // Vertical offsets for the two rings
    float2 topCenter = float2(0.0, 0.25);
    float2 botCenter = float2(0.0, -0.25);

    // Aperture: How much of the circle is drawn.
    // A typical '3' has arcs of about 260 degrees (leaving a 100 degree gap).
    // Half aperture = 130 degrees.
    float halfAperture = 130.0 * (PI / 180.0);
    float2 sc = float2(sin(halfAperture), cos(halfAperture));

    // 3. Compute SDFs
    // Top Arc: Rotate +90 deg to map Right(0) to Up(90) because sdArc is Y-symmetric
    // We want the opening on the Left, so the spine midpoint is on the Right.
    float2 pTop = p - topCenter;
    pTop = Rotate2D(pTop, PI * 0.5); 
    float dTop = sdArcSpine(pTop, sc, radius);

    // Bottom Arc: Same rotation
    float2 pBot = p - botCenter;
    pBot = Rotate2D(pBot, PI * 0.5);
    float dBot = sdArcSpine(pBot, sc, radius);

    // 4. Combine
    // Use smooth min to connect them organically at the center cusp
    float dSpine = smin(dTop, dBot, Smoothness);

    // 5. Solidify
    // Subtract thickness from the spine distance
    float dShape = dSpine - Thickness;

    // Restore metric scale for AA
    dShape *= distScale;

    // 6. Rendering / Coloring
    // Anti-aliasing width
    float aa = fwidth(dShape);
    
    // Fill Mask: dShape < 0 is inside
    float fillMask = smoothstep(aa, -aa, dShape);
    
    // Outline Mask: The border is drawn where dShape is between 0 and OutlineWidth
    // We want the outline to grow OUTWARD from the shape
    float outlineDist = dShape - OutlineWidth;
    float outlineMask = smoothstep(aa, -aa, outlineDist);
    
    // Composite: Outline is drawn 'behind' or 'around' the fill
    // Since we computed masks for "Shape+Outline" (outlineMask) and "InnerShape" (fillMask):
    // Color = mix(OutlineColor, FillColor, fillMask) * outlineMask
    
    float4 finalColor = lerp(OutlineColor, Color, fillMask);
    
    // Apply transparency based on the total coverage (outlineMask)
    finalColor.a *= outlineMask;
    
    outColor = finalColor;
}