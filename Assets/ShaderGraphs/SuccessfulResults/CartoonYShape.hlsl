#ifndef PI
#define PI 3.14159265359
#endif

// --- Helper Functions ---

// Signed distance to a line segment (Capsule shape base)
float sdSegment_CartoonY(float2 p, float2 a, float2 b) {
    float2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}

// Polynomial smooth min (k = blend radius)
// Used to create the smooth, cartoon-like junction of the Y
float smin_CartoonY(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / max(k, 0.0001), 0.0, 1.0);
    return lerp(b, a, h) - k * h * (1.0 - h);
}

// Standard "Source Over" alpha compositing
float4 composite_CartoonY(float4 src, float4 dst) {
    float outA = src.a + dst.a * (1.0 - src.a);
    float3 outRGB = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(outA, 0.0001);
    return float4(outRGB, outA);
}

// --- Main Function ---
// Description: A cartoon letter Y with adjustable arms, thickness, smooth corners, and outline.
void CartoonYShape_float(
    float2 UV,
    float Size,
    float2 Center,
    float Thickness,
    float HandRadius,
    float CornerRadius,
    float4 FillColor,
    float4 StrokeColor,
    float StrokeWidth,
    out float4 outColor
) {
    // PLAN:
    // 1) Center UVs and scale by Size.
    // 2) Define the skeleton of the Y (Stem + 2 Arms) using line segments.
    // 3) Calculate SDFs for all segments.
    // 4) Use smin() to blend the stem and arms, creating the "Dynamic Corner Radius" at the junction.
    // 5) Subtract Thickness to create the volume (Capsule style).
    // 6) Generate Fill and Stroke masks using smoothstep for AA.
    // 7) Composite Stroke over Fill.

    // 1. Transform Coordinates
    float2 p = UV - Center;
    p /= max(Size, 0.0001);

    // 2. Define Skeleton Geometry
    // J is the central junction point. We lower it slightly (-0.1) so the Y feels visually centered.
    float2 junction = float2(0.0, -0.1);
    
    // Stem goes down. Length is proportional to HandRadius for consistency.
    float2 stemBase = junction - float2(0.0, max(HandRadius, 0.1) * 1.2);

    // Arms go up and out. We use a fixed pleasing angle (~40 degrees from vertical).
    float angle = 0.7; 
    float2 armDir = float2(sin(angle), cos(angle));
    
    // Calculate arm endpoints based on HandRadius
    float2 rightArm = junction + armDir * max(HandRadius, 0.01);
    float2 leftArm = junction + float2(-armDir.x, armDir.y) * max(HandRadius, 0.01);

    // 3. Compute SDFs
    float dStem = sdSegment_CartoonY(p, stemBase, junction);
    float dRight = sdSegment_CartoonY(p, junction, rightArm);
    float dLeft = sdSegment_CartoonY(p, junction, leftArm);

    // 4. Smooth Blend (The "Dynamic Corner Radius")
    // First blend the two arms (sharp union is fine here, or smooth if preferred)
    float dArms = min(dRight, dLeft);
    
    // Then blend the arms with the stem using smin to make the joint "gooey"/rounded
    // CornerRadius controls how much the joint melts together.
    float dShape = smin_CartoonY(dStem, dArms, max(CornerRadius, 0.001));

    // 5. Apply Thickness
    // SDF is distance to skeleton. Subtracting thickness gives the capsule surface.
    float dist = dShape - Thickness;

    // 6. Rendering Masks
    float aa = fwidth(dist);

    // Fill: Inside the shape (dist < 0)
    float fillAlpha = 1.0 - smoothstep(-aa, aa, dist);
    float4 fillLayer = float4(FillColor.rgb, FillColor.a * fillAlpha);

    // Stroke: Centered on the edge (abs(dist) < Width/2)
    float halfStroke = StrokeWidth * 0.5;
    float strokeDist = abs(dist) - halfStroke;
    float strokeAlpha = 1.0 - smoothstep(-aa, aa, strokeDist);
    float4 strokeLayer = float4(StrokeColor.rgb, StrokeColor.a * strokeAlpha);

    // 7. Composite Output
    outColor = composite_CartoonY(strokeLayer, fillLayer);
}