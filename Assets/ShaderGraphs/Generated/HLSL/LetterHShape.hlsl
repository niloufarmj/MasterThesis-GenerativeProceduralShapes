#ifndef PI
#define PI 3.14159265359
#endif

// Helper: Signed Distance to a Box
// p: position relative to center
// b: half-extents (width/2, height/2)
float sdBox(float2 p, float2 b) {
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// Helper: Alpha blending (Source Over Destination)
float4 over(float4 src, float4 dst) {
    float a = src.a + dst.a * (1.0 - src.a);
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-8);
    return float4(c, a);
}

void LetterHShape_float(
    float2 UV,
    float Width,
    float Height,
    float Thickness,
    float CrossbarHeight,
    float CornerRadius,
    float2 Center,
    float Angle,
    float4 FillColor,
    float4 StrokeColor,
    float StrokeWidth,
    out float4 OutColor
) {
    // PLAN:
    // 1. Center UV and apply rotation to coordinate space.
    // 2. Exploit horizontal symmetry (abs(x)) to simplify SDF construction.
    // 3. Define dimensions for legs and crossbar based on Width/Height inputs.
    // 4. Compute SDFs for one vertical leg and the horizontal crossbar.
    // 5. Combine using min() for union.
    // 6. Subtract CornerRadius to apply rounding.
    // 7. Compute Fill and Stroke masks using smoothstep and fwidth for AA.
    // 8. Composite Stroke over Fill.

    // 1. Transform Space
    float2 p = UV - Center;
    float c = cos(Angle);
    float s = sin(Angle);
    p = float2(p.x * c - p.y * s, p.x * s + p.y * c);

    // 2. Symmetry
    // We only need to compute the right side because 'H' is symmetric across the Y axis
    float2 q = float2(abs(p.x), p.y);

    // 3. Dimensions
    // Clamp inputs to safe values
    float w = max(Width, 0.0);
    float h = max(Height, 0.0);
    float t = max(Thickness, 0.0);
    
    float halfThick = t * 0.5;
    // Leg X position is derived from total width minus half thickness
    float legX = max(0.0, w * 0.5 - halfThick);
    
    // 4. SDF Calculation
    // Vertical Leg SDF: Centered at (legX, 0)
    float dLeg = sdBox(q - float2(legX, 0.0), float2(halfThick, h * 0.5));

    // Crossbar SDF: Centered at (0, CrossbarHeight)
    // The bar extends from center (0) to legX (center of leg).
    // Since the leg has thickness, extending to legX guarantees overlap.
    float dBar = sdBox(q - float2(0.0, CrossbarHeight), float2(legX, halfThick));

    // 5. Union
    float d = min(dLeg, dBar);

    // 6. Apply Rounding
    // Subtract radius from the field to round sharp corners
    float r = max(CornerRadius, 0.0);
    d -= r;

    // 7. AA and Coloring
    float aa = fwidth(d);
    
    // Fill Mask (d < 0 is inside)
    float fillAlpha = 1.0 - smoothstep(-aa, aa, d);
    float4 fill = float4(FillColor.rgb, FillColor.a * fillAlpha);

    // Stroke Mask (band around d = 0)
    float halfStroke = max(StrokeWidth, 0.0) * 0.5;
    float strokeDist = abs(d) - halfStroke;
    float strokeAlpha = 1.0 - smoothstep(-aa, aa, strokeDist);
    float4 stroke = float4(StrokeColor.rgb, StrokeColor.a * strokeAlpha);

    // 8. Composite
    OutColor = over(stroke, fill);
}