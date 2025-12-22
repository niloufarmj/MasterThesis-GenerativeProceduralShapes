#ifndef PI
#define PI 3.14159265359
#endif

// Helper: Perpendicular vector (right-hand)
float2 hg_perp(float2 e) {
    return float2(e.y, -e.x);
}

// Helper: Distance from point to segment
float hg_segDist(float2 p, float2 a, float2 b) {
    float2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}

// Helper: Signed Distance to Trapezoid (Centered at origin)
// wb: Width at bottom, wt: Width at top, he: Full height
float hg_trapezoid(float2 p, float wb, float wt, float he) {
    float k1 = 0.5 * wt;
    float k2 = 0.5 * wb;
    float kh = 0.5 * he;

    // Define vertices (CCW order starting bottom-right)
    float2 v1 = float2(k2, -kh);
    float2 v2 = float2(k1, kh);
    float2 v3 = float2(-k1, kh);
    float2 v4 = float2(-k2, -kh);

    // Normals for the 4 edges (outward)
    float2 n1 = normalize(hg_perp(v2 - v1)); // Right slope
    float2 n2 = float2(0.0, 1.0);            // Top
    float2 n3 = normalize(hg_perp(v4 - v3)); // Left slope
    float2 n4 = float2(0.0, -1.0);           // Bottom

    // Signed distances to the infinite lines of the edges
    float sd1 = dot(p - v1, n1);
    float sd2 = dot(p - v2, n2);
    float sd3 = dot(p - v3, n3);
    float sd4 = dot(p - v4, n4);

    // Interior check: if inside all half-planes, distance is negative
    float sgn = (max(max(sd1, sd2), max(sd3, sd4)) < 0.0) ? -1.0 : 1.0;

    // Boundary distance: minimum distance to any of the 4 segments
    float dEdge = min(min(hg_segDist(p, v1, v2), hg_segDist(p, v2, v3)),
                      min(hg_segDist(p, v3, v4), hg_segDist(p, v4, v1)));

    return dEdge * sgn;
}

// Main Function: Basic Hourglass Shape
// User request: Adjustable size, and adjustable top/bottom width (waist vs ends).
void HourglassShape_float(float2 UV, float Size, float Height, float EndWidth, float WaistWidth, float4 Color, out float4 outColor) {
    // PLAN:
    // 1. Center UV coordinates at (0.5, 0.5).
    // 2. Apply global Size scaling to dimensions.
    // 3. Fold the Y coordinate (symmetry) to draw the top and bottom identically.
    // 4. Offset the folded coordinate to center the resulting trapezoid.
    // 5. Compute Trapezoid SDF using WaistWidth as bottom and EndWidth as top.
    // 6. Apply smoothstep for anti-aliasing and output final color.

    float2 p = UV - 0.5;

    // Scale dimensions by the global Size parameter
    float hTotal = max(Height, 0.0) * Size;
    float wEnd = max(EndWidth, 0.0) * Size;
    float wWaist = max(WaistWidth, 0.0) * Size;

    // Symmetry: Mirror the bottom half to the top
    // The waist is at y=0, the ends are at y=+/- hTotal/2
    p.y = abs(p.y);

    // We are now rendering a trapezoid from y=0 to y=hTotal/2.
    // The SDF function expects the shape to be centered at the origin.
    // The center of this segment (0 to hTotal/2) is at hTotal/4.
    p.y -= hTotal * 0.25;

    // Calculate SDF
    // The "bottom" of this trapezoid is the waist (originally y=0)
    // The "top" of this trapezoid is the end (originally y=hTotal/2)
    // Height of this trapezoid segment is hTotal/2
    float dist = hg_trapezoid(p, wWaist, wEnd, hTotal * 0.5);

    // Anti-aliased edge
    float edge = smoothstep(0.01, -0.01, dist);

    // Output color (rgb * mask, alpha = mask)
    outColor = float4(Color.rgb * edge, edge);
}