// User Request: Cartoon play icon (rounded right-pointing triangle) with 4 diagonal color zones and outline.
// PLAN:
// 1. Define helper SDF for triangle.
// 2. Map UV to centered space, scaled by Size.
// 3. Define triangle vertices based on Width/Height parameters.
// 4. Compute SDF of triangle and subtract Roundness.
// 5. Determine which of the 4 zones (Top/Bot/Left/Right) the pixel falls into.
// 6. Select zone color.
// 7. Compute AA masks for Fill and Outline.
// 8. Composite Outline over Fill and output.

#ifndef PI
#define PI 3.14159265359
#endif

// Helper: Signed Distance to a Triangle
// p: Point, v0,v1,v2: Vertices
float sdTriangle_Internal(float2 p, float2 p0, float2 p1, float2 p2) {
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

void CartoonPlayIcon_float(float2 UV, float Size, float Width, float Height, float Roundness, float OutlineThickness, float4 OutlineColor, float4 ColorTop, float4 ColorBottom, float4 ColorLeft, float4 ColorRight, out float4 outColor) {
    // 1. Setup Coordinates
    float2 center01 = float2(0.5, 0.5);
    float2 p = UV - center01;
    // Scale logic: Size=1 fills roughly 0 to 1 UV space if Width/Height are near 0.5
    p /= max(Size, 0.0001);

    // 2. Define Triangle Geometry (Isosceles pointing Right)
    // w and h are half-extents of the bounding box roughly
    float w = max(Width, 0.01) * 0.5;
    float h = max(Height, 0.01) * 0.5;

    // Vertices relative to center (0,0)
    // Tip is at +x, Base is at -x
    float2 vTip = float2(w, 0.0);
    float2 vTopBack = float2(-w, h);
    float2 vBotBack = float2(-w, -h);

    // 3. Compute SDF
    float dTri = sdTriangle_Internal(p, vTip, vTopBack, vBotBack);
    float dShape = dTri - Roundness;

    // 4. Zone Logic (Diagonal Split)
    // Normalize p relative to aspect ratio to get clean 45-degree splits logic in UV space
    // Adding epsilon to avoid division by zero
    float2 pNorm = p / float2(w + 0.0001, h + 0.0001);
    
    // Check 4 quadrants defined by diagonals
    // Right: x > |y|
    // Left:  x < -|y|
    // Top:   y > |x|
    // Bottom: y < -|x|
    float absX = abs(pNorm.x);
    float absY = abs(pNorm.y);
    
    // Use step for sharp transitions between zones
    float isRight = step(absY, pNorm.x);
    float isLeft  = step(absY, -pNorm.x);
    float isTop   = step(absX, pNorm.y);
    float isBot   = step(absX, -pNorm.y);

    // Composite Zone Color (Priority: Top/Bot override Left/Right at exact diagonals, but logic handles unique areas)
    float4 zoneColor = ColorRight * isRight +
                       ColorLeft * isLeft +
                       ColorTop * isTop +
                       ColorBottom * isBot;
                       
    // Fallback normalization if overlap (though geometrically they barely overlap)
    float sum = isRight + isLeft + isTop + isBot;
    if (sum > 0.5) zoneColor /= sum;
    else zoneColor = ColorRight; // Fallback inside center or errors

    // 5. Anti-Aliasing and Masking
    float aa = fwidth(dShape);
    float softAA = length(float2(ddx(dShape), ddy(dShape))) * 0.707;
    aa = max(aa, 0.001);

    // Fill Mask (Inner shape)
    float fillMask = 1.0 - smoothstep(0.0, aa, dShape);
    
    // Stroke Mask (Centered on edge)
    float halfStroke = max(OutlineThickness, 0.0) * 0.5;
    float dStroke = abs(dShape) - halfStroke;
    float strokeMask = 1.0 - smoothstep(0.0, aa, dStroke);

    // 6. Composition (Stroke Over Fill)
    // Pre-multiply alpha for correct blending
    float4 src = float4(OutlineColor.rgb * OutlineColor.a, OutlineColor.a) * strokeMask;
    float4 dst = float4(zoneColor.rgb * zoneColor.a, zoneColor.a) * fillMask;
    
    // Standard Over Operator: Src + Dst * (1 - Src.a)
    float4 result = src + dst * (1.0 - src.a);
    
    outColor = result;
}