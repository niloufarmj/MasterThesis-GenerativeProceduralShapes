#ifndef PI
#define PI 3.14159265359
#endif

// Signed Distance Function for a regular hexagon
// p: Coordinate relative to center
// r: Circumradius (distance from center to vertex)
float sdHexagon(float2 p, float r) {
    const float3 k = float3(-0.866025404, 0.5, 0.577350269);
    p = abs(p);
    p -= 2.0 * min(dot(k.xy, p), 0.0) * k.xy;
    p -= float2(clamp(p.x, -k.z * r, k.z * r), r);
    return length(p) * sign(p.y);
}

void HexagonShape_float(float2 UV, float Size, float Rotation, float2 Center, float4 Color, out float4 outColor) {
    // PLAN:
    // 1) Center the UV coordinates using the Center parameter.
    // 2) Apply rotation to the coordinate system.
    // 3) Compute the Hexagon SDF using the transformed coordinates.
    // 4) Calculate a smooth anti-aliased alpha mask.
    // 5) Output the final color combining input Color and the calculated alpha.

    // 1) Center coordinates
    float2 p = UV - Center;

    // 2) Rotate coordinates
    // We rotate the sampling point by -Rotation to rotate the shape by +Rotation
    float c = cos(Rotation);
    float s = sin(Rotation);
    p = float2(c * p.x + s * p.y, -s * p.x + c * p.y);

    // 3) Calculate SDF
    // Size represents the circumradius
    float dist = sdHexagon(p, max(Size, 0.0));

    // 4) Anti-aliasing
    // fwidth provides the width of the pixel in UV space for sharp yet smooth edges
    float aa = fwidth(dist);
    aa = max(aa, 0.0001); // Safety clamp to avoid division by zero

    // Compute mask: 1.0 inside the shape, 0.0 outside
    // SDF is negative inside, positive outside
    float mask = smoothstep(aa, -aa, dist);

    // 5) Output
    // Combine RGB with the mask applied to the alpha channel
    outColor = float4(Color.rgb, Color.a * mask);
}