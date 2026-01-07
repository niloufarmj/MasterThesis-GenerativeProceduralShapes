/* 
  Cartoon Number 3 SDF Generator
  - Constructs a smooth '3' using two rotated arc SDFs connected by a smooth minimum.
  - Supports adjustable dimensions, thickness, outline, and joint smoothness.
  - Uses analytic AA for clean edges.
*/

#ifndef PI
#define PI 3.14159265359
#endif

// --- Helpers ---

// Rotate a 2D vector by an angle (radians)
float2 Rotate2D(float2 p, float angle) {
    float s = sin(angle);
    float c = cos(angle);
    return float2(p.x * c - p.y * s, p.x * s + p.y * c);
}

// Signed Distance to an Arc (opening UP, symmetric around Y)
// p: sample point (centered at arc origin)
// sc: float2(sin(aperture/2), cos(aperture/2))
// ra: radius
// Returns distance to the arc spine (0 thickness)
float sdArc(float2 p, float2 sc, float ra) {
    // p is local coordinates
    p.x = abs(p.x);
    // Check if point is inside the arc sector defined by aperture
    return ((sc.y * p.x > sc.x * p.y) ? length(p - sc * ra) : abs(length(p) - ra));
}

// Smooth Minimum (polynomial) for organic blending at the junction
float smin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / max(k, 1e-5), 0.0, 1.0);
    return lerp(b, a, h) - k * h * (1.0 - h);
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
    // 1. Center and scale UV coordinates to normalized space.
    // 2. Define two arcs: Top (opening roughly SW) and Bottom (opening roughly NW).
    // 3. Position arcs vertically to meet at the center.
    // 4. Compute SDF for each arc spine.
    // 5. Blend spines using smin to form a continuous '3' curve.
    // 6. Subtract thickness to create solid shape.
    // 7. Render with smoothstep AA and outline.

    // 1. Coordinates
    float2 center = float2(0.5, 0.5);
    float2 p = UV - center;
    
    // Scale correction to maintain aspect ratio logic
    // We normalize so that 0.5 is the reference unit
    float2 scale = 1.0 / max(float2(Width, Height), 0.0001);
    p *= scale;
    
    // Metric scalar for correct AA width
    float aaScale = min(Width, Height);

    // 2. Arc Configuration
    // Radius of the loops (relative to scaled space)
    float radius = 0.25;
    // Vertical shift for centers
    float yShift = 0.25;

    // Aperture: We want "Major Arcs" (~270 degrees) to form the loops.
    // Half-aperture = 135 degrees = 2.356 radians
    // sc stores sin/cos of (135 deg)
    float halfAp = 135.0 * (PI / 180.0);
    float2 sc = float2(sin(halfAp), cos(halfAp));

    // 3. Compute Top Arc SDF
    // Center: (0, 0.25)
    float2 pTop = p - float2(0.0, yShift);
    // Rotation: We want the gap to be at ~225 deg (South-West).
    // Standard sdArc opens UP (90 deg). We rotate point by -(225 - 90) = -135 deg.
    // Or simply trial: Rot 135 deg puts gap at bottom-left.
    float2 pTopRot = Rotate2D(pTop, 135.0 * (PI / 180.0));
    float dTop = sdArc(pTopRot, sc, radius);

    // 4. Compute Bottom Arc SDF
    // Center: (0, -0.25)
    float2 pBot = p - float2(0.0, -yShift);
    // Rotation: We want the gap to be at ~135 deg (North-West).
    // Rot 45 deg puts gap at top-left.
    float2 pBotRot = Rotate2D(pBot, 45.0 * (PI / 180.0));
    float dBot = sdArc(pBotRot, sc, radius);

    // 5. Combine
    // smin blends the meeting point at (0,0) into a smooth waist
    float dSpine = smin(dTop, dBot, max(Smoothness, 0.01));

    // 6. Solidify
    // Subtract thickness (half-width) from the spine distance
    float dShape = dSpine - Thickness;

    // Restore metric distance for AA
    dShape *= aaScale;

    // 7. Coloring & Outline
    float aa = fwidth(dShape);
    float alpha = 1.0 - smoothstep(-aa, aa, dShape);
    
    // Outline logic: Outline is an expansion of the shape
    // Distance to outer edge of outline
    float dOutline = dShape - OutlineWidth;
    float outlineAlpha = 1.0 - smoothstep(-aa, aa, dOutline);
    
    // Composite: 
    // Base shape (Color) is on top of Outline (OutlineColor)
    // Use standard alpha blending or mask mixing
    float4 solidLayer = float4(Color.rgb, 1.0);
    float4 outlineLayer = float4(OutlineColor.rgb, 1.0);
    
    // If shape is transparent, we need careful handling
    // Final = lerp(Outline, Fill, fillMask) * outlineMask
    float4 finalColor = lerp(outlineLayer, solidLayer, alpha);
    finalColor.a = max(alpha * Color.a, outlineAlpha * OutlineColor.a); // Simple alpha merge
    
    // Better composite for variable opacity:
    // We draw the full outline shape, then blend the fill on top
    // But to avoid color bleeding, typically we just mix RGB
    float fillMask = clamp(alpha, 0.0, 1.0);
    float outlineMask = clamp(outlineAlpha, 0.0, 1.0);
    
    float3 outRGB = lerp(OutlineColor.rgb, Color.rgb, fillMask);
    float outA = outlineMask; // Basic coverage

    // Apply vertex color alphas
    float combinedAlpha = outlineMask * max(OutlineColor.a, fillMask * Color.a);

    outColor = float4(outRGB * combinedAlpha, combinedAlpha);
}