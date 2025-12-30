#ifndef PI
#define PI 3.14159265359
#endif

// Basic box SDF centered at origin with half extents b
float sdBox(float2 p, float2 b)
{
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// Union of two SDFs
float opUnion(float d1, float d2)
{
    return min(d1, d2);
}

void FunctionName_float(
    float2 UV,
    float ShaftLength,
    float ShaftThickness,
    float ArrowHeadSize,
    float4 Color,
    out float4 outColor)
{
    // User request: A directional arrow pointing to the right with adjustable shaft length, shaft thickness, and arrowhead size.
    // PLAN:
    // 1) Map UV to local coordinates centered at (0.5,0.5) in -1..1 space.
    // 2) Build a horizontal shaft as a box SDF using ShaftLength and ShaftThickness.
    // 3) Build a right-pointing triangular arrowhead using three half-space SDFs controlled by ArrowHeadSize.
    // 4) Combine shaft and head with union to form the full arrow SDF.
    // 5) Apply smoothstep-based anti-aliasing and output a single fill color with alpha.

    // 1) Center UV and scale to -1..1 for stable sizing
    float2 centered = UV - 0.5;
    float2 p = centered * 2.0;

    // Clamp and normalize parameters to reasonable ranges
    float shaftLen = clamp(ShaftLength, 0.05, 1.0);        // in -1..1 space
    float shaftThick = clamp(ShaftThickness, 0.02, 1.0);   // full thickness in -1..1
    float headSize = clamp(ArrowHeadSize, 0.05, 1.0);      // length of head base→tip in -1..1

    // 2) Shaft SDF (horizontal box)
    // Shaft extends from left toward the head; keep arrow roughly centered overall.
    // Place the head tip slightly to the right of center and let shaft extend left.
    float tipX = 0.4; // tip position in -1..1 space
    float shaftHalfLength = shaftLen * 0.5;
    float shaftCenterX = tipX - headSize - shaftHalfLength; // center shaft so its right end meets head base
    float2 shaftCenter = float2(shaftCenterX, 0.0);
    float2 shaftHalfSize = float2(shaftHalfLength, shaftThick * 0.5);
    float2 pShaft = p - shaftCenter;
    float dShaft = sdBox(pShaft, shaftHalfSize);

    // 3) Arrow head SDF (right-pointing isosceles triangle built from half-spaces)
    // Define triangle with base vertical line and tip to the right.
    // Base center aligned with shaft right end at x = tipX - headSize.
    float baseX = tipX - headSize;
    float halfHeadHeight = headSize * 0.5; // aspect ratio ~1:1; tweakable if needed

    // Three vertices in local head space (for explanation):
    // V0 (base bottom) = (baseX, -halfHeadHeight)
    // V1 (base top)    = (baseX, +halfHeadHeight)
    // V2 (tip)         = (tipX, 0)
    // We'll use their edge lines as half-spaces with outward normals.

    // Work directly in global p-space.
    float2 V0 = float2(baseX, -halfHeadHeight);
    float2 V1 = float2(baseX,  halfHeadHeight);
    float2 V2 = float2(tipX,   0.0);

    // Edges (CCW: V0→V1→V2)
    float2 e0 = V1 - V0; // base (vertical)
    float2 e1 = V2 - V1; // top-right slant
    float2 e2 = V0 - V2; // bottom-left slant

    // Normals pointing OUT of the triangle (right-hand perp for CCW polygon)
    float2 n0 = normalize(float2(e0.y, -e0.x));
    float2 n1 = normalize(float2(e1.y, -e1.x));
    float2 n2 = normalize(float2(e2.y, -e2.x));

    // Signed distances to each supporting line (positive = outside)
    float d0 = dot(p - V0, n0);
    float d1 = dot(p - V1, n1);
    float d2 = dot(p - V2, n2);

    // Max of outside distances for a convex polygon gives an SDF-like value
    float dHead = max(d0, max(d1, d2));

    // 4) Combine shaft and head (union)
    float dArrow = opUnion(dShaft, dHead);

    // 5) Anti-aliasing and color output
    // Use a fixed AA width in -1..1 space
    float aa = 0.01;
    float edge = smoothstep(aa, -aa, dArrow);

    float alpha = edge;
    outColor = float4(Color.rgb * alpha, alpha);
}
