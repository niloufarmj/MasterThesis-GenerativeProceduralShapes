#ifndef PI
#define PI 3.14159265359
#endif

// Signed distance to an axis-aligned box centered at origin with half extents size
float sdBox(float2 p, float2 size)
{
    float2 d = abs(p) - size;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

void FunctionName_float(
    float2 UV,
    float2 AreaSize,
    float Frequency,
    float Amplitude,
    float4 Color,
    out float4 outColor)
{
    // User request: A repeating wave-like shape masked into a fixed area. The wave frequency and amplitude should be adjustable. The pattern should stay centered and clearly visible. Single fill color.

    // PLAN:
    // 1) Center UV to [-0.5,0.5] and limit drawing to a centered box AreaSize using an SDF.
    // 2) Inside that box space, build a horizontal sine-wave band using an analytic SDF.
    // 3) Repeat the wave along X by wrapping phase with Frequency.
    // 4) Combine box SDF and wave SDF via intersection (max).
    // 5) Use smoothstep for anti-aliasing and output Color * mask.

    // 1) Center UV around (0.5,0.5)
    float2 centered = UV - 0.5;

    // Clamp parameters to sensible ranges
    float2 halfArea = 0.5 * float2(clamp(AreaSize.x, 0.05, 1.0), clamp(AreaSize.y, 0.05, 1.0));
    float freq = max(Frequency, 0.1);
    float amp = clamp(Amplitude, 0.0, halfArea.y * 0.9);

    // Box SDF for the fixed drawing area
    float boxDist = sdBox(centered, halfArea);

    // 2) Local coordinates normalized to box size (so wave stays centered in area)
    float2 p = centered / halfArea; // p in roughly [-1,1] inside box

    // 3) Build a horizontal sine wave band SDF.
    // We treat the ideal centerline as y = sin(phase) * ampN in box-normalized space,
    // then approximate distance as vertical distance to this curve.
    float xPhase = p.x * freq * 2.0 * PI; // frequency in box-normalized space

    float waveCenterY = sin(xPhase);

    // Normalized amplitude in box space (amp as fraction of halfArea.y)
    float ampN = amp / max(halfArea.y, 1e-4);

    waveCenterY *= ampN;

    // Band half-thickness (normalized) to keep the wave clearly visible
    float bandHalfThickness = 0.08;

    // Signed distance to horizontal band around the sine curve
    float verticalDist = abs(p.y - waveCenterY) - bandHalfThickness;

    // Convert this normalized distance back to UV units so AA width matches box SDF units
    float waveDist = verticalDist * halfArea.y;

    // 4) Combine: intersection of box and wave (max of distances)
    float shapeDist = max(boxDist, waveDist);

    // 5) Anti-aliasing and color output
    float aa = fwidth(shapeDist);

    // Ensure aa has a fallback if derivatives are unavailable
    aa = max(aa, 0.001);

    float edge = 1.0 - smoothstep(0.0, aa, shapeDist);

    float mask = edge;

    outColor = float4(Color.rgb * mask, mask);
}
