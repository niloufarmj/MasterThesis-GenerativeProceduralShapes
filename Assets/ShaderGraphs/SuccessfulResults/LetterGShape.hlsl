#ifndef PI
#define PI 3.14159265359
#endif

// --- Helpers ---

// Signed Distance to an Arc (Symmetric around Y axis)
// p: sampling point
// sc: sin/cos of the aperture half-angle
// ra: radius
// rb: thickness
// Note: This draws the arc segment. The aperture is the 'missing' part.
float sdArcG(float2 p, float2 sc, float ra, float rb) {
    p.x = abs(p.x);
    return ((sc.y*p.x > sc.x*p.y) ? length(p - sc*ra) : 
            abs(length(p) - ra)) - rb;
}

// Signed Distance to a Line Segment
float sdSegmentG(float2 p, float2 a, float2 b) {
    float2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}

// Polynomial Smooth Min (for blending shapes)
float sminG(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / max(k, 1e-5), 0.0, 1.0);
    return lerp(b, a, h) - k * h * (1.0 - h);
}

// Alpha Blending (Src Over Dst)
float4 overG(float4 src, float4 dst) {
    float a = src.a + dst.a * (1.0 - src.a);
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-8);
    return float4(c, a);
}

// --- Main Function ---
// Letter G Shape: A circular arc (C-shape) with an inward horizontal spur.
void LetterGShape_float(float2 UV, float Width, float Height, float Thickness, float GapSize, float SpurLength, float CornerRounding, float4 FillColor, float4 OutlineColor, float OutlineWidth, out float4 outColor) {
    // PLAN:
    // 1) Center UVs and apply scale (Width/Height) to map to -1..1 space.
    // 2) Create the "C" arc by rotating standard sdArc. Map the 'solid' part to Y+ and 'gap' to Y-.
    // 3) Create the horizontal spur attached to the bottom lip of the aperture.
    // 4) Combine Arc and Spur using smin for smooth joints.
    // 5) Generate Fill and Outline masks using smoothstep.
    // 6) Composite colors.

    // 1. Coordinate Setup
    float2 center = float2(0.5, 0.5);
    float2 p = UV - center;
    // Scale p so that a value of 1.0 matches the Width/Height
    // We use a safe divider to prevent division by zero
    p /= max(float2(Width, Height), 0.001);
    
    // 2. Arc Component
    // We want a C shape with opening on the Right (+X).
    // IQ's sdArc is symmetric around Y+ (Top). 
    // We map our desired "Solid Back" (Left/-X) to Y+ (Top) by rotating -90 degrees.
    // Rotate -90: x' = y, y' = -x.
    float2 pArc = float2(p.y, -p.x);
    
    // The aperture of the C is 'GapSize'. The solid arc is PI - (GapSize/2).
    float halfGap = GapSize * 0.5;
    float arcHalfAngle = PI - halfGap;
    float2 scArc = float2(sin(arcHalfAngle), cos(arcHalfAngle));
    
    // Base radius is 0.5 (half of the 1.0 scaling box)
    float radius = 0.5;
    
    // Compute Arc SDF
    float dArc = sdArcG(pArc, scArc, radius, Thickness);
    
    // 3. Spur Component
    // The spur attaches to the bottom lip of the aperture.
    // In original unrotated space, the gap is centered at 0.
    // The bottom lip is at angle -halfGap.
    float spurAngle = -halfGap;
    
    // Calculate start point on the ring
    float2 spurStart = float2(cos(spurAngle), sin(spurAngle)) * radius;
    
    // The spur goes inward horizontally (to the Left, -X direction)
    float2 spurEnd = spurStart - float2(SpurLength, 0.0);
    
    // Compute Spur SDF (Segment)
    // Subtract Thickness so it matches the arc's weight
    float dSpur = sdSegmentG(p, spurStart, spurEnd) - Thickness;
    
    // 4. Combination
    // Smooth union to blend the spur into the arc
    float dShape = sminG(dArc, dSpur, max(CornerRounding, 0.001));
    
    // 5. Rendering
    float aa = fwidth(dShape);
    
    // Fill Mask (dShape < 0)
    float fillAlpha = 1.0 - smoothstep(0.0, aa, dShape);
    float4 fill = float4(FillColor.rgb, FillColor.a * fillAlpha);
    
    // Outline Mask (abs(dShape) < OutlineWidth/2)
    // Outline sits on the boundary of the shape
    float halfOutline = OutlineWidth * 0.5;
    float dOutline = abs(dShape) - halfOutline;
    float outlineAlpha = 1.0 - smoothstep(0.0, aa, dOutline);
    float4 stroke = float4(OutlineColor.rgb, OutlineColor.a * outlineAlpha);
    
    // 6. Composite (Stroke over Fill)
    outColor = overG(stroke, fill);
}