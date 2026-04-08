// USER REQUEST: a heart shape with adjustable size, color, and rotation, smooth anti-aliased edges, centered

// PLAN:
// 1) Remap UV to centered coordinates (UV - Center).
// 2) Apply rotation using the provided Angle in radians.
// 3) Scale the coordinates by the inverse of Size, and shift Y to align the heart's visual center.
// 4) Compute the heart SDF using Inigo Quilez's analytical heart formula.
// 5) Scale the resulting distance back by Size to maintain the proper distance field metric.
// 6) Use fwidth and smoothstep for high-quality analytic anti-aliasing.
// 7) Output the final color with the calculated mask.

#ifndef PI
#define PI 3.14159265359
#endif

// Helper: squared length of a vector
inline float nm_dot2(float2 v) {
    return dot(v, v);
}

// Exact signed distance to an origin-aligned heart shape
inline float nm_sdHeart(float2 p) {
    p.x = abs(p.x);
    if (p.y + p.x > 1.0) {
        // Upper lobes of the heart
        return sqrt(nm_dot2(p - float2(0.25, 0.75))) - 0.35355339059; // sqrt(2)/4
    }
    // Bottom tip of the heart
    return sqrt(min(nm_dot2(p - float2(0.00, 1.00)),
                    nm_dot2(p - 0.5 * max(p.x + p.y, 0.0)))) * sign(p.x - p.y);
}

void HeartShape_float(float2 UV, float2 Center, float Size, float Angle, float4 Color, out float4 outColor) {
    // 1) Remap UV to centered coordinates
    float2 p = UV - Center;

    // 2) Rotate sampling point by -Angle (so the shape appears rotated by +Angle)
    float c = cos(Angle);
    float s = sin(Angle);
    float2 pr = float2(c * p.x + s * p.y, -s * p.x + c * p.y);

    // 3) Scale and shift to align the heart center
    // The analytic heart bounds are roughly x in [-1, 1], y in [0, 1]
    // We shift y by 0.5 so its center rests exactly at the origin.
    float safeSize = max(Size, 0.0001);
    float2 scaledP = pr / safeSize;
    scaledP.y += 0.5;

    // 4) Compute SDF
    float d = nm_sdHeart(scaledP);

    // 5) Multiply distance back by Size to keep accurate distance field metric
    d = d * safeSize;

    // 6) Anti-aliasing using analytic width
    float aa = max(fwidth(d), 0.001);
    float mask = 1.0 - smoothstep(0.0, aa, d);

    // 7) Output color with straight alpha pattern
    outColor = float4(Color.rgb * mask, saturate(Color.a) * mask);
}