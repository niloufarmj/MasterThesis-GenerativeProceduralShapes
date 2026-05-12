#ifndef PI
#define PI 3.14159265359
#endif

// Signed distance to a convex polygon defined by vertices
// SDF for a line segment
float sdSegment(float2 p, float2 a, float2 b) {
    float2 pa = p - a;
    float2 ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}

// SDF for a triangle defined by three vertices
float sdTriangle(float2 p, float2 a, float2 b, float2 c) {
    float2 e0 = b - a, e1 = c - b, e2 = a - c;
    float2 v0 = p - a, v1 = p - b, v2 = p - c;
    float2 pq0 = v0 - e0 * clamp(dot(v0, e0) / dot(e0, e0), 0.0, 1.0);
    float2 pq1 = v1 - e1 * clamp(dot(v1, e1) / dot(e1, e1), 0.0, 1.0);
    float2 pq2 = v2 - e2 * clamp(dot(v2, e2) / dot(e2, e2), 0.0, 1.0);
    float s = sign(e0.x * e2.y - e0.y * e2.x);
    float2 d = min(min(
        float2(dot(pq0, pq0), s * (v0.x * e0.y - v0.y * e0.x)),
        float2(dot(pq1, pq1), s * (v1.x * e1.y - v1.y * e1.x))),
        float2(dot(pq2, pq2), s * (v2.x * e2.y - v2.y * e2.x)));
    return -sqrt(d.x) * sign(d.y);
}

void LightningBolt_float(
    float2 UV,
    float Size,
    float BoltWidth,
    float4 FillColor,
    out float4 outColor
) {
    // Center UV
    float2 p = UV - float2(0.5, 0.5);
    // Scale by size
    p /= max(Size, 0.001);

    // Lightning bolt shape:
    // Upper parallelogram-like quad: top-left to midpoint, slanting right-downward
    // Lower parallelogram-like quad: midpoint to bottom, slanting right-downward
    // Classic lightning bolt: top segment goes from upper-right to center-left,
    // lower segment goes from center-left to lower-right
    //
    // Define bolt as two triangular quads (each as two triangles)
    // Upper half: thick band from top area to midpoint, slanting
    // Lower half: thick band from midpoint to bottom, slanting

    float hw = BoltWidth * 0.5;

    // Upper segment vertices (parallelogram as two triangles)
    // Goes from top-right area diagonally down-left to the midpoint
    // Top-right: (0.15, 0.45), upper-left: (-0.05, 0.45)
    // Mid-right: (0.05, 0.0),  mid-left:  (-0.15, 0.0)
    float2 uTR = float2( 0.15,  0.45);
    float2 uTL = float2(-0.05,  0.45);
    float2 uMR = float2( 0.10,  0.02);
    float2 uML = float2(-0.10,  0.02);

    // Lower segment vertices
    // Goes from midpoint diagonally down-left to bottom
    // Mid-right: slightly above mid, Mid-left: slightly above mid
    // Bot-right: (0.05, -0.45), Bot-left: (-0.15, -0.45)
    float2 lTR = float2( 0.10, -0.02);
    float2 lTL = float2(-0.10, -0.02);
    float2 lBR = float2( 0.15, -0.45);
    float2 lBL = float2(-0.05, -0.45);

    // Compute SDF for upper quad (two triangles, take union)
    float dU1 = sdTriangle(p, uTL, uTR, uMR);
    float dU2 = sdTriangle(p, uTL, uMR, uML);
    float dUpper = min(dU1, dU2);

    // Compute SDF for lower quad (two triangles, take union)
    float dL1 = sdTriangle(p, lTL, lTR, lBR);
    float dL2 = sdTriangle(p, lTL, lBR, lBL);
    float dLower = min(dL1, dL2);

    // Union of upper and lower
    float dist = min(dUpper, dLower);

    // Anti-aliasing
    float aa = fwidth(dist);
    aa = max(aa, 0.0001);

    float fillMask = smoothstep(aa, -aa, dist);

    outColor = float4(FillColor.rgb, FillColor.a * fillMask);
}
