#ifndef PI
#define PI 3.14159265359
#endif

// Helper: Ellipse SDF approximation
// p: local point (centered)
// r: radius (half-extents)
float sdEllipse(float2 p, float2 r) {
    r = max(r, 0.001); // Prevent divide by zero
    float k0 = length(p / r);
    float k1 = length(p / (r * r));
    return k0 * (k0 - 1.0) / k1;
}

// Helper: Segment/Capsule SDF
// p: point, a: start, b: end, r: radius
float sdSegment(float2 p, float2 a, float2 b, float r) {
    float2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h) - r;
}

void CartoonBranch_float(float2 UV, float StemHeight, float StemCurvature, float StemThickness, float4 StemColor, float LeafCount, float2 LeafSize, float LeafSpacing, float LeafAngle, float4 LeafColor, float HighlightSize, float4 HighlightColor, out float4 outColor) {
    // User Request: a cartoon plant branch consisting of a central stem with adjustable height, curvature, and color, multiple rounded leaves attached along the stem where the number of leaves, their size, and spacing are adjustable, leaf orientation is adjustable relative to the stem, optional highlight reflections on the leaves with adjustable size, flat 2D style with smooth connected shapes.
    
    // PLAN:
    // 1) Normalize UVs so the plant base is at (0.5, 0.0).
    // 2) Apply a quadratic curve to the coordinate space to bend the stem.
    // 3) Calculate Stem SDF using a capsule segment.
    // 4) Loop through leaves:
    //    - Calculate attachment point along the bent stem.
    //    - Rotate local coordinates for leaf orientation.
    //    - Calculate Leaf SDF (ellipse) and Highlight SDF.
    //    - Combine using union (min).
    // 5) Resolve colors and apply anti-aliasing masks.

    // 1. Coordinate Setup
    // Center X at 0.5, Base Y at 0.05 to leave some margin
    float2 p = UV - float2(0.5, 0.05);

    // 2. Apply Stem Curvature
    // Bend the space: x' = x - k * y^2
    // This creates a parabolic curve for the vertical axis
    float2 bentP = p;
    bentP.x -= StemCurvature * bentP.y * bentP.y;

    // 3. Stem SDF
    // Vertical capsule in bent space from 0 to StemHeight
    float dStem = sdSegment(bentP, float2(0.0, 0.0), float2(0.0, StemHeight), StemThickness * 0.5);

    // 4. Leaves & Highlight SDF
    float dLeaves = 100.0;
    float dHighlight = 100.0;
    
    // Clamp leaf count to safe range
    int count = clamp((int)LeafCount, 0, 30);

    for (int i = 0; i < count; i++) {
        // Determine position along the stem
        float t = LeafSpacing * (float(i) + 1.0);
        
        // Stop if we exceed stem height
        if (t > StemHeight) break;

        // Alternate sides: -1.0 (Left), 1.0 (Right)
        float side = (fmod(float(i), 2.0) * 2.0) - 1.0;

        // Leaf attachment point in bent space
        float2 attachPos = float2(0.0, t);
        float2 localP = bentP - attachPos;

        // Rotate leaf
        // Base orientation: Horizontal (perpendicular to stem)
        // LeafAngle adjust: + tilts up, - tilts down
        // Angle calculation: side * (90 degrees - tilt)
        float angle = -side * (PI * 0.5 - LeafAngle);
        float c = cos(angle);
        float s = sin(angle);
        
        // Rotate point by -angle to rotate shape by +angle
        float2 leafP = float2(c * localP.x + s * localP.y, -s * localP.x + c * localP.y);

        // Center the leaf shape so (0,0) is the base/attachment point
        // We move the ellipse center up by half its length
        float2 leafDims = LeafSize;
        float2 centerOffset = float2(0.0, leafDims.y * 0.5);
        
        // Compute Leaf SDF (Ellipse)
        float dL = sdEllipse(leafP - centerOffset, leafDims * 0.5);
        dLeaves = min(dLeaves, dL);

        // Compute Highlight SDF (Smaller Ellipse)
        // Only if size > 0
        if (HighlightSize > 0.001) {
            // Offset highlight to the upper-left of the leaf (relative to leaf orientation)
            float2 hlOffset = float2(-leafDims.x * 0.15, leafDims.y * 0.6);
            // Scale highlight based on leaf size
            float2 hlRadius = float2(HighlightSize, HighlightSize * 1.5);
            float dH = sdEllipse(leafP - hlOffset, hlRadius);
            dHighlight = min(dHighlight, dH);
        }
    }

    // 5. Masks and Colors
    float aa = 0.005; // Anti-aliasing width

    // Combined Shape SDF
    float dFinal = min(dStem, dLeaves);
    
    // Alpha Mask (Overall Opacity)
    float alpha = 1.0 - smoothstep(-aa, aa, dFinal);

    // Determine which object is drawn (Leaf vs Stem)
    // If dLeaves < dStem, we favor leaf color
    float isLeaf = smoothstep(0.0, 0.001, dStem - dLeaves);
    
    // Base Color Mix (Stem vs Leaf)
    float3 baseColor = lerp(StemColor.rgb, LeafColor.rgb, isLeaf);

    // Highlight Mask
    // Must be inside the leaf shape, so we clip it by leaf alpha
    float hlMask = 1.0 - smoothstep(-aa, aa, dHighlight);
    float leafAlpha = 1.0 - smoothstep(-aa, aa, dLeaves);
    hlMask *= leafAlpha;

    // Apply Highlight Color
    float3 finalRGB = lerp(baseColor, HighlightColor.rgb, hlMask * HighlightColor.a);

    // Final Output (Premultiplied Alpha)
    outColor = float4(finalRGB * alpha, alpha);
}