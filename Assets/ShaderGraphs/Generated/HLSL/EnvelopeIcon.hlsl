#ifndef PI
#define PI 3.14159265359
#endif

// Helper: Distance to a line segment
// p: sampling point
// a, b: start and end of segment
float sdSegment(float2 p, float2 a, float2 b) {
    float2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}

// Helper: Distance to a rounded box
// p: sampling point
// b: half-extents (width/2, height/2)
// r: corner radius
float sdRoundedBox(float2 p, float2 b, float r) {
    float2 q = abs(p) - b + r;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

// Helper: Source Over Blend
float4 blendOver(float4 src, float4 dst) {
    float outA = src.a + dst.a * (1.0 - src.a);
    float3 outRGB = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(outA, 1e-5);
    return float4(outRGB, outA);
}

void EnvelopeIcon_float(float2 UV, float Width, float Height, float Size, float CornerRadius, float FlapHeight, float StrokeThickness, float2 Center, float Angle, float4 FillColor, float4 StrokeColor, out float4 outColor) {
    // PLAN:
    // 1) Transform UV to centered, rotated local coordinates (p).
    // 2) Define envelope body dimensions based on Width/Height/Size.
    // 3) Compute SDF for the main body (Rounded Box).
    // 4) Compute SDF for the flap lines (V-shape from top corners).
    // 5) Render filled body and strokes for body and flap.
    // 6) Composite stroke over fill.

    // 1. Transform Coordinates
    float2 p = UV - Center;
    float c = cos(Angle);
    float s = sin(Angle);
    p = float2(p.x * c - p.y * s, p.x * s + p.y * c);

    // 2. Define Dimensions
    // Half-sizes for the box (scaled by Size)
    float2 halfSize = float2(max(Width, 0.01), max(Height, 0.01)) * Size * 0.5;
    // Radius must not exceed dimensions
    float r = min(min(halfSize.x, halfSize.y), max(CornerRadius * Size, 0.0));

    // 3. Body SDF
    // The main container of the envelope
    float dBody = sdRoundedBox(p, halfSize, r);

    // 4. Flap SDF
    // Defines the "V" fold lines.
    // Tip drops down from the top center.
    float drop = FlapHeight * Size;
    float2 vTip = float2(0.0, halfSize.y - drop);
    // Lines start from top corners (schematic view)
    float2 vTL = float2(-halfSize.x, halfSize.y);
    float2 vTR = float2(halfSize.x, halfSize.y);
    
    // Union of left and right flap lines (min distance)
    float dFlap = min(sdSegment(p, vTL, vTip), sdSegment(p, vTR, vTip));

    // 5. Masks & Rendering
    // Anti-aliasing width based on derivatives
    float aa = fwidth(dBody);
    aa = max(aa, 0.0005); // Robust min AA

    // Fill Mask
    float fillMask = 1.0 - smoothstep(-aa, aa, dBody);
    float4 fillLayer = float4(FillColor.rgb, FillColor.a * fillMask);

    // Stroke Calculations
    // Center stroke on the geometric edge
    float halfStroke = StrokeThickness * 0.5;
    
    // Body Outline Distance
    float dBodyStroke = abs(dBody) - halfStroke;
    
    // Flap Stroke Distance
    float dFlapStroke = dFlap - halfStroke;
    
    // Combined Stroke (Union of body outline and flap lines)
    float dStroke = min(dBodyStroke, dFlapStroke);
    float strokeMask = 1.0 - smoothstep(-aa, aa, dStroke);
    float4 strokeLayer = float4(StrokeColor.rgb, StrokeColor.a * strokeMask);

    // 6. Composite (Stroke Over Fill)
    outColor = blendOver(strokeLayer, fillLayer);
}