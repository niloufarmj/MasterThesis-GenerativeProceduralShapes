/*
  User Request: Letter K shape with adjustable spine, legs, thickness, angle, intersection height, corner rounding, and stroke.
  Plan:
  1) Define helper for Oriented Box SDF (segment with thickness).
  2) Define helper for alpha blending (src over dst).
  3) In main function, recenter UVs and define bounding box logic.
  4) Construct Vertical Spine SDF (left aligned).
  5) Construct Upper and Lower Leg SDFs originating from the spine.
     - Use ray-box intersection logic to clip legs to the bounding width/height.
  6) Apply corner rounding by shrinking the box dimensions and subtracting radius from SDF.
  7) Combine parts using min() for union.
  8) Compute stroke and fill masks with smoothstep AA.
  9) Composite output color.
*/

#ifndef LETTER_K_HELPERS
#define LETTER_K_HELPERS

// SDF for an Oriented Box (Segment with thickness)
// p: sampling point
// a: start point
// b: end point
// th: thickness
float sdOrientedBox(float2 p, float2 a, float2 b, float th)
{
    float l = length(b - a);
    float2 d = (b - a) / max(l, 0.0001);
    float2 q = p - (a + b) * 0.5;
    q = float2(dot(q, d), dot(q, float2(-d.y, d.x)));
    q = abs(q) - float2(l, th) * 0.5;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
}

// Alpha blending helper
float4 letter_k_over(float4 src, float4 dst)
{
    float a = src.a + dst.a * (1.0 - src.a);
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-8);
    return float4(c, a);
}
#endif

void LetterKShape_float(float2 UV, float Width, float Height, float Thickness, float AngleRad, float IntersectionHeight, float CornerRounding, float2 Center, float4 FillColor, float4 StrokeColor, float StrokeWidth, out float4 outColor)
{
    // 1. Setup Coordinates
    float2 p = UV - Center;
    
    // 2. Validate Parameters
    float w = max(Width, 0.001);
    float h = max(Height, 0.001);
    float th = max(Thickness, 0.001);
    // Clamp corner radius to prevent shape inversion (max is half thickness)
    float r = clamp(CornerRounding, 0.0, th * 0.5);
    
    // 3. Define Shapes
    // Effective thickness and lengths for rounding compensation
    // We subtract 2*r from box size, then subtract r from SDF to round corners
    float effTh = max(th - 2.0 * r, 0.0);
    
    // --- SPINE ---
    // Left-aligned vertical spine
    // X position: Left edge (-w/2) + half thickness
    float spineX = -w * 0.5 + th * 0.5;
    // Spine goes from bottom to top, shortened by r to keep exact height bounds
    float spineHalfH = h * 0.5 - r;
    float2 spineA = float2(spineX, -spineHalfH);
    float2 spineB = float2(spineX, spineHalfH);
    
    float dSpine = sdOrientedBox(p, spineA, spineB, effTh) - r;

    // --- LEGS ---
    // Legs start from the spine at the intersection height
    float2 startP = float2(spineX, IntersectionHeight);
    
    // Direction vectors
    // Ensure angle doesn't cause div by zero issues
    float ang = AngleRad;
    float2 dirUp = float2(cos(ang), sin(ang));
    float2 dirDown = float2(cos(ang), -sin(ang));
    
    // Calculate intersection with bounding box edges (Right, Top, Bottom)
    // Bounding box limits (adjusted for rounding/thickness roughly, but geometric bounds are cleaner)
    float boundRight = w * 0.5 - r;
    float boundTop = h * 0.5 - r;
    float boundBottom = -h * 0.5 + r;
    
    // Upper Leg Length
    // Distance to right wall
    float distRightUp = (boundRight - startP.x) / max(dirUp.x, 0.001);
    // Distance to top wall
    float distTop = (boundTop - startP.y) / max(dirUp.y, 0.001);
    float lenUp = min(distRightUp, distTop);
    // Clamp to 0 just in case
    lenUp = max(lenUp, 0.0);
    float2 endUp = startP + dirUp * lenUp;
    
    // Lower Leg Length
    // Distance to right wall
    float distRightDown = (boundRight - startP.x) / max(dirDown.x, 0.001);
    // Distance to bottom wall (dirDown.y is negative)
    float distBottom = (boundBottom - startP.y) / min(dirDown.y, -0.001);
    float lenDown = min(distRightDown, distBottom);
    lenDown = max(lenDown, 0.0);
    float2 endDown = startP + dirDown * lenDown;
    
    // Compute Leg SDFs
    float dLegUp = sdOrientedBox(p, startP, endUp, effTh) - r;
    float dLegDown = sdOrientedBox(p, startP, endDown, effTh) - r;
    
    // 4. Combine Shapes (Union)
    float d = min(dSpine, min(dLegUp, dLegDown));
    
    // 5. Rendering
    float aa = fwidth(d);
    
    // Fill
    float fillAlpha = 1.0 - smoothstep(-aa, aa, d);
    float4 fillLayer = float4(FillColor.rgb, FillColor.a * fillAlpha);
    
    // Stroke
    float halfStroke = StrokeWidth * 0.5;
    float strokeD = abs(d) - halfStroke;
    float strokeAlpha = 1.0 - smoothstep(-aa, aa, strokeD);
    float4 strokeLayer = float4(StrokeColor.rgb, StrokeColor.a * strokeAlpha);
    
    // Composite Stroke Over Fill
    outColor = letter_k_over(strokeLayer, fillLayer);
}