#ifndef PI
#define PI 3.14159265359
#endif

// Simple 2D rotation
inline float2 rotate2D(float2 p, float angle)
{
    float c = cos(angle);
    float s = sin(angle);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

// Circle SDF: negative inside
inline float sdCircle(float2 p, float radius)
{
    return length(p) - radius;
}

// Box/Rectangle SDF centered at origin with half extents b, negative inside
inline float sdBox(float2 p, float2 b)
{
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// Smooth union of two SDFs
inline float opSmoothUnion(float d1, float d2, float k)
{
    // k is smoothing radius; higher = softer blend
    float h = clamp(0.5 + 0.5 * (d2 - d1) / k, 0.0, 1.0);
    return lerp(d2, d1, h) - k * h * (1.0 - h);
}

// Anti-aliased mask from SDF using standard pattern
inline float aaMask(float dist)
{
    float aa = fwidth(dist);
    return 1.0 - smoothstep(0.0, aa, dist);
}

// PLAN:
// 1) Center UV to p in [-0.5,0.5], optionally scale by overall size.
// 2) Convert p to polar coordinates: radius r, angle a in [0, 2*PI).
// 3) Use angular repetition: fold angle into a single petal sector via modulo.
// 4) Build a petal SDF as a smooth union of:
//    - A box (for main body) aligned with +Y in local petal space.
//    - A circle cap at the petal tip.
// 5) Radially stretch petal using PetalLength and PetalWidth controls.
// 6) Build a center circle SDF with CenterRadius.
// 7) Compute AA masks for petals and center, then combine colors:
//    - Center color overrides where center mask is strongest.
//    - Else petal color, fade by petal mask.
// 8) Output final color with alpha = combined mask.

// Exact user request: A stylized flower with repeated petals, adjustable count/length/width, and separate petal/center colors.
void FunctionName_float(
    float2 UV,
    float PetalCount,
    float PetalLength,
    float PetalWidth,
    float CenterRadius,
    float OverallSize,
    float4 PetalColor,
    float4 CenterColor,
    out float4 outColor)
{
    // Center UV coordinates around (0.5, 0.5) and apply overall scaling
    float2 p = UV - float2(0.5, 0.5);
    float size = max(OverallSize, 1e-3);
    p /= size;

    // Polar coordinates
    float r = length(p);
    float angle = atan2(p.y, p.x); // range [-PI, PI]
    // Map to [0, 2PI)
    if (angle < 0.0) angle += 2.0 * PI;

    // Angular repetition for petals
    float n = max(PetalCount, 1.0); // avoid division by zero
    float sectorAngle = 2.0 * PI / n;

    // Shift so petal is centered in its sector
    float aLocal = fmod(angle + 0.5 * sectorAngle, sectorAngle) - 0.5 * sectorAngle;

    // Local petal space: x from angle, y from radius
    // Scale angular coordinate so width is normalized around PetalWidth
    float angularScale = max(PetalWidth, 1e-3);
    float2 petalP = float2(aLocal / sectorAngle / angularScale, r);

    // Build petal SDF in petal space
    // Petal length control
    float petalLen = max(PetalLength, 1e-3);

    // Shift so petal base near origin and tip at +Y
    petalP.y *= 1.0 / petalLen;

    // Main body: vertical box
    float boxHalfWidth = 0.5;
    float boxHalfHeight = 0.7;
    float2 boxHalfExtents = float2(boxHalfWidth, boxHalfHeight);
    float2 boxP = petalP - float2(0.0, boxHalfHeight);
    float dBox = sdBox(boxP, boxHalfExtents);

    // Tip: circle cap at top
    float capRadius = 0.55;
    float2 capCenter = float2(0.0, boxHalfHeight + (capRadius - 0.1));
    float dCap = sdCircle(petalP - capCenter, capRadius);

    // Smooth union for organic petal
    float smoothK = 0.2;
    float dPetalLocal = opSmoothUnion(dBox, dCap, smoothK);

    // Convert back to world radial SDF approximation
    // Since petalP.y ~ r / PetalLength, reuse dPetalLocal as final petal sdf
    float dPetal = dPetalLocal;

    // Center circle in original p-space
    float centerR = max(CenterRadius, 0.0);
    float dCenter = sdCircle(p, centerR);

    // AA masks
    float petalMask = aaMask(dPetal);
    float centerMask = aaMask(dCenter);

    // Combine masks: center overrides petals
    float combinedCenter = centerMask;
    float combinedPetal = petalMask * (1.0 - combinedCenter);
    float finalMask = saturate(combinedCenter + combinedPetal);

    // Composite colors (simple linear blend based on normalized weights)
    float3 petalRGB = PetalColor.rgb;
    float3 centerRGB = CenterColor.rgb;

    float totalWeight = combinedCenter + combinedPetal + 1e-6;
    float3 finalRGB = (centerRGB * combinedCenter + petalRGB * combinedPetal) / totalWeight;

    // Apply overall alpha from masks and input color alphas
    float petalAlpha = PetalColor.a * combinedPetal;
    float centerAlpha = CenterColor.a * combinedCenter;
    float finalAlpha = saturate(petalAlpha + centerAlpha);

    // If both input alphas are zero, still use coverage as alpha
    finalAlpha = max(finalAlpha, finalMask);

    outColor = float4(finalRGB * finalMask, finalAlpha);
}
