/* 
  Letter B Shape
  - Vertical spine on left, two semi-circular loops on right.
  - Adjustable ratio, curvature, spine thickness, and holes.
*/

#ifndef PI
#define PI 3.14159265359
#endif

// Helper: Rounded Box with varying corner radii
// r = (TopRight, BottomRight, TopLeft, BottomLeft)
float sdRoundedBoxVarying(float2 p, float2 b, float4 r) {
    r.xy = (p.x > 0.0) ? r.xy : r.zw;
    r.x  = (p.y > 0.0) ? r.x  : r.y;
    float2 q = abs(p) - b + r.x;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r.x;
}

void LetterBShape_float(float2 UV, float Width, float Height, float SpineThickness, float TopLoopRatio, float LoopCurvature, float HoleScale, float CornerRounding, float2 Center, float Angle, float4 FillColor, float4 OutlineColor, float OutlineWidth, out float4 outColor) {
    // 1) Coordinate Setup
    float2 p = UV - Center;
    float s = sin(-Angle);
    float c = cos(-Angle);
    p = float2(p.x * c - p.y * s, p.x * s + p.y * c);
    
    // 2) Dimensions and Split
    float2 dim = float2(Width, Height) * 0.5;
    // Split Y based on TopLoopRatio (0=all bottom, 1=all top)
    float totalH = dim.y * 2.0;
    float splitY = -dim.y + totalH * (1.0 - clamp(TopLoopRatio, 0.1, 0.9));
    
    // 3) Define Zones (Top and Bottom Loops)
    // We model the B as two stacked boxes that overlap on the left to form the spine.
    // Top Box
    float topH = dim.y - splitY;
    float2 topSize = float2(dim.x, topH * 0.5);
    float2 topCenter = float2(0.0, splitY + topSize.y);
    
    // Bottom Box
    float botH = splitY - (-dim.y);
    float2 botSize = float2(dim.x, botH * 0.5);
    float2 botCenter = float2(0.0, -dim.y + botSize.y);
    
    // 4) Radii Calculation
    // Outer right corners get LoopCurvature. Left corners get CornerRounding (spine ends).
    // Middle-left corners are 0 to merge the spine seamlessly.
    float minDim = min(dim.x, min(topSize.y, botSize.y));
    float rCurve = minDim * clamp(LoopCurvature, 0.0, 1.0) * 2.0;
    float rSpine = minDim * clamp(CornerRounding, 0.0, 1.0);
    
    // Radii vectors: (TR, BR, TL, BL)
    float4 rTop = float4(rCurve, rCurve, rSpine, 0.0);
    float4 rBot = float4(rCurve, rCurve, 0.0, rSpine);
    
    // 5) Outer SDF
    float dTop = sdRoundedBoxVarying(p - topCenter, topSize, rTop);
    float dBot = sdRoundedBoxVarying(p - botCenter, botSize, rBot);
    float dOuter = min(dTop, dBot);
    
    // 6) Inner Holes SDF
    // Calculate padding based on HoleScale and dimensions
    // SpineThickness controls where the hole starts from the left
    float spineW = Width * clamp(SpineThickness, 0.05, 0.9);
    float padX = (dim.x * 2.0 - spineW) * (1.0 - clamp(HoleScale, 0.0, 0.95)) * 0.5;
    float padY = min(topSize.y, botSize.y) * (1.0 - clamp(HoleScale, 0.0, 0.95));
    
    // Hole Bounds
    float holeLeft = -dim.x + spineW + 0.01; // Small epsilon gap
    float holeRight = dim.x - padX;
    float holeW = max(holeRight - holeLeft, 0.0);
    
    float2 topHoleSize = float2(holeW * 0.5, max(topSize.y - padY, 0.0));
    float2 topHoleCenter = float2(holeLeft + topHoleSize.x, topCenter.y);
    
    float2 botHoleSize = float2(holeW * 0.5, max(botSize.y - padY, 0.0));
    float2 botHoleCenter = float2(holeLeft + botHoleSize.x, botCenter.y);
    
    // Hole Radii (reduced by padding to stay concentric)
    float rHole = max(rCurve - padX, 0.0);
    float4 rTopH = float4(rHole, rHole, max(rSpine - padX, 0.0), 0.0);
    float4 rBotH = float4(rHole, rHole, 0.0, max(rSpine - padX, 0.0));
    
    float dTopHole = sdRoundedBoxVarying(p - topHoleCenter, topHoleSize, rTopH);
    float dBotHole = sdRoundedBoxVarying(p - botHoleCenter, botHoleSize, rBotH);
    float dInner = min(dTopHole, dBotHole);
    
    // 7) Combine Outer and Inner (Subtraction)
    float dShape = max(dOuter, -dInner);
    
    // 8) Rendering (Anti-aliasing and Outline)
    float aa = fwidth(dShape);
    float alpha = 1.0 - smoothstep(-aa, aa, dShape);
    
    float dOutline = abs(dShape) - OutlineWidth * 0.5;
    float outlineAlpha = 1.0 - smoothstep(-aa, aa, dOutline);
    
    // Composite Outline over Fill
    float4 fill = float4(FillColor.rgb, FillColor.a * alpha);
    float4 stroke = float4(OutlineColor.rgb, OutlineColor.a * outlineAlpha);
    
    // Alpha blending (SrcOver)
    float outA = stroke.a + fill.a * (1.0 - stroke.a);
    float3 outRGB = (stroke.rgb * stroke.a + fill.rgb * fill.a * (1.0 - stroke.a)) / max(outA, 0.0001);
    
    outColor = float4(outRGB * outA, outA);
}