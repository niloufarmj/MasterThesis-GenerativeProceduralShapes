#ifndef PI
#define PI 3.14159265359
#endif

// Signed distance to an axis-aligned box
float sdBox(float2 p, float2 b) {
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// Alpha compositing: src over dst
float4 over(float4 src, float4 dst) {
    float a = src.a + dst.a * (1.0 - src.a);
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-8);
    return float4(c, a);
}

// Custom Function for a capital Letter L shape with adjustable leg length, thickness, and rounding
void LetterLShape_float(float2 UV, float Width, float Height, float Thickness, float Rounding, float2 Center, float Angle, float4 FillColor, float4 StrokeColor, float StrokeWidth, out float4 outColor) {
    // PLAN:
    // 1) Center UV coordinates and apply rotation.
    // 2) Define dimensions for the vertical spine and horizontal leg.
    // 3) Construct SDFs for both segments (boxes).
    // 4) Combine them using min() for union.
    // 5) Apply rounding via distance subtraction (compensating box size to maintain dimensions).
    // 6) Compute masks for fill and stroke with AA.
    // 7) Composite final output.

    // 1) Coordinates
    float2 p = UV - Center;
    
    // Rotation
    float c = cos(Angle);
    float s = sin(Angle);
    p = float2(c * p.x + s * p.y, -s * p.x + c * p.y);

    // 2) Dimensions
    // Clamp thickness to not exceed width/height to avoid artifacts
    float safeThickness = min(Thickness, min(Width, Height));
    float halfW = Width * 0.5;
    float halfH = Height * 0.5;
    float halfT = safeThickness * 0.5;

    // 3) Box Definitions
    // To support rounding that softens the shape without expanding it arbitrarily,
    // we subtract the radius from the box size and then subtract it from the final distance.
    // This creates a rounded shape that still fits within the specified bounds (mostly).
    float r = clamp(Rounding, 0.0, halfT); // Limit rounding to half thickness

    // Vertical Spine Box (Left side)
    // Extents: x from -halfW to -halfW + Thickness
    //          y from -halfH to halfH
    float2 centerV = float2(-halfW + halfT, 0.0);
    float2 sizeV = float2(halfT, halfH) - r;
    float distV = sdBox(p - centerV, sizeV);

    // Horizontal Leg Box (Bottom side)
    // Extents: x from -halfW to halfW
    //          y from -halfH to -halfH + Thickness
    float2 centerH = float2(0.0, -halfH + halfT);
    float2 sizeH = float2(halfW, halfT) - r;
    float distH = sdBox(p - centerH, sizeH);

    // 4) Union & 5) Rounding
    // min(distV, distH) unions the sharp boxes.
    // Subtracting r rounds the outer corners and fillets the inner junction.
    float dist = min(distV, distH) - r;

    // 6) Rendering
    float aa = fwidth(dist);
    
    // Fill Mask
    float fillAlpha = 1.0 - smoothstep(-aa, aa, dist);
    float4 fill = float4(FillColor.rgb, FillColor.a * fillAlpha);

    // Stroke Mask
    // Stroke is centered on the edge. Width is StrokeWidth.
    float halfStroke = StrokeWidth * 0.5;
    float strokeDist = abs(dist) - halfStroke;
    float strokeAlpha = 1.0 - smoothstep(-aa, aa, strokeDist);
    float4 stroke = float4(StrokeColor.rgb, StrokeColor.a * strokeAlpha);

    // 7) Composition
    outColor = over(stroke, fill);
}