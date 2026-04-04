/*
  PLAN:
  1. Define Signed Distance Functions for the 5-point star and utility shapes (boxes).
  2. Implement an alpha blending helper (nm_over).
  3. Main Function:
     a. Recenter and rotate UV coordinates.
     b. Evaluate Star SDF with rounding for the main body.
     c. Generate a thick, solid outline mask by expanding the Star SDF.
     d. Generate an inner shadow by offsetting a secondary Star SDF.
     e. Add facial features (elliptical eyes, U-shaped mouth cap logic).
     f. Add crescent highlight and dot using localized SDF intersections.
     g. Composite layers: Outline -> Body (+Shadow) -> Face -> Highlights.
*/

#ifndef PI
#define PI 3.14159265359
#endif

// Helper: 5-Point Star SDF
inline float sdStar5_helper(float2 p, float r, float rf)
{
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

// Helper: Box SDF for highlight masking
inline float sdBox_helper(float2 p, float2 b)
{
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// Helper: Straight-alpha "src over dst" blending
inline float4 nm_over(float4 src, float4 dst)
{
    float a = src.a + dst.a * (1.0 - src.a);
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-8);
    return float4(c, a);
}

void CartoonStar_float(
    float2 UV,
    float2 Center,
    float Rotation,
    float StarRadius,
    float StarInnerRadius,
    float StarRounding,
    float OutlineWidth,
    float4 BodyColor,
    float4 EdgeShadowColor,
    float4 OutlineColor,
    float4 HighlightColor,
    float2 EyeOffset,
    float EyeSize,
    float2 MouthOffset,
    float MouthRadius,
    float MouthThickness,
    float2 HighlightBoxPos,
    float2 HighlightDotPos,
    out float4 outColor
) {
    // 1) Space setup & Rotation
    float2 p = UV - Center;
    
    // Rotate coordinates (positive rotation tilts the shape clockwise)
    float c = cos(Rotation);
    float s = sin(Rotation);
    p = float2(p.x * c - p.y * s, p.x * s + p.y * c);

    // Analytic anti-aliasing factor
    float aa = length(float2(fwidth(p.x), fwidth(p.y))) * 0.707;
    aa = max(aa, 0.001);

    // 2) Base Star Shape
    // Subtracting StarRounding expands and rounds the convex points
    float dStar = sdStar5_helper(p, max(StarRadius, 0.001), max(StarInnerRadius, 0.0)) - StarRounding;

    // 3) Layer 0: Outline
    // Outline is an expansion of the base star
    float dOutline = dStar - OutlineWidth;
    float maskOutline = smoothstep(aa, -aa, dOutline);
    float4 col = float4(OutlineColor.rgb, OutlineColor.a * maskOutline);

    // 4) Layer 1: Body Fill
    float maskBody = smoothstep(aa, -aa, dStar);
    float4 bodyLayer = float4(BodyColor.rgb, BodyColor.a * maskBody);

    // Inner Shadow effect on the Body
    // Shift sampling point down-right to place shadow on the bottom-right interior
    float2 pShadow = p + float2(0.015, -0.015);
    float dStarShadow = sdStar5_helper(pShadow, StarRadius, StarInnerRadius) - StarRounding;
    
    // Soft threshold for a smooth gradient shadow
    float maskShadow = maskBody * smoothstep(-0.04, 0.02, dStarShadow);
    float4 shadowLayer = float4(EdgeShadowColor.rgb, EdgeShadowColor.a * maskShadow);
    
    // Composite Shadow over Body
    bodyLayer = nm_over(shadowLayer, bodyLayer);
    // Composite Body over Outline
    col = nm_over(bodyLayer, col);

    // 5) Layer 2: Facial Features
    // Eyes (vertically elongated ovals)
    float2 pEyeL = p - float2(-EyeOffset.x, EyeOffset.y);
    float2 pEyeR = p - float2( EyeOffset.x, EyeOffset.y);
    float dEyes = min(
        length(pEyeL * float2(1.0, 1.2)) - EyeSize,
        length(pEyeR * float2(1.0, 1.2)) - EyeSize
    );

    // Mouth (U-shape smile)
    float2 pMouth = p - MouthOffset;
    float dMouthRing = abs(length(pMouth) - MouthRadius) - MouthThickness;
    // Exact distance to the arc endpoints to cleanly cap the smile at y=0
    float dMouthCap = length(float2(abs(pMouth.x) - MouthRadius, pMouth.y)) - MouthThickness;
    float dMouth = (pMouth.y > 0.0) ? dMouthCap : dMouthRing;

    // Composite Face (matching the outline color)
    float dFace = min(dEyes, dMouth);
    float maskFace = smoothstep(aa, -aa, dFace);
    float4 faceLayer = float4(OutlineColor.rgb, OutlineColor.a * maskFace);
    col = nm_over(faceLayer, col);

    // 6) Layer 3: Highlights
    // Top-left crescent curve: stroke slightly inside the top-left edge
    float dHighlightCurve = abs(dStar + 0.025) - 0.007;
    // Mask out strictly to the target slope using a bounding box
    float maskBox = smoothstep(0.02, 0.0, sdBox_helper(p - HighlightBoxPos, float2(0.06, 0.06)));
    float maskHighlightCurve = smoothstep(aa, -aa, dHighlightCurve) * maskBox;
    
    // Small secondary shiny dot
    float dDot = length(p - HighlightDotPos) - 0.008;
    float maskDot = smoothstep(aa, -aa, dDot);
    
    float maskHighlight = max(maskHighlightCurve, maskDot);
    // Clamp to body purely as a safety margin
    maskHighlight *= smoothstep(aa, -aa, dStar);

    float4 highlightLayer = float4(HighlightColor.rgb, HighlightColor.a * maskHighlight);
    col = nm_over(highlightLayer, col);

    outColor = col;
}
