#ifndef PI
#define PI 3.14159265359
#endif

// Simple 2D rotation helper
float2 rotate2D(float2 p, float angle)
{
    float ca = cos(angle);
    float sa = sin(angle);
    return float2(ca * p.x - sa * p.y, sa * p.x + ca * p.y);
}

// Circle SDF: signed distance to a circle of radius r at origin
float sdCircle(float2 p, float r)
{
    return length(p) - r;
}

// Box SDF: axis-aligned box with half extents b
float sdBox(float2 p, float2 b)
{
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// Boolean / CSG helpers
float opUnion(float d1, float d2)
{
    return min(d1, d2);
}

float opIntersection(float d1, float d2)
{
    return max(d1, d2);
}

float opSubtract(float dA, float dB)
{
    return max(dA, -dB);
}

// User request: An eight-pointed star with long sharp spikes, fixed 8 points, adjustable spike length, adjustable rotation, single fill color.
void FunctionName_float(float2 UV, float Size, float SpikeLength, float Rotation, float4 Color, out float4 outColor)
{
    // PLAN:
    // 1) Map UV to centered coordinates around (0.5,0.5) and uniform-scale by Size.
    // 2) Build a base circle SDF for the inner core of the star.
    // 3) Build one thin rectangular spike aligned with +X and extend it by SpikeLength.
    // 4) Replicate that spike 8 times using angular sectors by rotating the sample point.
    // 5) Combine core and spikes via union to form the 8-point star.
    // 6) Apply an overall rotation using Rotation (in radians).
    // 7) Use smoothstep for anti-aliased edge and output single fill color with alpha.

    // Center UV around (0.5, 0.5)
    float2 centered = UV - float2(0.5, 0.5);

    // Apply overall scaling: Size controls visual size, 0.5 ≈ half-screen
    float safeSize = max(Size, 1e-4);
    centered /= safeSize;

    // Apply overall rotation (shape appears rotated by +Rotation)
    centered = rotate2D(centered, Rotation);

    // Inner core radius of the star (kept within reasonable range)
    float coreRadius = 0.25;

    // Clamp spike length to avoid extreme artifacts
    float clampedSpike = clamp(SpikeLength, 0.0, 1.0);

    // Core circle SDF (negative inside)
    float dCore = sdCircle(centered, coreRadius);

    // Prepare for 8-way angular repetition by working in polar space
    float r = length(centered);
    float angle = atan2(centered.y, centered.x); // range [-PI, PI]

    // Fold angle into one 8th (PI/4) wedge so we only model a single spike
    float wedge = PI * 0.25; // 45 degrees
    float aFold = fmod(angle + wedge * 0.5, wedge) - wedge * 0.5;

    // Convert back to Cartesian for the folded wedge
    float ca = cos(aFold);
    float sa = sin(aFold);
    float2 pFold = float2(ca, sa) * r;

    // Build a single spike as a thin box along +X from the core edge outward
    // Spike half-length and half-width
    float spikeHalfLen = clampedSpike * 0.6; // controls how long the spike goes beyond the core
    float spikeHalfWidth = coreRadius * 0.15; // thin spike

    // Shift so box center starts just outside the core
    float spikeOffset = coreRadius + spikeHalfLen;
    float2 pSpike = pFold - float2(spikeOffset, 0.0);

    // Box SDF for the spike
    float dSpike = sdBox(pSpike, float2(spikeHalfLen, spikeHalfWidth));

    // Union of core and replicated spikes (via angular folding)
    float dStar = opUnion(dCore, dSpike);

    // Anti-aliased edge using smoothstep on SDF
    float edge = smoothstep(0.01, -0.01, dStar);

    // Final output: single fill color with star-shaped alpha mask
    outColor = float4(Color.rgb * edge, edge);
}
