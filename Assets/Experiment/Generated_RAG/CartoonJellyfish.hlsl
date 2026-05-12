#ifndef PI
#define PI 3.14159265359
#endif

// Smooth minimum (union with smooth blending)
float smin(float a, float b, float k)
{
    float h = clamp(0.5 + 0.5*(b-a)/k, 0.0, 1.0);
    return lerp(b, a, h) - k*h*(1.0-h);
}

// Approximate ellipse SDF
float sdEllipse(float2 p, float2 ab)
{
    float a = max(ab.x, 1e-6);
    float b = max(ab.y, 1e-6);
    float F = (p.x*p.x)/(a*a) + (p.y*p.y)/(b*b) - 1.0;
    float gx = 2.0*p.x/(a*a);
    float gy = 2.0*p.y/(b*b);
    float gl = sqrt(gx*gx + gy*gy);
    return (gl > 1e-8) ? F/gl : -min(a,b);
}

// Circle SDF
float sdCircle(float2 p, float r)
{
    return length(p) - r;
}

// Segment SDF
float sdSegment(float2 p, float2 a, float2 b)
{
    float2 pa = p - a;
    float2 ba = b - a;
    float h = clamp(dot(pa,ba)/dot(ba,ba), 0.0, 1.0);
    return length(pa - ba*h);
}

// Porter-Duff Over composite
float4 compOver(float4 src, float4 dst)
{
    float a = src.a + dst.a*(1.0 - src.a);
    float3 c = (src.rgb*src.a + dst.rgb*dst.a*(1.0-src.a)) / max(a, 1e-8);
    return float4(c, a);
}

