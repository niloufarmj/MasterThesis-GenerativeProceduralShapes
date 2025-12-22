#ifndef PI
#define PI 3.14159265359
#endif

// --- Helper Functions ---

// Signed Distance to a Box
// p: Point, b: Half-extents
float sdBox(float2 p, float2 b) {
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// Signed Distance to a Triangle defined by 3 points
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

// --- Main Function ---
// PLAN:
// 1) Center and scale UV coordinates using Size.
// 2) Define geometry for Trunk (Box) and 3 Tree Layers (Triangles).
// 3) Compute SDFs for all parts.
// 4) Combine tree layers using min() for union.
// 5) Calculate analytic anti-aliasing masks.
// 6) Blend Trunk and Tree colors (Tree on top of Trunk).
// 7) Output final composited color with straight alpha.

void ChristmasTreeShape_float(float2 UV, float Size, float4 TreeColor, float4 TrunkColor, out float4 outColor) {
    // 1) Setup Coordinates
    // Map UV (0..1) to centered coords (-1..1 approx), scaled by Size
    float2 p = (UV - 0.5) * 2.0;
    p /= max(Size, 0.001);

    // 2) Define Shapes
    // Trunk: A vertical box at the bottom
    // Positioned slightly below center
    float2 trunkPos = p - float2(0.0, -0.5);
    float2 trunkSize = float2(0.08, 0.2); // Half-extents
    float dTrunk = sdBox(trunkPos, trunkSize);

    // Tree Layers: 3 Triangles stacked vertically
    // Vertices defined relative to p origin
    
    // Bottom Layer (Widest)
    float2 t1_p0 = float2(-0.45, -0.4); // Bottom Left
    float2 t1_p1 = float2( 0.45, -0.4); // Bottom Right
    float2 t1_p2 = float2( 0.0,   0.0); // Top Center
    float dL1 = sdTriangle(p, t1_p0, t1_p1, t1_p2);

    // Middle Layer
    float2 t2_p0 = float2(-0.35, -0.15); // Base slightly overlaps bottom layer
    float2 t2_p1 = float2( 0.35, -0.15);
    float2 t2_p2 = float2( 0.0,   0.35);
    float dL2 = sdTriangle(p, t2_p0, t2_p1, t2_p2);

    // Top Layer (Smallest)
    float2 t3_p0 = float2(-0.25,  0.2);
    float2 t3_p1 = float2( 0.25,  0.2);
    float2 t3_p2 = float2( 0.0,   0.7);
    float dL3 = sdTriangle(p, t3_p0, t3_p1, t3_p2);

    // Union of all tree layers (min distance)
    float dTree = min(dL1, min(dL2, dL3));

    // 3) Anti-Aliasing
    // Calculate width of transition based on screen-space derivatives
    float aa = fwidth(p.y);
    aa = max(aa, 0.001); // Safety clamp

    // 4) Compute Masks
    float maskTrunk = 1.0 - smoothstep(-aa, aa, dTrunk);
    float maskTree = 1.0 - smoothstep(-aa, aa, dTree);

    // 5) Composite Colors
    // We want the Tree to appear ON TOP of the Trunk.
    // Standard Over Operator: Out = Src + Dst * (1 - SrcAlpha)
    
    float alphaTree = maskTree * TreeColor.a;
    float alphaTrunk = maskTrunk * TrunkColor.a;

    // Compute final alpha
    float outAlpha = alphaTree + alphaTrunk * (1.0 - alphaTree);

    // Compute weighted RGB (premultiplied logic mostly, but we output straight RGB for shader graph)
    // To get straight RGB, we mix weighted colors then divide by total alpha.
    float3 rgbTree = TreeColor.rgb * alphaTree;
    float3 rgbTrunk = TrunkColor.rgb * alphaTrunk;
    
    float3 outRGB = rgbTree + rgbTrunk * (1.0 - alphaTree);
    
    // Normalize RGB by alpha to avoid double darkening if the pipeline handles blending
    // If alpha is near zero, keep RGB black or neutral
    if (outAlpha > 0.0001) {
        outRGB /= outAlpha;
    }

    outColor = float4(outRGB, outAlpha);
}