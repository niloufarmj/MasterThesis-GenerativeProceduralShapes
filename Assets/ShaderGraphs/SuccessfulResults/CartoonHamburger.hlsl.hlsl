#ifndef PI
#define PI 3.14159265359
#endif

// --- Helper Functions ---

// Signed distance for a rounded box with independent corner radii
// r = float4(TopRight, BottomRight, TopLeft, BottomLeft)
float sdRoundBoxUneven(float2 p, float2 b, float4 r) {
    float rad = (p.x > 0.0) ? ((p.y > 0.0) ? r.x : r.y) : ((p.y > 0.0) ? r.z : r.w);
    float2 q = abs(p) - b + rad;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - rad;
}

// Approximate signed distance to an ellipse
float sdEllipseApprox(float2 p, float2 halfAxes) {
    float a = max(halfAxes.x, 1e-8);
    float b = max(halfAxes.y, 1e-8);
    float aa = a * a;
    float bb = b * b;
    float x = p.x, y = p.y;
    float F = (x * x) / aa + (y * y) / bb - 1.0;
    float gradLen = 2.0 * sqrt((x * x) / (aa * aa) + (y * y) / (bb * bb));
    return (gradLen > 1e-8) ? (F / gradLen) : -min(a, b);
}

// Smooth/Rounded boolean intersection
float opIntersectRound(float d1, float d2, float r) {
    float2 u = max(float2(r + d1, r + d2), float2(0.0, 0.0));
    return min(max(d1, d2), -r) + length(u) - r;
}

// Straight-alpha "src over dst" blending
float4 shape_over(float4 src, float4 dst) {
    float a = src.a + dst.a * (1.0 - src.a);
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-6);
    return float4(c, a);
}

// Renders a shape with a solid fill and centered outline stroke
float4 drawShape(float4 baseColor, float d, float4 fillColor, float4 strokeColor, float strokeWidth) {
    float aa = max(fwidth(d), 0.001);
    
    float fillMask = 1.0 - smoothstep(-aa * 0.5, aa * 0.5, d);
    float4 fillLayer = float4(fillColor.rgb, fillColor.a * fillMask);
    
    float halfStroke = strokeWidth * 0.5;
    float dStroke = abs(d) - halfStroke;
    float strokeMask = 1.0 - smoothstep(-aa * 0.5, aa * 0.5, dStroke);
    float4 strokeLayer = float4(strokeColor.rgb, strokeColor.a * strokeMask);
    
    float4 shapeColor = shape_over(strokeLayer, fillLayer);
    return shape_over(shapeColor, baseColor);
}

// --- Main Function ---

