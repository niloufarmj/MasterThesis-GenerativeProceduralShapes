#ifndef PI
#define PI 3.14159265359
#endif

// Helper: Calculate signed distance to a 2D triangle (CCW vertices)
float sdTriangle_Helper(float2 p, float2 p0, float2 p1, float2 p2) {
    float2 e0 = p1 - p0;
    float2 e1 = p2 - p1;
    float2 e2 = p0 - p2;

    float2 v0 = p - p0;
    float2 v1 = p - p1;
    float2 v2 = p - p2;

    float2 pq0 = v0 - e0 * clamp(dot(v0, e0) / dot(e0, e0), 0.0, 1.0);
    float2 pq1 = v1 - e1 * clamp(dot(v1, e1) / dot(e1, e1), 0.0, 1.0);
    float2 pq2 = v2 - e2 * clamp(dot(v2, e2) / dot(e2, e2), 0.0, 1.0);

    float s = sign(e0.x * e2.y - e0.y * e2.x);
    
    float2 d = min(min(float2(dot(pq0, pq0), s * (v0.x * e0.y - v0.y * e0.x)),
                       float2(dot(pq1, pq1), s * (v1.x * e1.y - v1.y * e1.x))), 
                       float2(dot(pq2, pq2), s * (v2.x * e2.y - v2.y * e2.x)));

    return -sqrt(d.x) * sign(d.y);
}

// Helper: Straight Alpha Blending (Source Over Destination)
float4 blendColors_Helper(float4 fg, float4 bg) {
    float a = fg.a + bg.a * (1.0 - fg.a);
    if (a < 1e-6) return float4(0.0, 0.0, 0.0, 0.0);
    float3 c = (fg.rgb * fg.a + bg.rgb * bg.a * (1.0 - fg.a)) / a;
    return float4(c, a);
}

void FoxFace_float(
    float2 UV,
    float FaceSize,
    float2 Center,
    float4 ColorOrange,
    float4 ColorDarkOrange,
    float4 ColorBeige,
    float4 ColorDark,
    float4 ColorWhite,
    out float4 outColor
) {
    // 1. Center and Scale Space
    float2 p = (UV - Center) / max(0.001, FaceSize);
    
    // 2. Symmetric Space for Mirrored Components (Ears, Cheeks, Eyes)
    float2 pSym = p;
    pSym.x = abs(pSym.x);

    // 3. Anti-Aliasing Setup
    float aa = max(fwidth(p.x), 0.001) * 1.5;
    float4 result = float4(0.0, 0.0, 0.0, 0.0);

    // 4. Outer Ears (Orange)
    // CCW vertices: Inner Base -> Outer Base -> Top Tip
    float dOuterEar = sdTriangle_Helper(pSym, float2(0.12, 0.05), float2(0.42, 0.0), float2(0.35, 0.42)) - 0.03;
    float maskOuter = smoothstep(aa, -aa, dOuterEar);
    float4 cOuter = float4(ColorOrange.rgb, saturate(ColorOrange.a) * maskOuter);
    result = blendColors_Helper(cOuter, result);

    // 5. Inner Ears (Dark Orange)
    float dInnerEar = sdTriangle_Helper(pSym, float2(0.16, 0.10), float2(0.38, 0.05), float2(0.32, 0.35)) - 0.02;
    float maskInner = smoothstep(aa, -aa, dInnerEar);
    float4 cInner = float4(ColorDarkOrange.rgb, saturate(ColorDarkOrange.a) * maskInner);
    result = blendColors_Helper(cInner, result);

    // 6. Face Base Form (Kite-like Diamond)
    // Bottom Triangle: Snout/Cheeks
    float dBottom = sdTriangle_Helper(p, float2(0.0, -0.38), float2(0.44, 0.05), float2(-0.44, 0.05));
    // Top Triangle: Forehead
    float dTop = sdTriangle_Helper(p, float2(0.0, 0.10), float2(-0.44, 0.05), float2(0.44, 0.05));
    // Union and round corners
    float dHead = min(dBottom, dTop) - 0.04;
    
    // 7. Cheek & Snout Color Separation
    // Define an invisible circle to create the sweeping curved boundary between Orange and Beige
    float2 centerC = float2(-0.6, 0.2);
    float rC = length(float2(0.0, -0.42) - centerC); // Pin exactly to the nose tip
    float dCheek = length(pSym - centerC) - rC;
    
    // Apply Base Face Colors
    float maskHead = smoothstep(aa, -aa, dHead);
    float cheekBlend = smoothstep(-aa, aa, dCheek);
    float4 headCol = lerp(ColorOrange, ColorBeige, cheekBlend);
    float4 cHead = float4(headCol.rgb, saturate(headCol.a) * maskHead);
    result = blendColors_Helper(cHead, result);

    // 8. Nose (Dark Gray/Black)
    float dNose = sdTriangle_Helper(p, float2(0.0, -0.41), float2(0.06, -0.35), float2(-0.06, -0.35)) - 0.01;
    float maskNose = smoothstep(aa, -aa, dNose);
    float4 cNose = float4(ColorDark.rgb, saturate(ColorDark.a) * maskNose);
    result = blendColors_Helper(cNose, result);

    // 9. Eyes (Dark Gray/Black)
    float dEye = length(pSym - float2(0.22, -0.16)) - 0.025;
    float maskEye = smoothstep(aa, -aa, dEye);
    float4 cEye = float4(ColorDark.rgb, saturate(ColorDark.a) * maskEye);
    result = blendColors_Helper(cEye, result);

    // 10. Eye Catchlights (White Highlights - Fixed lighting direction top-left)
    float dHighlight = min(
        length(p - float2(-0.23, -0.14)) - 0.008, // Left Eye Highlight
        length(p - float2(0.21, -0.14)) - 0.008   // Right Eye Highlight
    );
    float maskHighlight = smoothstep(aa, -aa, dHighlight);
    float4 cHighlight = float4(ColorWhite.rgb, saturate(ColorWhite.a) * maskHighlight);
    result = blendColors_Helper(cHighlight, result);

    // Final Output Composite
    outColor = result;
}
