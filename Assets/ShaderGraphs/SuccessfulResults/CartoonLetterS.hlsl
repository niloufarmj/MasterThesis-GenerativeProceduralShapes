#ifndef PI
#define PI 3.14159265359
#endif

// Rotate 2D vector by angle in radians
float2 Rotate2D(float2 p, float angle) {
    float c = cos(angle);
    float s = sin(angle);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

// Signed Distance to an Arc (symmetric around Y axis)
// p: point, sc: sin/cos of aperture, ra: radius, rb: thickness
float sdArc(float2 p, float2 sc, float ra, float rb) {
    p.x = abs(p.x);
    return ((sc.y * p.x > sc.x * p.y) ? length(p - sc * ra) : 
                                      abs(length(p) - ra)) - rb;
}

// General Arc Segment from startAngle to endAngle
float sdGeneralArc(float2 p, float2 center, float radius, float startAngle, float endAngle, float thickness) {
    float2 localP = p - center;
    // Calculate aperture properties
    float midAngle = (startAngle + endAngle) * 0.5;
    float halfAngle = abs(endAngle - startAngle) * 0.5;
    // Rotate localP so the arc center aligns with +Y axis (PI/2)
    float rot = (PI * 0.5) - midAngle;
    localP = Rotate2D(localP, rot);
    float2 sc = float2(sin(halfAngle), cos(halfAngle));
    return sdArc(localP, sc, radius, thickness);
}

void CartoonLetterS_float(float2 UV, float Size, float4 Color, float2 Center, float Thickness, float Curvature, float TipAngle, float4 OutlineColor, float OutlineWidth, out float4 outColor) {
    // PLAN:
    // 1. Center and Scale UVs.
    // 2. Define 'S' as two connected arcs (top and bottom) with point symmetry.
    // 3. Top Arc: Centered at (-Curvature, Curvature) with computed radius to pass through origin.
    // 4. Bottom Arc: Same logic, evaluated at -p (180 deg rotation).
    // 5. Compute min distance of both arcs.
    // 6. Apply outline and fill logic with smoothstep.

    // 1. Coordinates
    float2 p = UV - Center;
    p /= max(Size, 0.0001);
    
    // 2. Parameters
    // 'Curvature' (k) controls the offset of the loops. radius is derived to join at origin.
    float k = max(Curvature, 0.001);
    float radius = k * 1.41421356; // k * sqrt(2)
    float halfThick = Thickness * 0.5;
    
    // 3. Angles
    // Start angle -45 deg aligns the arc tangent with the diagonal at origin for smooth 'S' join
    float startRad = -PI * 0.25;
    float endRad = radians(TipAngle);
    
    // 4. SDF Calculation
    // Top Loop (starts at origin, curls left/up)
    float2 centerTop = float2(-k, k);
    float dTop = sdGeneralArc(p, centerTop, radius, startRad, endRad, halfThick);
    
    // Bottom Loop (Symmetric to top loop rotated 180 degrees)
    float dBot = sdGeneralArc(-p, centerTop, radius, startRad, endRad, halfThick);
    
    // Combine
    float dist = min(dTop, dBot);
    
    // 5. Rendering
    // Analytic AA
    float aa = fwidth(dist);
    if (aa < 0.001) aa = 0.005; // Fallback for previews
    
    // Masks
    // Dist <= 0 is Fill. Dist <= OutlineWidth is Outline.
    float fillMask = 1.0 - smoothstep(-aa, aa, dist);
    float outlineMask = 1.0 - smoothstep(OutlineWidth - aa, OutlineWidth + aa, dist);
    
    // 6. Composite (Fill over Outline)
    float4 finalRGB = lerp(OutlineColor, Color, fillMask);
    
    // Output Premultiplied Alpha
    // Alpha is determined by the outline mask (broadest shape)
    float finalAlpha = outlineMask;
    outColor = float4(finalRGB.rgb * finalAlpha, finalRGB.a * finalAlpha);
}