void CartoonHamburger_float(
    float2 UV,
    float4 BunColor,
    float4 PattyColor,
    float4 LettuceColor,
    float4 StrokeColor,
    float4 SeedColor,
    float2 TopBunSize,
    float PattyThickness,
    float LettuceWaveFreq,
    float LettuceWaveAmp,
    float StrokeWidth,
    out float4 outColor
) {
    // Recenter UV to (-0.5, 0.5) coordinate space
    float2 p = UV - float2(0.5, 0.5);
    
    // Auto-stacking logic ensures layers perfectly touch regardless of parameter changes
    float currentY = -0.28;
    
    // 1. Bottom Bun Parameters
    float bbHeight = 0.09;
    float bbWidth = 0.33;
    float2 bbCenter = float2(0.0, currentY + bbHeight);
    currentY += bbHeight * 2.0;
    
    // 2. Patty Parameters
    float pattyHalfThickness = max(PattyThickness, 0.01);
    currentY -= 0.015; // Vertical overlap hides seams within strokes
    float2 pattyCenter = float2(0.0, currentY + pattyHalfThickness);
    currentY += pattyHalfThickness * 2.0;
    
    // 3. Lettuce Parameters
    float lettuceHalfHeight = 0.025;
    currentY -= 0.015;
    float2 lettuceCenter = float2(0.0, currentY + lettuceHalfHeight);
    currentY += lettuceHalfHeight * 2.0;
    
    // 4. Top Bun Parameters
    float topBunCutY = currentY - 0.015;
    float2 topBunCenter = float2(0.0, topBunCutY + TopBunSize.y * 0.3);
    
    // --- Distance Field Evaluations ---
    
    // Bottom Bun SDF (Flat top, highly rounded bottom corners)
    float dBottom = sdRoundBoxUneven(p - bbCenter, float2(bbWidth, bbHeight), float4(0.015, 0.09, 0.015, 0.09));
    
    // Patty SDF (Soft rounded rectangle)
    float dPatty = sdRoundBoxUneven(p - pattyCenter, float2(0.36, pattyHalfThickness), float4(0.04, 0.04, 0.04, 0.04));
    
    // Lettuce SDF (Wavy band overlapping patty)
    float2 pLettuce = p - lettuceCenter;
    pLettuce.y += cos(pLettuce.x * LettuceWaveFreq) * LettuceWaveAmp;
    float dLettuce = sdRoundBoxUneven(pLettuce, float2(0.39, lettuceHalfHeight), float4(0.01, 0.01, 0.01, 0.01));
    
    // Top Bun SDF (Ellipse clipped by horizontal plane with slightly rounded corners)
    float2 pTop = p - topBunCenter;
    float dEllipse = sdEllipseApprox(pTop, TopBunSize);
    float dPlane = topBunCutY - p.y;
    float dTop = opIntersectRound(dEllipse, dPlane, 0.02);
    
    // --- Layer Compositing ---
    float4 color = float4(0.0, 0.0, 0.0, 0.0);
    
    // Draw sequentially from bottom to top for correct outline overlap
    color = drawShape(color, dBottom, BunColor, StrokeColor, StrokeWidth);
    color = drawShape(color, dPatty, PattyColor, StrokeColor, StrokeWidth);
    color = drawShape(color, dLettuce, LettuceColor, StrokeColor, StrokeWidth);
    color = drawShape(color, dTop, BunColor, StrokeColor, StrokeWidth);
    
    // --- Sesame Seeds Details ---
    float dSeeds = 1e9;
    float2 seedRadius = float2(0.012, 0.025);
    
    // Seed 1 (Left)
    float2 ps1 = p - (topBunCenter + float2(-0.16, 0.08));
    float a1 = 0.5;
    float2 rps1 = float2(cos(a1)*ps1.x - sin(a1)*ps1.y, sin(a1)*ps1.x + cos(a1)*ps1.y);
    dSeeds = min(dSeeds, sdEllipseApprox(rps1, seedRadius));
    
    // Seed 2 (Middle Top)
    float2 ps2 = p - (topBunCenter + float2(0.02, 0.16));
    float a2 = -0.3;
    float2 rps2 = float2(cos(a2)*ps2.x - sin(a2)*ps2.y, sin(a2)*ps2.x + cos(a2)*ps2.y);
    dSeeds = min(dSeeds, sdEllipseApprox(rps2, seedRadius));
    
    // Seed 3 (Right)
    float2 ps3 = p - (topBunCenter + float2(0.18, 0.05));
    float a3 = 0.6;
    float2 rps3 = float2(cos(a3)*ps3.x - sin(a3)*ps3.y, sin(a3)*ps3.x + cos(a3)*ps3.y);
    dSeeds = min(dSeeds, sdEllipseApprox(rps3, seedRadius));
    
    // Blend solid seeds (no outlines)
    float seedAA = max(fwidth(dSeeds), 0.001);
    float seedMask = 1.0 - smoothstep(-seedAA * 0.5, seedAA * 0.5, dSeeds);
    color = shape_over(float4(SeedColor.rgb, SeedColor.a * seedMask), color);
    
    outColor = color;
}

// ------------------------------------------------------------------------
//  Visual Result (High-level, parameter-invariant description)
// ------------------------------------------------------------------------
//  This function produces a **2D cartoon hamburger** constructed from analytic SDFs. The resulting shape is composed of:
//
//  - A large semi-elliptical top bun with slightly rounded corners and adorned with small elliptical sesame seeds.
//  - A rectangular patty with softly rounded corners beneath the top bun.
//  - A wavy lettuce band that protrudes slightly from the sides of the patty, giving an organic, flowing appearance.
//  - A bottom bun with a flat top and highly rounded bottom corners, creating a stable base.
//
//  These components are stacked vertically with smooth transitions, creating a stylized, symmetric hamburger silhouette.
// ------------------------------------------------------------------------
