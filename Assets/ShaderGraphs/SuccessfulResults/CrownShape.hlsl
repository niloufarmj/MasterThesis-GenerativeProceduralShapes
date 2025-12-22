#ifndef PI
#define PI 3.14159265359
#endif

// Helper: Signed Distance to a Box
float sdBox(float2 p, float2 b) {
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// Helper: Signed Distance to a Circle
float sdCircle(float2 p, float r) {
    return length(p) - r;
}

// Helper: Signed Distance to a generic Triangle (vertices p0, p1, p2)
float sdTriangle(float2 p, float2 p0, float2 p1, float2 p2) {
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

// User Request: A simple crown shape with three pointed tips and small round decorations
void CrownShape_float(float2 UV, float Width, float Height, float TipRatio, float JewelSize, float4 Color, out float4 outColor) {
    // PLAN:
    // 1) Center UVs to (0,0).
    // 2) Define geometric points for base, tips, and jewels based on inputs.
    // 3) Use horizontal symmetry (abs(p.x)) to draw side tips/jewels.
    // 4) Combine shapes using union (min of SDFs).
    // 5) Apply smoothstep for anti-aliasing and output color.

    // 1. Coordinates
    float2 p = UV - 0.5;

    // 2. Parameters & Dimensions
    float halfW = max(Width, 0.01) * 0.5;
    float halfH = max(Height, 0.01) * 0.5;
    float rJewel = max(JewelSize, 0.0);
    
    // Calculate vertical splits
    float tipH = clamp(TipRatio, 0.1, 0.9); // Ratio of height that is tips
    float totalH = 2.0 * halfH;
    float baseH = totalH * (1.0 - tipH);
    
    float yBottom = -halfH;
    float yBaseTop = yBottom + baseH;
    float yTipApex = halfH;
    
    // 3. Base Shape (Rectangular Band)
    // Centered at (0, yMidOfBase)
    float2 baseCenter = float2(0.0, yBottom + baseH * 0.5);
    float2 baseSize = float2(halfW, baseH * 0.5);
    float dBase = sdBox(p - baseCenter, baseSize);

    // 4. Tips Setup
    // We use symmetry to handle the side tips.
    // Center tip is at x=0. Side tips are at +/- offset.
    // Divide width into 3 sections for the bases of the tips.
    float xSplit = halfW * 0.333;
    float xEnd = halfW;
    
    // 5. Center Tip (Triangle)
    // Vertices: (-xSplit, yBaseTop), (xSplit, yBaseTop), (0, yTipApex)
    float dCenterTip = sdTriangle(p, float2(-xSplit, yBaseTop), float2(xSplit, yBaseTop), float2(0.0, yTipApex));

    // 6. Side Tips (Symmetry)
    float2 pSym = float2(abs(p.x), p.y);
    // Side tip apex is slightly lower for style (85% of tip height relative to base)
    float ySideApex = yBaseTop + (yTipApex - yBaseTop) * 0.85;
    float xSideApex = (xSplit + xEnd) * 0.5;
    
    // Vertices: (xSplit, yBaseTop), (xEnd, yBaseTop), (xSideApex, ySideApex)
    float dSideTip = sdTriangle(pSym, float2(xSplit, yBaseTop), float2(xEnd, yBaseTop), float2(xSideApex, ySideApex));

    // 7. Jewels (Circles at apexes)
    float dCenterJewel = sdCircle(p - float2(0.0, yTipApex), rJewel);
    float dSideJewel = sdCircle(pSym - float2(xSideApex, ySideApex), rJewel);

    // 8. Union All Shapes
    float d = dBase;
    d = min(d, dCenterTip);
    d = min(d, dSideTip);
    d = min(d, dCenterJewel);
    d = min(d, dSideJewel);

    // 9. Anti-aliasing and Color Output
    float edge = smoothstep(0.005, -0.005, d);
    outColor = float4(Color.rgb * edge, Color.a * edge);
}