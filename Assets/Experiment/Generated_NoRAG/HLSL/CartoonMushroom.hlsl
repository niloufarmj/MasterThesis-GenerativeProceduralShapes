// PLAN:
// 1) Define SDF helpers: sdEllipseApprox for the cap, sdRoundBox for the stalk, and nm_over for alpha compositing.
// 2) Calculate local coordinates by shifting the centered UV so the whole mushroom is vertically centered.
// 3) Stalk SDF: a rounded box extending downward from the cap base.
// 4) Cap SDF: the intersection of an ellipse and a flat half-plane (y=0), offset inward then outward by a small corner radius to slightly round the sharp intersection corners.
// 5) Spots SDF: union of three small circles distributed symmetrically on the cap surface.
// 6) Composite layers back-to-front using nm_over to naturally occlusion outlines:
//    - Stalk Fill
//    - Stalk Outline
//    - Cap Fill
//    - Cap Outline
//    - Spots Fill (masked to remain strictly inside the cap outline)

#ifndef NM_OVER_HELPER
#define NM_OVER_HELPER
inline float4 nm_over(float4 src, float4 dst)
{
    float a = src.a + dst.a * (1.0 - src.a);
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-8);
    return float4(c, a);
}
#endif

inline float sdEllipseApprox(float2 p, float2 halfAxes)
{
    float a = max(halfAxes.x, 1e-8);
    float b = max(halfAxes.y, 1e-8);

    float aa = a * a;
    float bb = b * b;

    float x = p.x, y = p.y;
    float F = (x * x) / aa + (y * y) / bb - 1.0;

    float gradLen = 2.0 * sqrt((x * x) / (aa * aa) + (y * y) / (bb * bb));

    return (gradLen > 1e-8) ? (F / gradLen) : -min(a, b);
}

inline float sdRoundBox(float2 p, float2 b, float r)
{
    float2 q = abs(p) - b;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void CartoonMushroom_float(
    float2 UV,
    float CapWidth,
    float CapHeight,
    float4 CapColor,
    float StalkWidth,
    float StalkHeight,
    float4 StalkColor,
    float SpotRadius,
    float4 SpotColor,
    float StrokeThickness,
    float4 StrokeColor,
    out float4 outColor)
{
    // 1. Setup local coordinates
    float2 centered = UV - 0.5;
    
    // Protect inputs to prevent artifacts
    float capW = max(CapWidth, 0.01);
    float capH = max(CapHeight, 0.01);
    float stalkW = max(StalkWidth, 0.01);
    float stalkH = max(StalkHeight, 0.01);
    float spotR = max(SpotRadius, 0.001);
    float halfStroke = max(StrokeThickness * 0.5, 0.0001);
    
    // Shift Y so the entire mushroom is centered in the UV frame
    // Bounding box in local space is roughly [-stalkH, capH]
    // Midpoint is (capH - stalkH) * 0.5
    float2 pLocal = centered;
    pLocal.y += (capH - stalkH) * 0.5;
    
    // 2. Stalk SDF
    float stalkCornerR = 0.02;
    float2 bStalk = float2(stalkW * 0.5 - stalkCornerR, stalkH * 0.5 - stalkCornerR);
    bStalk = max(bStalk, 0.001);
    
    float2 pStalk = pLocal;
    pStalk.y += stalkH * 0.5; // Shift down so the flat top of stalk is at y=0
    
    float dStalk = sdRoundBox(pStalk, bStalk, stalkCornerR);
    float stalkAA = fwidth(dStalk);
    float stalkFillMask = 1.0 - smoothstep(0.0, stalkAA, dStalk);
    float stalkEdge = abs(dStalk) - halfStroke;
    float stalkOutlineMask = 1.0 - smoothstep(0.0, stalkAA, stalkEdge);
    
    // 3. Cap SDF
    float capCornerR = 0.03;
    float2 capHalfAxes = float2(capW * 0.5, capH);
    float2 bEllipse = float2(max(capHalfAxes.x - capCornerR, 0.001), max(capHalfAxes.y - capCornerR, 0.001));
    float dEllipse = sdEllipseApprox(pLocal, bEllipse);
    
    // Flat bottom at y=0, shifted by capCornerR for true intersection rounding
    float dFlat = -(pLocal.y + capCornerR);
    float dCap = max(dEllipse, dFlat) - capCornerR;
    float capAA = fwidth(dCap);
    float capFillMask = 1.0 - smoothstep(0.0, capAA, dCap);
    float capEdge = abs(dCap) - halfStroke;
    float capOutlineMask = 1.0 - smoothstep(0.0, capAA, capEdge);
    
    // 4. Spots SDF (3 spots placed dynamically on the cap)
    float2 s1 = float2(0.0, capH * 0.6);
    float2 s2 = float2(-capW * 0.25, capH * 0.25);
    float2 s3 = float2(capW * 0.25, capH * 0.25);
    
    float dS1 = length(pLocal - s1) - spotR;
    float dS2 = length(pLocal - s2) - spotR;
    float dS3 = length(pLocal - s3) - spotR;
    float dSpots = min(min(dS1, dS2), dS3);
    float spotAA = fwidth(dSpots);
    float spotFillMask = 1.0 - smoothstep(0.0, spotAA, dSpots);
    
    // Clip spots so they don't bleed onto the cap's outline if sized too large
    float innerCapMask = 1.0 - smoothstep(0.0, capAA, dCap + halfStroke);
    spotFillMask *= innerCapMask;
    
    // 5. Compositing using painter's algorithm
    float4 res = float4(0.0, 0.0, 0.0, 0.0);
    
    // Draw Stalk Base
    res = nm_over(float4(StalkColor.rgb, saturate(StalkColor.a) * stalkFillMask), res);
    res = nm_over(float4(StrokeColor.rgb, saturate(StrokeColor.a) * stalkOutlineMask), res);
    
    // Draw Cap strictly OVER Stalk (creates the classic mushroom underside overlap)
    res = nm_over(float4(CapColor.rgb, saturate(CapColor.a) * capFillMask), res);
    res = nm_over(float4(StrokeColor.rgb, saturate(StrokeColor.a) * capOutlineMask), res);
    
    // Draw Spots cleanly OVER Cap Fill
    res = nm_over(float4(SpotColor.rgb, saturate(SpotColor.a) * spotFillMask), res);
    
    outColor = res;
}