#ifndef PI
#define PI 3.14159265359
#endif

// Helper: Distance to line segment
float LWS_sdSegment(float2 p, float2 a, float2 b) {
    float2 pa = p - a, ba = b - a;
    float h = saturate(dot(pa, ba) / dot(ba, ba));
    return length(pa - ba * h);
}

// Helper: Smooth Minimum (polynomial) for dynamic rounded corners
float LWS_smin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / max(k, 1e-6), 0.0, 1.0);
    return lerp(b, a, h) - k * h * (1.0 - h);
}

// Helper: Color Composite (Source Over)
float4 LWS_over(float4 src, float4 dst) {
    float a = src.a + dst.a * (1.0 - src.a);
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-8);
    return float4(c, a);
}

// Main Function: Cartoon Letter W with adjustable properties
void LetterWShape_float(
    float2 UV,
    float Size,
    float2 Center,
    float Rotation,
    float Thickness,
    float CornerRadius,
    float4 FillColor,
    float4 OutlineColor,
    float OutlineWidth,
    out float4 outColor
) {
    // PLAN:
    // 1) Center and rotate UV coordinates.
    // 2) Define 5 points constituting the W skeleton based on Size.
    // 3) Calculate SDF to the 4 connecting segments.
    // 4) Combine segment SDFs using smooth minimum (smin) to create dynamic rounded joints.
    // 5) Subtract Thickness to create volume (thick stroke).
    // 6) Compute outline and fill masks using smoothstep for AA.
    // 7) Composite outline over fill and output.

    // 1) Center and rotate UV
    float2 p = UV - Center;
    float c = cos(Rotation);
    float s = sin(Rotation);
    p = float2(c * p.x - s * p.y, s * p.x + c * p.y);

    // 2) Define W skeleton points relative to size
    // Coordinates span roughly [-Size/2, Size/2]
    float halfS = Size * 0.5;
    
    // Points: TopLeft, BotLeft, MidJoint, BotRight, TopRight
    float2 p0 = float2(-halfS, halfS);
    float2 p1 = float2(-halfS * 0.5, -halfS);
    float2 p2 = float2(0.0, 0.0);
    float2 p3 = float2(halfS * 0.5, -halfS);
    float2 p4 = float2(halfS, halfS);

    // 3) Compute SDF to the 4 segments
    float d0 = LWS_sdSegment(p, p0, p1);
    float d1 = LWS_sdSegment(p, p1, p2);
    float d2 = LWS_sdSegment(p, p2, p3);
    float d3 = LWS_sdSegment(p, p3, p4);

    // 4) Combine segments with smooth minimum to round the joints
    float k = max(CornerRadius, 1e-4);
    float d = LWS_smin(d0, d1, k);
    d = LWS_smin(d, d2, k);
    d = LWS_smin(d, d3, k);

    // 5) Subtract thickness to form the solid shape (SDF < 0 is inside)
    float shapeSDF = d - max(Thickness, 0.0);

    // 6) Analytic Anti-Aliasing
    float aa = fwidth(shapeSDF);

    // 7) Fill Layer
    float fillMask = 1.0 - smoothstep(0.0, aa, shapeSDF);
    float4 fillLayer = float4(FillColor.rgb, FillColor.a * fillMask);

    // 8) Outline Layer
    // Outline is a band centered on the shape edge
    float halfOutline = max(OutlineWidth, 0.0) * 0.5;
    float outlineDist = abs(shapeSDF) - halfOutline;
    float outlineMask = 1.0 - smoothstep(0.0, aa, outlineDist);
    float4 outlineLayer = float4(OutlineColor.rgb, OutlineColor.a * outlineMask);

    // 9) Composite: Outline over Fill
    outColor = LWS_over(outlineLayer, fillLayer);
}