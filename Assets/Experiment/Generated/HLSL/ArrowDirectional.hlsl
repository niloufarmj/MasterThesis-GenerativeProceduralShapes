#ifndef PI
#define PI 3.14159265359
#endif

// Helper: Signed Distance to a Box (for the shaft)
float sdBox_Arrow(float2 p, float2 b) {
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// Helper: Signed Distance to a Triangle (for the head)
// Calculates exact SDF to an arbitrary triangle defined by vertices p0, p1, p2
float sdTriangle_Arrow(float2 p, float2 p0, float2 p1, float2 p2) {
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

// Main Function: Directional Arrow Shape pointing Right
void ArrowDirectional_float(float2 UV, float ShaftLength, float ShaftThickness, float HeadSize, float4 Color, out float4 outColor) {
    // PLAN:
    // 1) Center UV coordinates to [-1, 1] range.
    // 2) Calculate geometry for Shaft (Box) and Head (Triangle) to stay centered.
    // 3) Compute SDFs for both parts.
    // 4) Combine using min() (Union).
    // 5) Apply anti-aliasing and color.

    // 1) Normalize UV to centered space [-1, 1]
    //    This assumes the arrow should fit within a reasonable 0..1 UV bounding box.
    float2 p = (UV - 0.5) * 2.0;

    // Validate inputs to prevent degenerate shapes
    float sLen = max(ShaftLength, 0.001);
    float sThick = max(ShaftThickness, 0.001);
    float hSize = max(HeadSize, 0.001);

    // 2) Geometry Setup
    //    We want the arrow centered. Total width = ShaftLength + HeadSize.
    //    The shape starts at x = -TotalWidth/2 and ends at x = TotalWidth/2.
    float totalWidth = sLen + hSize;
    float startX = -totalWidth * 0.5;
    
    // Shaft Geometry
    //    Center of shaft box is at startX + ShaftLength/2
    float2 shaftCenter = float2(startX + sLen * 0.5, 0.0);
    float2 shaftHalfSize = float2(sLen * 0.5, sThick * 0.5);
    
    // Head Geometry (Triangle)
    //    Base is at startX + ShaftLength. Tip is at startX + TotalWidth (which is totalWidth/2).
    //    We define an isosceles triangle pointing right.
    float headBaseX = startX + sLen;
    float headTipX = startX + totalWidth;
    float headHalfWidth = hSize * 0.5; // Head width proportional to size (1:1 aspect roughly)
    
    float2 v0 = float2(headTipX, 0.0);             // Tip
    float2 v1 = float2(headBaseX, headHalfWidth);  // Top Base
    float2 v2 = float2(headBaseX, -headHalfWidth); // Bottom Base

    // 3) Compute SDFs
    //    Distance to Shaft (Box)
    float dShaft = sdBox_Arrow(p - shaftCenter, shaftHalfSize);
    
    //    Distance to Head (Triangle)
    float dHead = sdTriangle_Arrow(p, v0, v1, v2);
    
    // 4) Combine SDFs (Union)
    float dist = min(dShaft, dHead);
    
    // 5) Anti-aliasing and Output
    float aa = fwidth(dist);
    //    If fwidth is too small (e.g. preview window), fallback to constant
    aa = max(aa, 0.001);
    
    //    Smoothstep for crisp but anti-aliased edges
    float mask = smoothstep(aa, -aa, dist);
    
    //    Final color composition (premultiplied alpha logic)
    outColor = float4(Color.rgb * mask, mask * Color.a);
}