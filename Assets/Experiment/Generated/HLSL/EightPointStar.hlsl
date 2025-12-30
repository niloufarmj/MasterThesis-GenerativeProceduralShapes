#ifndef PI
#define PI 3.14159265359
#endif

// Simple 2D rotation helper
float2 rotate2D(float2 p, float angle)
{
    float c = cos(angle);
    float s = sin(angle);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

// Circle SDF using center at origin
float sdCircle(float2 p, float radius)
{
    return length(p) - radius;
}

// Axis-aligned box SDF centered at origin
float sdBox(float2 p, float2 halfSize)
{
    float2 d = abs(p) - halfSize;
    float2 dMax = float2(max(d.x, 0.0), max(d.y, 0.0));
    float outsideDist = length(dMax);
    float insideDist = min(max(d.x, d.y), 0.0);
    return outsideDist + insideDist;
}

// CSG helpers
float opUnion(float d1, float d2)
{
    return min(d1, d2);
}

float opIntersection(float d1, float d2)
{
    return max(d1, d2);
}

float opSubtract(float d1, float d2)
{
    return max(d1, -d2);
}

// MAIN
// User request: An eight-pointed star with long sharp spikes. Fixed 8 points, adjustable spike length, adjustable rotation, single fill color.
void FunctionName_float(float2 UV, float Size, float SpikeLength, float Rotation, float4 Color, out float4 outColor)
{
    // PLAN:
    // 1) Remap UV to centered coords around (0.5, 0.5) and scale by Size.
    // 2) Build a circular core using a circle SDF.
    // 3) Build four axis-aligned spikes with box SDFs (up, down, left, right).
    // 4) Build four diagonal spikes by rotating the box shape by 45 degrees steps.
    // 5) Union all spikes with the core to form an eight-pointed star.
    // 6) Apply global rotation to the sampling position.
    // 7) Use smoothstep for anti-aliasing and output single fill color.

    // 1) Center UV and apply overall size scaling
    float2 centered = UV - float2(0.5, 0.5);
    float safeSize = max(Size, 0.0001);
    float2 p = centered / safeSize;

    // 2) Apply global rotation (star rotation)
    p = rotate2D(p, Rotation);

    // Core radius of the star in this normalized space
    float coreRadius = 0.25;

    // 3) Base spike parameters
    float baseSpikeLen = SpikeLength;
    // Clamp spike length to a reasonable range in local units
    baseSpikeLen = clamp(baseSpikeLen, 0.0, 1.5);

    // Main spike thickness (in local units)
    float spikeThickness = 0.15;

    // Core circle SDF
    float dCore = sdCircle(p, coreRadius);

    // Helper to create a single spike along +X axis, then we rotate it to desired direction
    // Spike extends from coreRadius to coreRadius + baseSpikeLen
    float spikeInner = coreRadius;
    float spikeOuter = coreRadius + baseSpikeLen;
    float spikeHalfWidth = spikeThickness * 0.5;

    // Define a reference rectangle for a spike along +X
    // Center of box along X is midway between inner and outer radius
    float spikeCenterX = (spikeInner + spikeOuter) * 0.5;
    float spikeHalfLength = (spikeOuter - spikeInner) * 0.5;
    float2 spikeHalfSize = float2(spikeHalfLength, spikeHalfWidth);

    // Function body-local lambda not allowed in HLSL, so we inline the logic for each spike:

    // Axis-aligned spikes (0, 90, 180, 270 degrees)
    float dSpike0; // +X
    {
        float2 pp = p - float2(spikeCenterX, 0.0);
        dSpike0 = sdBox(pp, spikeHalfSize);
    }

    float dSpike180; // -X
    {
        float2 pp = p - float2(-spikeCenterX, 0.0);
        dSpike180 = sdBox(pp, spikeHalfSize);
    }

    float dSpike90; // +Y
    {
        float2 pr = float2(-p.y, p.x); // rotate p by +90 degrees
        float2 pp = pr - float2(spikeCenterX, 0.0);
        dSpike90 = sdBox(pp, spikeHalfSize);
    }

    float dSpike270; // -Y
    {
        float2 pr = float2(p.y, -p.x); // rotate p by -90 degrees
        float2 pp = pr - float2(spikeCenterX, 0.0);
        dSpike270 = sdBox(pp, spikeHalfSize);
    }

    // Diagonal spikes at 45, 135, 225, 315 degrees
    float angle45 = PI * 0.25;
    float angle135 = PI * 0.75;
    float angle225 = PI * 1.25;
    float angle315 = PI * 1.75;

    float dSpike45;
    {
        float2 pr = rotate2D(p, -angle45); // rotate sampling so spike template aligns with +X
        float2 pp = pr - float2(spikeCenterX, 0.0);
        dSpike45 = sdBox(pp, spikeHalfSize);
    }

    float dSpike135;
    {
        float2 pr = rotate2D(p, -angle135);
        float2 pp = pr - float2(spikeCenterX, 0.0);
        dSpike135 = sdBox(pp, spikeHalfSize);
    }

    float dSpike225;
    {
        float2 pr = rotate2D(p, -angle225);
        float2 pp = pr - float2(spikeCenterX, 0.0);
        dSpike225 = sdBox(pp, spikeHalfSize);
    }

    float dSpike315;
    {
        float2 pr = rotate2D(p, -angle315);
        float2 pp = pr - float2(spikeCenterX, 0.0);
        dSpike315 = sdBox(pp, spikeHalfSize);
    }

    // 5) Union all spikes with the core to get the eight-pointed star SDF
    float dStar = dCore;
    dStar = opUnion(dStar, dSpike0);
    dStar = opUnion(dStar, dSpike90);
    dStar = opUnion(dStar, dSpike180);
    dStar = opUnion(dStar, dSpike270);
    dStar = opUnion(dStar, dSpike45);
    dStar = opUnion(dStar, dSpike135);
    dStar = opUnion(dStar, dSpike225);
    dStar = opUnion(dStar, dSpike315);

    // 6) Anti-aliased edge using a fixed AA width in local space
    float edge = smoothstep(0.01, -0.01, dStar);

    // 7) Output final color with single fill and alpha from mask
    outColor = float4(Color.rgb * edge, edge);
}