void CartoonJellyfish_float(
    float2 UV,
    float2 Center,
    float BellWidth,
    float BellHeight,
    float4 BellColor,
    float FrillCount,
    float FrillDepth,
    float TentacleCount,
    float TentacleLength,
    float TentacleThickness,
    float TentacleAmplitude,
    float4 TentacleColor,
    float GlowIntensity,
    float4 GlowColor,
    float OutlineThickness,
    float4 OutlineColor,
    out float4 outColor
)
{
    // Setup: center at (0,0)
    float2 p = UV - Center;

    float hw = max(BellWidth * 0.5, 0.01);
    float hh = max(BellHeight * 0.5, 0.01);

    // -------------------------------------------------------
    // 1) BELL BODY: upper half-ellipse dome
    // The dome is centered so its flat bottom is at y = -hh*0.15
    // (slightly below center so the bell looks like a dome)
    // We use a full ellipse SDF but mask off the lower half
    float2 bellCenter = float2(0.0, hh * 0.2);
    float2 pBell = p - bellCenter;
    float dEllipse = sdEllipse(pBell, float2(hw, hh));

    // Flat cut at the bottom of the dome (y = bellCenter.y - hh*0.35)
    float cutY = -hh * 0.35;
    float dCut = pBell.y - cutY;  // positive above cut line
    // Bell SDF = ellipse but only above the cut
    float dBell = max(dEllipse, -dCut);

    // -------------------------------------------------------
    // 2) FRILL / WAVY SKIRT at the bottom edge of the bell
    // Build a wavy strip near the bottom edge of the dome
    float frillCount = max(2.0, FrillCount);
    float frillAmp = max(0.0, FrillDepth);

    // Frill strip: a thin band at the bottom of the bell
    float frillY = bellCenter.y + cutY;  // world-space Y of the cut
    float2 pFrill = p - float2(0.0, frillY);

    // Horizontal wave along x
    float wave = sin(pFrill.x / hw * PI * frillCount) * frillAmp;
    float frillStripH = hh * 0.12 + frillAmp;
    // SDF of wavy strip: a rectangle warped by a wave
    float frillTop = -pFrill.y + wave;
    float frillBot = pFrill.y + frillStripH;
    float dFrillStrip = max(frillTop, frillBot);
    // Clip to bell width
    float dFrillClip = abs(p.x) - hw * 0.98;
    float dFrill = max(dFrillStrip, dFrillClip);

    // Union bell + frill
    float dBody = smin(dBell, dFrill, 0.01);

    // -------------------------------------------------------
    // 3) TENTACLES: flowing sine-wave strands below the bell
    float tCount = clamp(floor(TentacleCount), 1.0, 8.0);
    float tLen = max(0.01, TentacleLength);
    float tThick = max(0.001, TentacleThickness * 0.5);
    float tAmp = max(0.0, TentacleAmplitude);

    float dTentacles = 1e9;
    float tentacleStartY = frillY - frillStripH * 0.5;

    for (float i = 0.0; i < 8.0; i++)
    {
        if (i >= tCount) break;

        // Evenly space tentacles across bell width
        float t = (tCount > 1.0) ? (i / (tCount - 1.0)) : 0.5;
        float tx = lerp(-hw * 0.75, hw * 0.75, t);

        // Phase offset per tentacle for variety
        float phase = i * 1.3;

        // For each tentacle, compute distance by marching along Y
        // We sample the sine wave as a curved path
        float2 pT = p - float2(tx, tentacleStartY);

        // Approximate distance to a sine curve: distort x by wave
        // at each y, the curve is at x = sin(y*freq + phase)*amp
        float freq = 4.0 * PI;
        float distortedX = pT.x - sin(-pT.y * freq + phase) * tAmp;
        // The tentacle goes from y=0 to y=-tLen (downward)
        float clampedY = clamp(pT.y, -tLen, 0.0);
        float dTentSeg = length(float2(distortedX, pT.y - clampedY)) - tThick;
        dTentacles = min(dTentacles, dTentSeg);
    }

    // -------------------------------------------------------
    // 4) BIOLUMINESCENT SPOTS on the bell
    // Scatter spots using a polar-repeat pattern
    float spotSDF = 1e9;

    // Radial rings of spots
    // Ring 1: ~3 spots at radius 0.35*hw
    // Ring 2: ~5 spots at radius 0.65*hw
    float spotRings[2];
    spotRings[0] = 0.35;
    spotRings[1] = 0.65;
    float spotCounts[2];
    spotCounts[0] = 3.0;
    spotCounts[1] = 5.0;

    for (int ri = 0; ri < 2; ri++)
    {
        float ringR = spotRings[ri] * hw;
        float sCount = spotCounts[ri];
        float spotRadius = hw * 0.055;

        for (float si = 0.0; si < 8.0; si++)
        {
            if (si >= sCount) break;
            float angle = (si / sCount) * 2.0 * PI + float(ri) * 0.5;
            float2 spotPos = float2(cos(angle)*ringR, sin(angle)*ringR*0.6 + bellCenter.y + hh*0.1);
            float dSpot = sdCircle(p - spotPos, spotRadius);
            spotSDF = min(spotSDF, dSpot);
        }
    }

    // Only show spots inside the bell
    float dSpotsMasked = max(spotSDF, dBell);

    // -------------------------------------------------------
    // 5) RADIAL GLOW on bell surface
    // Gradient: bright at center-top, dimmer outward
    float2 pGlow = p - (bellCenter + float2(0.0, hh*0.1));
    float glowDist = length(pGlow / float2(hw*0.8, hh*0.8));
    float glowMask = 1.0 - smoothstep(0.0, 1.0, glowDist);
    // Only inside bell
    float bellMask = 1.0 - smoothstep(0.0, 0.005, dBell);
    float glowFactor = glowMask * bellMask * GlowIntensity;

    // -------------------------------------------------------
    // 6) RENDERING with AA
    float aa = max(fwidth(dBody), 0.001);
    float aaTent = max(fwidth(dTentacles), 0.001);
    float aaSpot = max(fwidth(dSpotsMasked), 0.001);

    // Tentacles (rendered first, behind bell)
    float tentAlpha = (1.0 - smoothstep(0.0, aaTent, dTentacles)) * TentacleColor.a;
    float4 tentLayer = float4(TentacleColor.rgb, tentAlpha);

    // Bell fill
    float fillAlpha = (1.0 - smoothstep(0.0, aa, dBody)) * BellColor.a;
    float4 bellFill = float4(BellColor.rgb, fillAlpha);

    // Glow overlay on bell
    float4 glowLayer = float4(GlowColor.rgb, glowFactor * GlowColor.a * bellMask);

    // Spots
    float spotAlpha = (1.0 - smoothstep(0.0, aaSpot, dSpotsMasked)) * GlowColor.a;
    float4 spotLayer = float4(GlowColor.rgb, spotAlpha * GlowIntensity);

    // Outline: band around dBody
    float outlineHalf = max(OutlineThickness * 0.5, 0.0);
    float dOutline = abs(dBody) - outlineHalf;
    float outlineAlpha = (1.0 - smoothstep(0.0, aa, dOutline)) * OutlineColor.a;
    float4 outlineLayer = float4(OutlineColor.rgb, outlineAlpha);

    // Composite order: tentacles -> bell fill -> glow -> spots -> outline
    float4 result = float4(0,0,0,0);
    result = compOver(tentLayer, result);
    result = compOver(bellFill, result);
    result = compOver(glowLayer, result);
    result = compOver(spotLayer, result);
    result = compOver(outlineLayer, result);

    outColor = result;
}