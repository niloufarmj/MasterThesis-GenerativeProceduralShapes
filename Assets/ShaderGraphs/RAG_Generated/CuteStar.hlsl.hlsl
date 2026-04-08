#ifndef PI
#define PI 3.14159265359
#endif

#ifndef NM_OVER_HELPER
#define NM_OVER_HELPER
inline float4 nm_over(float4 src, float4 dst) {
    float a = src.a + dst.a * (1.0 - src.a);
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-8);
    return float4(c, a);
}
#endif

#ifndef SD_ARC_HELPER
#define SD_ARC_HELPER
inline float sdArc(float2 p, float2 sc, float ra, float rb) {
    p.x = abs(p.x);
    return ((sc.y*p.x > sc.x*p.y) ? length(p - sc*ra) : abs(length(p) - ra)) - rb;
}
#endif

#ifndef SD_STAR5_HELPER
#define SD_STAR5_HELPER
inline float sdStar5(float2 p, float r, float rf) {
    const float2 k1 = float2(0.809016994375, -0.587785252292);
    const float2 k2 = float2(-k1.x, k1.y);
    p.x = abs(p.x);
    p -= 2.0 * max(dot(k1, p), 0.0) * k1;
    p -= 2.0 * max(dot(k2, p), 0.0) * k2;
    p.x = abs(p.x);
    p.y -= r;
    float2 ba = rf * float2(-k1.y, k1.x) - float2(0, 1);
    float h = clamp( dot(p,ba)/dot(ba,ba), 0.0, r );
    return length(p-ba*h) * sign(p.y*ba.x-p.x*ba.y);
}
#endif

void CuteStar_float(
    float2 UV,
    float4 StarColor,
    float4 OutlineColor,
    float4 FeatureColor,
    float4 HighlightColor,
    float LengthOfLegs,
    float InnerRadius,
    float OverallShapeCurvature,
    float OutlineThickness,
    float2 EyeSize,
    float EyeDistance,
    float MouthCurve,
    float MouthThickness,
    float2 FaceOffset,
    out float4 outColor
) {
    // Center UV coordinate system
    float2 p = UV - 0.5;

    // 1. Base Star Shape
    // Subtract curvature from radii so the overall bounding size remains roughly consistent
    float rOuter = max(LengthOfLegs - OverallShapeCurvature, 0.01);
    float rInner = max(InnerRadius - OverallShapeCurvature, 0.01);
    
    float dStarRaw = sdStar5(p, rOuter, rInner);
    float dStar = dStarRaw - OverallShapeCurvature;
    
    float aa = max(fwidth(dStar), 0.001);
    
    // Fill Mask
    float fillMask = 1.0 - smoothstep(0.0, aa, dStar);
    
    // Outline Mask (expand the shape outward to create a thick outer border)
    float dSolidOutline = dStar - OutlineThickness;
    float solidOutlineMask = 1.0 - smoothstep(0.0, aa, dSolidOutline);
    
    // 2. Face Features
    float2 pFace = p - FaceOffset;
    
    // Eyes (symmetrical)
    float2 pEye = pFace;
    pEye.x = abs(pEye.x) - EyeDistance * 0.5;
    // Scaled space for elliptical eyes
    float dEye = (length(pEye / max(EyeSize, 0.001)) - 1.0) * min(EyeSize.x, EyeSize.y);
    float eyeMask = 1.0 - smoothstep(0.0, aa, dEye);
    
    // Mouth (cute U-shape)
    float2 pMouth = pFace - float2(0.0, -0.02); // Position slightly below the eyes
    pMouth.y = -pMouth.y; // Flip Y to make the arc open upwards (U-shape)
    float mouthAngle = PI * 0.45;
    float2 scMouth = float2(sin(mouthAngle), cos(mouthAngle));
    float dMouth = sdArc(pMouth, scMouth, MouthCurve, MouthThickness);
    float mouthMask = 1.0 - smoothstep(0.0, aa, dMouth);
    
    float featureMask = max(eyeMask, mouthMask);
    
    // 3. Highlight
    // Create a curved stroke following the top-left inner contour of the star
    float highlightOffset = 0.035; 
    float dContour = abs(dStar + highlightOffset) - 0.01; // Thickness of highlight line
    
    // Intersect the contour with a spatial boundary to isolate it to the top-left
    float maskDist = length(p - float2(-0.16, 0.2)) - 0.14;
    float dHighlightLine = max(dContour, maskDist);
    
    // Add a small dot beneath the highlight curve
    float dHighlightDot = length(p - float2(-0.25, 0.10)) - 0.015;
    
    float dHighlight = min(dHighlightLine, dHighlightDot);
    float highlightMask = 1.0 - smoothstep(0.0, aa, dHighlight);
    // Ensure the highlight perfectly clips to the inside of the star
    highlightMask *= fillMask; 
    
    // 4. Compositing Layers
    float4 bg = float4(0.0, 0.0, 0.0, 0.0);
    float4 layerSolidOutline = float4(OutlineColor.rgb, OutlineColor.a * solidOutlineMask);
    float4 layerFill = float4(StarColor.rgb, StarColor.a * fillMask);
    float4 layerHighlight = float4(HighlightColor.rgb, HighlightColor.a * highlightMask);
    float4 layerFeature = float4(FeatureColor.rgb, FeatureColor.a * featureMask);
    
    // Painter's algorithm (Back to Front)
    outColor = nm_over(layerSolidOutline, bg);
    outColor = nm_over(layerFill, outColor);
    outColor = nm_over(layerHighlight, outColor);
    outColor = nm_over(layerFeature, outColor);
}
