#ifndef PI
#define PI 3.14159265359
#endif

// Helper: Signed Distance to a Box
// p: point relative to box center
// b: half-extents (width/2, height/2)
float sdBox_F(float2 p, float2 b) {
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// Helper: Composite Source Over Destination (for transparency)
float4 compositeOver_F(float4 src, float4 dst) {
    float a = src.a + dst.a * (1.0 - src.a);
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-6);
    return float4(c, a);
}

// Helper: 2D Rotation
float2 rotate_F(float2 p, float angle) {
    float c = cos(angle);
    float s = sin(angle);
    return float2(c * p.x + s * p.y, -s * p.x + c * p.y);
}

void LetterFShape_float(
    float2 UV,
    float Width,
    float Height,
    float Thickness,
    float ArmLengthTop,
    float ArmLengthMiddle,
    float MiddleArmY,
    float CornerRadius,
    float2 Center,
    float Rotation,
    float4 FillColor,
    float4 StrokeColor,
    float StrokeThickness,
    out float4 outColor
) {
    // PLAN:
    // 1) Center UV and apply Rotation to the coordinate space.
    // 2) Define 3 overlapping boxes for the F shape: Spine, Top Arm, Middle Arm.
    // 3) Calculate SDFs for each box, applying CornerRadius logic (box - r).
    // 4) Union the shapes using min().
    // 5) Compute anti-aliased masks for Fill and Stroke.
    // 6) Composite Stroke over Fill.

    // 1. Coordinates
    float2 p = UV - Center;
    p = rotate_F(p, -Rotation);

    // 2. Safe Dimensions & Radius
    float w = max(Width, 0.001);
    float h = max(Height, 0.001);
    float t = clamp(Thickness, 0.001, min(w, h));
    
    // Limit radius so it doesn't invert the shape (max radius is half-thickness)
    float r = clamp(CornerRadius, 0.0, t * 0.5);

    // 3. Define Shapes
    // Note: We use max(size - r, 0.0) to shrink the box for rounding, then subtract r from distance.
    // Positions are relative to the center of the total bounds (0,0)
    
    // -- Spine (Left Vertical) --
    // Aligned to the left edge: x = -w/2 + t/2
    float2 spineSize = float2(t * 0.5, h * 0.5);
    float2 spinePos = float2(-w * 0.5 + t * 0.5, 0.0);
    float dSpine = sdBox_F(p - spinePos, max(spineSize - r, 0.0)) - r;

    // -- Top Arm (Horizontal) --
    // Aligned to Top edge: y = h/2 - t/2
    // Extends from left edge (-w/2) to length. 
    // Length is clamped to not exceed width.
    float lTop = clamp(ArmLengthTop, t, w);
    float2 topSize = float2(lTop * 0.5, t * 0.5);
    // Center X is shifted so left edge matches spine's left edge
    float2 topPos = float2(-w * 0.5 + lTop * 0.5, h * 0.5 - t * 0.5);
    float dTop = sdBox_F(p - topPos, max(topSize - r, 0.0)) - r;

    // -- Middle Arm (Horizontal) --
    // Vertical position controlled by MiddleArmY
    float lMid = clamp(ArmLengthMiddle, t, w);
    float2 midSize = float2(lMid * 0.5, t * 0.5);
    // Clamp Y to prevent detaching from spine area vertically
    float midY = clamp(MiddleArmY, -h * 0.5 + t, h * 0.5 - t * 1.5);
    float2 midPos = float2(-w * 0.5 + lMid * 0.5, midY);
    float dMid = sdBox_F(p - midPos, max(midSize - r, 0.0)) - r;

    // 4. Combine (Union)
    float d = min(dSpine, min(dTop, dMid));

    // 5. Rendering / Anti-Aliasing
    float aa = fwidth(d);
    aa = max(aa, 0.0001); // Safety against zero derivative

    // Fill Mask
    float fillAlpha = 1.0 - smoothstep(-aa, aa, d);
    float4 fillLayer = float4(FillColor.rgb, FillColor.a * fillAlpha);

    // Stroke Mask
    float halfStroke = max(StrokeThickness, 0.0) * 0.5;
    float strokeDist = abs(d) - halfStroke;
    float strokeAlpha = 1.0 - smoothstep(-aa, aa, strokeDist);
    float4 strokeLayer = float4(StrokeColor.rgb, StrokeColor.a * strokeAlpha);

    // 6. Composite
    outColor = compositeOver_F(strokeLayer, fillLayer);
}