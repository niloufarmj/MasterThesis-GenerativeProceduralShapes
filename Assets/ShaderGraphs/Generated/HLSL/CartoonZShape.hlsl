#ifndef PI
#define PI 3.14159265359
#endif

// Helper: Box SDF
float sdBox(float2 p, float2 b) {
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// Helper: Oriented Box SDF (Capsule with flat ends)
float sdOrientedBox(float2 p, float2 a, float2 b, float th) {
    float l = length(b - a);
    float2 d = (b - a) / l;
    float2 q = (p - (a + b) * 0.5);
    q = float2(d.x * q.x + d.y * q.y, -d.y * q.x + d.x * q.y);
    q = abs(q) - float2(l * 0.5, th);
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
}

// Helper: Color Blend (Source Over Destination)
float4 blendOver(float4 src, float4 dst) {
    float a = src.a + dst.a * (1.0 - src.a);
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-6);
    return float4(c, a);
}

void CartoonZShape_float(float2 UV, float Size, float Thickness, float CornerRadius, float2 Center, float4 Color, float4 OutlineColor, float OutlineWidth, out float4 outColor) {
    // PLAN: Cartoon Z Shape with adjustable props
    // 1. Center UV coordinates around 'Center'.
    // 2. Adjust Size to account for CornerRadius (so shape doesn't balloon).
    // 3. Construct Z using 3 primitives: Top Box, Bottom Box, Diagonal Box.
    // 4. Combine using standard union (min).
    // 5. Apply CornerRadius by subtracting from the SDF.
    // 6. Generate Fill and Outline masks with AA.
    // 7. Composite Output.

    float2 p = UV - Center;

    // Validate inputs
    float r = max(CornerRadius, 0.0);
    float s = max(Size, 0.001);
    float t = max(Thickness, 0.001);
    float outlineW = max(OutlineWidth, 0.0);

    // Effective size for sharp primitives
    // Subtract r so that d - r results in the correct visual size
    float effSize = max(s - r, 0.001);
    float halfThick = t * 0.5;

    // 1. Top Horizontal Bar
    // Position: Top-Center of the Z bounding box
    float2 cTop = float2(0.0, effSize - halfThick);
    float dTop = sdBox(p - cTop, float2(effSize, halfThick));

    // 2. Bottom Horizontal Bar
    // Position: Bottom-Center of the Z bounding box
    float2 cBot = float2(0.0, -effSize + halfThick);
    float dBot = sdBox(p - cBot, float2(effSize, halfThick));

    // 3. Diagonal Bar
    // Connects the Top-Right end of Top Bar to Bottom-Left end of Bottom Bar
    // This ensures a clean connection for the Z shape
    float2 pA = float2(effSize, effSize - halfThick);
    float2 pB = float2(-effSize, -effSize + halfThick);
    float dDiag = sdOrientedBox(p, pA, pB, halfThick);

    // Union: Combine all parts (min distance)
    float dSharp = min(dTop, min(dBot, dDiag));

    // Rounding: Subtract radius to round convex corners
    float dFinal = dSharp - r;

    // Anti-aliasing (Screen-space derivative)
    float aa = fwidth(dFinal);

    // Fill Mask
    float fillMask = 1.0 - smoothstep(-aa, aa, dFinal);
    float4 finalFill = float4(Color.rgb, Color.a * fillMask);

    // Outline Mask (Centered on edge)
    float halfOutline = outlineW * 0.5;
    float dOutline = abs(dFinal) - halfOutline;
    float outlineMask = 1.0 - smoothstep(-aa, aa, dOutline);
    float4 finalStroke = float4(OutlineColor.rgb, OutlineColor.a * outlineMask);

    // Composite: Stroke over Fill
    outColor = blendOver(finalStroke, finalFill);
}