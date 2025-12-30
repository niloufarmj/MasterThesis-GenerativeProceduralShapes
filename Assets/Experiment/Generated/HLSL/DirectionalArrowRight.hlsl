#ifndef PI
#define PI 3.14159265359
#endif

// Signed distance to axis-aligned box centered at origin with half-extents b
float sdBox(float2 p, float2 b)
{
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// CSG operations for SDFs
float opUnion(float d1, float d2)
{
    return min(d1, d2);
}

// Directional arrow pointing to the right with adjustable shaft length, thickness, and head size
void FunctionName_float(
    float2 UV,
    float ShaftLength,
    float ShaftThickness,
    float ArrowHeadSize,
    float4 Color,
    out float4 outColor)
{
    // PLAN:
    // 1) Center UV to [-0.5,0.5] space around (0.5,0.5).
    // 2) Build a rectangular shaft SDF aligned horizontally.
    // 3) Build a right-pointing triangular arrowhead from 3 line SDFs.
    // 4) Union shaft and head SDFs to form final arrow.
    // 5) Use smoothstep for anti-aliasing and output single fill color.
    // USER REQUEST: A directional arrow pointing to the right. The shaft length, shaft thickness, and arrowhead size should be adjustable. The arrow should stay centered and readable at different sizes. Single fill color.

    // 1) Center UV around (0.5,0.5)
    float2 p = UV - 0.5;

    // Clamp parameters to sane ranges relative to UV space
    float shaftLen = clamp(ShaftLength, 0.05, 0.9);
    float shaftThick = clamp(ShaftThickness, 0.01, 0.5);
    float headSize = clamp(ArrowHeadSize, 0.05, 0.9);

    // Normalize so that total arrow width does not exceed the canvas
    float maxTotal = 0.9; // keep some margin
    float totalRequested = shaftLen + headSize;
    if (totalRequested > maxTotal)
    {
        float scale = maxTotal / totalRequested;
        shaftLen *= scale;
        headSize *= scale;
    }

    // 2) Shaft SDF (axis-aligned box)
    // Shaft centered horizontally so that combined arrow stays visually centered.
    // Place shaft so that its right end meets the left edge of the head base.
    float shaftHalfLen = shaftLen * 0.5;
    float headBaseX = headSize * 0.5;      // base of triangle at x = headBaseX
    float shaftCenterX = headBaseX - shaftLen; // so right end at base, shaft extends left
    float2 shaftCenter = float2(shaftCenterX, 0.0);
    float2 shaftP = p - shaftCenter;
    float2 shaftHalfExtents = float2(shaftHalfLen, shaftThick * 0.5);
    float dShaft = sdBox(shaftP, shaftHalfExtents);

    // 3) Right-pointing triangular head SDF via three half-planes
    // Triangle vertices (in centered space):
    //   v0: base bottom, v1: base top, v2: tip
    float halfHeadHeight = shaftThick * 0.5 + headSize * 0.25; // a bit taller than shaft for readability
    float2 v0 = float2(headBaseX, -halfHeadHeight);
    float2 v1 = float2(headBaseX,  halfHeadHeight);
    float2 v2 = float2(headBaseX + headSize, 0.0);

    // Compute signed distance to triangle using intersection of three half-spaces
    // Based on Inigo Quilez style: distances to edges and inside test with edge normals.
    float2 e0 = v1 - v0;
    float2 e1 = v2 - v1;
    float2 e2 = v0 - v2;

    float2 n0 = normalize(float2(e0.y, -e0.x)); // outward normals for CCW order v0->v1->v2
    float2 n1 = normalize(float2(e1.y, -e1.x));
    float2 n2 = normalize(float2(e2.y, -e2.x));

    float d0 = dot(p - v0, n0);
    float d1 = dot(p - v1, n1);
    float d2 = dot(p - v2, n2);

    float outside = max(max(d0, d1), d2);

    // Distance to each edge segment
    float2 pa0 = p - v0;
    float2 ba0 = e0;
    float h0 = saturate(dot(pa0, ba0) / max(dot(ba0, ba0), 1e-8));
    float dist0 = length(pa0 - ba0 * h0);

    float2 pa1 = p - v1;
    float2 ba1 = e1;
    float h1 = saturate(dot(pa1, ba1) / max(dot(ba1, ba1), 1e-8));
    float dist1 = length(pa1 - ba1 * h1);

    float2 pa2 = p - v2;
    float2 ba2 = e2;
    float h2 = saturate(dot(pa2, ba2) / max(dot(ba2, ba2), 1e-8));
    float dist2 = length(pa2 - ba2 * h2);

    float unsignedTri = min(dist0, min(dist1, dist2));
    float dHead = (outside <= 0.0) ? -unsignedTri : unsignedTri;

    // 4) Union of shaft and head
    float dArrow = opUnion(dShaft, dHead);

    // 5) Anti-aliasing and output
    float edge = smoothstep(0.01, -0.01, dArrow);
    float alpha = edge;
    float3 rgb = Color.rgb * edge;
    outColor = float4(rgb, alpha);
}
