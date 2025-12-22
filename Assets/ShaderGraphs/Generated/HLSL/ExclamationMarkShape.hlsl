#ifndef PI
#define PI 3.14159265359
#endif

// Helper: Signed Distance to a Box
// p: Point
// b: Half-extents (width/2, height/2)
float em_sdBox(float2 p, float2 b) {
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

void ExclamationMarkShape_float(float2 UV, float2 Center, float Size, float Thickness, float Rotation, float4 Color, out float4 outColor) {
    // PLAN:
    // 1) Center UV coordinates and apply rotation.
    // 2) Define vertical layout parameters (dot radius, gap, bar height) based on Size and Thickness.
    // 3) Calculate SDF for the bottom Dot (circle).
    // 4) Calculate SDF for the top Bar (rounded box/capsule).
    // 5) Combine using min() for union.
    // 6) Apply smoothstep for AA and output color.

    // 1) Center and Rotate
    float2 p = UV - Center;
    float c = cos(Rotation);
    float s = sin(Rotation);
    p = float2(p.x * c - p.y * s, p.x * s + p.y * c);

    // 2) Layout Parameters
    // r is the radius of the stroke/capsules
    float r = Thickness * 0.5;
    // Ensure size encompasses the content comfortably
    float safeSize = max(Size, Thickness * 3.0);
    
    // Define gap size (gap between dot and line)
    float gap = Thickness;

    // Vertical positions (Relative to the rotated center)
    // The total visual height is 'safeSize'. We center this vertical extent on the pivot.
    float halfH = safeSize * 0.5;
    float bottomY = -halfH;
    float topY = halfH;

    // Dot Geometry
    // Dot sits at the bottom.
    float dotCenterY = bottomY + r;
    float2 dotPos = float2(0.0, dotCenterY);

    // Bar Geometry
    // Bar starts above the dot + gap
    float barBottomY = dotCenterY + r + gap;
    float barTopY = topY;
    float barHeight = barTopY - barBottomY;
    
    // We model the bar as a vertical rounded box (capsule).
    // The visual segment goes from barBottomY to barTopY.
    // The center of this segment:
    float barCenterY = barBottomY + barHeight * 0.5;
    // The half-height of the rectangular part of the box:
    // Total height = 2 * (boxHalfH + r). So boxHalfH = height/2 - r.
    float boxHalfH = max(0.0, barHeight * 0.5 - r);
    
    // 3) Dot SDF
    float distDot = length(p - dotPos) - r;

    // 4) Bar SDF
    // We use a box of width 0 and calculated height, then subtract radius r (making it a capsule)
    float distBar = em_sdBox(p - float2(0.0, barCenterY), float2(0.0, boxHalfH)) - r;

    // 5) Combine Shapes (Union)
    float dist = min(distDot, distBar);

    // 6) Anti-aliasing and Output
    float edge = smoothstep(0.005, -0.005, dist);
    
    // Apply mask to color (Premultiplied alpha-like behavior for clean blending)
    outColor = float4(Color.rgb * edge, edge);
}