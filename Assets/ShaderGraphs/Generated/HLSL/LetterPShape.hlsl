#ifndef PI
#define PI 3.14159265359
#endif

// SDF Helper: Rounded Box
// p: position relative to center
// b: half-extents (width/2, height/2)
// r: corner radius
// Returns signed distance (negative inside)
inline float sdRoundBox_P(float2 p, float2 b, float r) {
    float2 q = abs(p) - b + r;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

// Helper: Source Over Destination Composite
inline float4 composite_P(float4 src, float4 dst) {
    float outA = src.a + dst.a * (1.0 - src.a);
    float3 outRGB = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(outA, 1e-5);
    return float4(outRGB, outA);
}

void LetterPShape_float(float2 UV, float Width, float Height, float SpineThickness, float LoopThickness, float LoopVerticalShift, float CornerRounding, float4 FillColor, float4 StrokeColor, float StrokeWidth, out float4 outColor) {
    // PLAN:
    // 1) Center UVs to (0,0) and define shape parameters.
    // 2) Calculate LoopRadius derived from Overall Width and SpineThickness.
    // 3) Construct Spine SDF (Vertical Rounded Box).
    // 4) Construct Loop SDF as a D-shape (Semi-circle) attached strictly to the right of the spine.
    // 5) Ensure the Loop does not bulge to the left (avoiding the 'keyhole' look) by clipping it.
    // 6) Combine Spine and Loop, subtract the inner hole.
    // 7) Render with analytic anti-aliasing.

    float2 p = UV - 0.5;
    
    // --- Dimensions & Layout ---
    // Calculate Loop Outer Radius based on total Width and Spine Thickness
    // This ensures the shape respects the 'Overall Width' parameter.
    float loopRadius = max(0.01, Width - SpineThickness);
    
    // Center the entire shape visually around (0,0)
    // The shape spans from x = -Width/2 to x = Width/2
    // Spine is on the left, Loop on the right.
    float startX = -Width * 0.5;
    
    // Spine Geometry
    float spineHalfW = SpineThickness * 0.5;
    float spineHalfH = Height * 0.5;
    float2 spineCenter = float2(startX + spineHalfW, 0.0);
    
    // Loop Geometry
    // Loop is attached to the right edge of the spine
    // Right edge of spine x = startX + SpineThickness
    float2 loopCenter = float2(startX + SpineThickness, LoopVerticalShift);
    
    // Clamp corner radius to fit spine
    float rBox = clamp(CornerRounding, 0.0, min(spineHalfW, spineHalfH));

    // --- SDF Construction ---
    
    // 1. Spine SDF (Vertical Stem)
    float dSpine = sdRoundBox_P(p - spineCenter, float2(spineHalfW, spineHalfH), rBox);
    
    // 2. Loop Outer SDF (Right Semi-Circle)
    // We model the loop as a circle, but we CLIP it to the right of the spine's right edge.
    // This prevents the circle from bulging out the left side of the spine (fixing the keyhole issue).
    // Clip Plane: x > loopCenter.x. SDF for right-half plane is -(p.x - loopCenter.x).
    float dLoopCircle = length(p - loopCenter) - loopRadius;
    float dLoopOuter = max(dLoopCircle, -(p.x - loopCenter.x));
    
    // 3. Loop Inner Hole SDF (Right Semi-Circle)
    float innerRadius = max(0.0, loopRadius - LoopThickness);
    float dHoleCircle = length(p - loopCenter) - innerRadius;
    float dHole = max(dHoleCircle, -(p.x - loopCenter.x));

    // 4. Combine Shapes
    // Base P Shape = Union of Spine and Loop Outer
    float dSolid = min(dSpine, dLoopOuter);
    
    // Final Shape = Subtract Hole from Solid
    float dShape = max(dSolid, -dHole);

    // --- Rendering ---
    float aa = fwidth(dShape);
    aa = max(aa, 0.0005);

    // Fill
    float fillMask = 1.0 - smoothstep(-aa, aa, dShape);
    float4 fillLayer = float4(FillColor.rgb, saturate(FillColor.a) * fillMask);

    // Stroke
    float halfStroke = StrokeWidth * 0.5;
    float dStroke = abs(dShape) - halfStroke;
    float strokeMask = 1.0 - smoothstep(-aa, aa, dStroke);
    float4 strokeLayer = float4(StrokeColor.rgb, saturate(StrokeColor.a) * strokeMask);

    // Composite
    outColor = composite_P(strokeLayer, fillLayer);
}