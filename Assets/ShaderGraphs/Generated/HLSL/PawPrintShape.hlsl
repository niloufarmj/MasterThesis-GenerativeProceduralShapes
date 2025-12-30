/* 
  USER REQUEST:
  A cartoon paw print consisting of a large central pad shape with adjustable width, height, and lobed curvature, 
  surmounted by an arc of smaller separate toe pads where the number of toes, their size, and radial spacing are adjustable, 
  flat 2D style with clean outlines and adjustable stroke thickness.
*/

#ifndef PAW_PRINT_HELPERS
#define PAW_PRINT_HELPERS

#ifndef PI
#define PI 3.14159265359
#endif

// Smooth Union (Metaball blending)
// d1, d2: SDFs to blend
// k: Smoothness factor (0.0 = sharp, 0.5+ = very blobby)
float opSmoothUnion(float d1, float d2, float k) {
    float h = clamp(0.5 + 0.5 * (d2 - d1) / max(k, 0.0001), 0.0, 1.0);
    return lerp(d2, d1, h) - k * h * (1.0 - h);
}

// Simple Circle SDF
float sdCircle(float2 p, float r) {
    return length(p) - r;
}

// Safe alpha composition (Source Over Destination)
float4 composite(float4 src, float4 dst) {
    float a = src.a + dst.a * (1.0 - src.a);
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-8);
    return float4(c, a);
}

#endif // PAW_PRINT_HELPERS

void PawPrintShape_float(
    float2 UV,
    float2 Center,
    float Rotation,
    float2 PadSize,      // x: Width factor, y: Height factor
    float PadSmoothness, // Controls lobed curvature blending
    float ToeCount,
    float ToeSize,
    float ToeDistance,
    float ToeSpread,     // Arc spread in radians
    float4 FillColor,
    float4 StrokeColor,
    float StrokeThickness,
    out float4 OutColor
) {
    // PLAN:
    // 1) Center and rotate the UV coordinates.
    // 2) Construct the Central Pad using a smooth union of 3 circles (1 bottom base, 2 top lobes).
    // 3) Construct the Toes using a loop to place circles in an arc.
    // 4) Combine Pad and Toes using min() (standard union).
    // 5) Render solid fill and outline using smoothstep for anti-aliasing.

    // 1. Transform Coordinates
    float2 p = UV - Center;
    float c = cos(Rotation);
    float s = sin(Rotation);
    p = float2(c * p.x + s * p.y, -s * p.x + c * p.y);

    // 2. Central Pad SDF (Metaball construction)
    // Scales for the pad components
    float w = max(PadSize.x, 0.01);
    float h = max(PadSize.y, 0.01);
    float k = max(PadSmoothness, 0.01);

    // Bottom Base Circle (Large anchor)
    float2 posBot = float2(0.0, -0.15 * h);
    float rBot = 0.25 * w;
    float dPad = sdCircle(p - posBot, rBot);

    // Top Left Lobe
    float2 posTL = float2(-0.2 * w, 0.15 * h);
    float rLobe = 0.18 * w;
    float dTL = sdCircle(p - posTL, rLobe);

    // Top Right Lobe
    float2 posTR = float2(0.2 * w, 0.15 * h);
    float dTR = sdCircle(p - posTR, rLobe);

    // Blend lobes together, then blend with base
    float dLobes = opSmoothUnion(dTL, dTR, k);
    dPad = opSmoothUnion(dPad, dLobes, k);

    // 3. Toes SDF
    float dToes = 100.0;
    int iCount = clamp((int)ToeCount, 0, 12); // Limit loop for safety
    
    // Calculate arc steps
    // If count > 1, spread from -Spread/2 to +Spread/2
    // If count == 1, center at 0
    float halfSpread = ToeSpread * 0.5;
    float angleStep = (iCount > 1) ? (ToeSpread / float(iCount - 1)) : 0.0;
    float startAngle = (iCount > 1) ? -halfSpread : 0.0;

    if (iCount > 0) {
        for (int i = 0; i < iCount; i++) {
            // Calculate angle for this toe (0 is Up/Y-axis in this local space)
            float ang = startAngle + float(i) * angleStep;
            
            // Convert polar (angle, distance) to cartesian offset
            // sin(ang) gives X, cos(ang) gives Y for 0=Up orientation
            float2 toeOffset = float2(sin(ang), cos(ang)) * ToeDistance;
            
            float dSingleToe = sdCircle(p - toeOffset, ToeSize);
            dToes = min(dToes, dSingleToe);
        }
    }

    // 4. Combine Shapes (Union)
    float dFinal = min(dPad, dToes);

    // 5. Rendering
    // Calculate anti-aliasing width based on derivatives
    float aa = fwidth(dFinal);
    
    // Fill Mask (Inner shape)
    // SDF is negative inside, so we smoothstep across 0
    float fillMask = 1.0 - smoothstep(-aa, aa, dFinal);
    float4 fillOut = float4(FillColor.rgb, FillColor.a * fillMask);

    // Stroke Mask (Outline)
    // Band centered at d=0 with total width = StrokeThickness
    float halfStroke = max(StrokeThickness, 0.0) * 0.5;
    float dStroke = abs(dFinal) - halfStroke;
    float strokeMask = 1.0 - smoothstep(-aa, aa, dStroke);
    float4 strokeOut = float4(StrokeColor.rgb, StrokeColor.a * strokeMask);

    // Composite Stroke OVER Fill
    OutColor = composite(strokeOut, fillOut);
}