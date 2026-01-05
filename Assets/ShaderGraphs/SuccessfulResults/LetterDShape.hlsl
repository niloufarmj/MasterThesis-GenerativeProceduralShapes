#ifndef PI
#define PI 3.14159265359
#endif

// SDF for a box with varying corner radii
// r components: x=TopRight, y=BotRight, z=TopLeft, w=BotLeft
inline float sdRoundedBox4(float2 p, float2 b, float4 r) {
    // Select radius based on quadrant
    r.xy = (p.x > 0.0) ? r.xy : r.zw;
    r.x  = (p.y > 0.0) ? r.x  : r.y;
    float2 q = abs(p) - b + r.x;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r.x;
}

// Helper for alpha compositing (Source Over)
inline float4 compositeOver(float4 src, float4 dst) {
    float outA = src.a + dst.a * (1.0 - src.a);
    float3 outRGB = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(outA, 0.0001);
    return float4(outRGB, outA);
}

// Main Function: Letter D Shape
// A 'D' shape constructed as a rounded box where the right-side corners 
// have a large radius (controlled by CurveBulge) and the left side is flat (Spine).
void LetterDShape_float(float2 UV, float Width, float Height, float SpineThickness, float CurveBulge, float Rounding, float4 FillColor, float4 StrokeColor, float StrokeWidth, out float4 outColor) {
    // 1. Center coordinates
    float2 p = UV - 0.5;
    
    // 2. Define Box Dimensions (Half-size)
    float2 b = float2(max(Width, 0.0), max(Height, 0.0)) * 0.5;
    
    // 3. Calculate Radii for 'D' Shape
    // Left corners (Spine) use the generic Rounding value
    float rLeft = max(Rounding, 0.0);
    
    // Right corners (Curve) are calculated to form the 'bulge'.
    // The curve width effectively fills the space after the SpineThickness.
    float availableCurveWidth = max(Width - SpineThickness, 0.0);
    
    // Calculate desired radius. If CurveBulge is 1.0, we try to make it a full semi-circle.
    float rRight = availableCurveWidth * saturate(CurveBulge);
    
    // Clamp rRight to half-height to keep the SDF valid (no self-intersection)
    // This ensures that if the shape is very tall, it forms a semi-circle end.
    // If it's very wide, it forms a 'pill' end.
    rRight = min(rRight, b.y);
    
    // Ensure right radius is at least as round as the spine corners (optional, looks better)
    rRight = max(rRight, rLeft);
    
    // Construct Radii Vector: TR, BR, TL, BL
    float4 radii = float4(rRight, rRight, rLeft, rLeft);
    
    // 4. Compute Signed Distance Field
    float d = sdRoundedBox4(p, b, radii);
    
    // 5. Render with Anti-Aliasing
    float aa = fwidth(d);
    
    // Fill: 1.0 inside, 0.0 outside
    float fillAlpha = 1.0 - smoothstep(-aa, aa, d);
    
    // Stroke: Centered on the edge
    float halfStroke = StrokeWidth * 0.5;
    float strokeAlpha = 1.0 - smoothstep(-aa, aa, abs(d) - halfStroke);
    
    // 6. Composite Stroke over Fill
    float4 strokeLayer = float4(StrokeColor.rgb, StrokeColor.a * strokeAlpha);
    float4 fillLayer = float4(FillColor.rgb, FillColor.a * fillAlpha);
    
    outColor = compositeOver(strokeLayer, fillLayer);
}