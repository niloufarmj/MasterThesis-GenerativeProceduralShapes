// PLAN:
// 1) Define SDF helpers: sdBox, sdArc (symmetric), Rotate2D.
// 2) Center UVs and prepare dimensions (Stem, Serif, Hook).
// 3) Construct Stem SDF (Vertical Box) and Serif SDF (Horizontal Box).
// 4) Construct Hook SDF using a rotated Arc primitive (to handle asymmetry).
// 5) Combine primitives using min() (union) and subtract CornerRadius for rounding.
// 6) Compute outline distance and composite Fill vs Outline colors.

#ifndef PI
#define PI 3.14159265359
#endif

// Rotate a 2D vector by an angle (radians)
float2 Rotate2D(float2 p, float angle) {
    float c = cos(angle);
    float s = sin(angle);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

// SDF for an axis-aligned box
float sdBox(float2 p, float2 b) {
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// SDF for a circular arc (symmetric around Y axis)
// p: sample point (centered at arc center)
// sc: sin/cos of aperture (half-angle)
// ra: radius
// rb: thickness
float sdArc(float2 p, float2 sc, float ra, float rb) {
    p.x = abs(p.x);
    return ((sc.y * p.x > sc.x * p.y) ? length(p - sc * ra) : 
            abs(length(p) - ra)) - rb;
}

void LetterJShape_float(float2 UV, float Width, float Height, float Thickness, float HookRadius, float HookExtent, float SerifWidth, float CornerRadius, float4 FillColor, float4 OutlineColor, float OutlineWidth, out float4 outColor) {
    // 1. Center coordinates
    float2 p = UV - 0.5;
    
    // 2. Adjust Primitive Dimensions
    // To keep visual size consistent with rounding, we shrink primitives by CornerRadius
    float effThickness = max(0.001, Thickness - 2.0 * CornerRadius);
    float halfThick = effThickness * 0.5;
    float effHookRadius = max(halfThick + 0.001, HookRadius);
    
    // 3. Define Centers and Sizes
    // Align stem to the right side of the bounding width
    float stemX = (Width * 0.5) - (Thickness * 0.5);
    // Align stem vertical range
    float stemTopY = Height * 0.5;
    float stemBotY = -Height * 0.5 + HookRadius + (Thickness * 0.5);
    
    // 4. Stem SDF
    float stemH = (stemTopY - stemBotY);
    float2 stemCenter = float2(stemX, stemBotY + stemH * 0.5);
    float2 stemSize = float2(halfThick, stemH * 0.5);
    // Extend stem slightly down to blend with hook
    float dStem = sdBox(p - stemCenter, stemSize + float2(0.0, halfThick)); 

    // 5. Serif SDF (Top Bar)
    float dSerif = 100.0;
    if (SerifWidth > 0.0) {
        float2 serifCenter = float2(stemX, stemTopY - (Thickness * 0.5));
        // Extend serif width but subtract thickness to avoid double counting center
        float2 serifSize = float2(SerifWidth * 0.5, halfThick);
        dSerif = sdBox(p - serifCenter, serifSize);
    }

    // 6. Hook SDF (Bottom Arc)
    // The hook connects to the stem at angle 0 and curves downwards/left.
    // Total angle logic: 
    // Extent 0.0 -> Quarter circle (0 to -PI/2)
    // Extent 1.0 -> Semicircle (0 to -PI)
    float maxAngle = PI * (0.5 + 0.5 * clamp(HookExtent, 0.0, 1.0));
    float aperture = maxAngle * 0.5;
    float2 hookCenterPos = float2(stemX - effHookRadius, stemBotY);
    
    // Rotate p to align the arc's center-of-symmetry to the +Y axis (standard for sdArc)
    // The arc spans from 0 to -maxAngle. Midpoint is -maxAngle/2.
    // We want -maxAngle/2 to map to +PI/2 (up) or similar axis for sdArc.
    // IQ's sdArc is symmetric around Y+. 
    // Our arc midpoint is at angle -aperture.
    // We need to rotate coordinates by: +90deg - (-aperture) = PI/2 + aperture.
    // Note: We use -p relative to center because J hook is at bottom.
    float2 q = p - hookCenterPos;
    float rotAngle = (PI * 0.5) + aperture;
    float2 qRot = Rotate2D(q, rotAngle);
    
    float2 sc = float2(sin(aperture), cos(aperture));
    float dHook = sdArc(qRot, sc, effHookRadius, halfThick);

    // 7. Combine Shape
    float dShape = min(dStem, dHook);
    dShape = min(dShape, dSerif);
    
    // 8. Apply Rounding
    // Subtracting radius expands the shape, so our primitives were shrunk earlier
    // Actually, simple subtraction gives the rounded look on convex corners
    dShape -= CornerRadius;

    // 9. Compute Fill and Outline
    float aa = fwidth(dShape);
    // Fill Mask
    float fillMask = 1.0 - smoothstep(-aa, aa, dShape);
    
    // Outline Mask (Border around the shape)
    // The outline is defined as a band of width 'OutlineWidth' centered on the edge (d=0)
    // Distance to outline: abs(dShape) - OutlineWidth/2
    // But user asked for "Consistent Outline" usually meaning external or centered.
    // Let's do a standard external/centered stroke.
    float outlineDist = abs(dShape) - OutlineWidth * 0.5;
    float outlineMask = 1.0 - smoothstep(-aa, aa, outlineDist);
    
    // 10. Composite Colors
    // Draw Outline, then Fill on top?
    // Usually Fill is inside. Outline is the border.
    // Composite: Result = Outline * OutlineAlpha + Fill * FillAlpha * (1-OutlineAlpha)?
    // Simple Over operator: Fill over Outline.
    float4 finalColor = lerp(float4(0,0,0,0), OutlineColor, outlineMask);
    finalColor = lerp(finalColor, FillColor, fillMask);
    
    outColor = finalColor;
}