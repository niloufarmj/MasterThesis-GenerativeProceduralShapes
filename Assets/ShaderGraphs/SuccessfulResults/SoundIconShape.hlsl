#ifndef PI
#define PI 3.14159265359
#endif

// --- Helper Functions ---

// Signed distance to an axis-aligned box
float sdBox(float2 p, float2 b) {
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// Signed distance to a line segment (used for polygon)
float sdSegment(float2 p, float2 a, float2 b) {
    float2 pa = p - a, ba = b - a;
    float h = saturate(dot(pa, ba) / dot(ba, ba));
    return length(pa - ba * h);
}

// Signed distance to a convex quadrilateral (used for speaker cone)
float sdConvexPoly4(float2 p, float2 v0, float2 v1, float2 v2, float2 v3) {
    float2 v[4] = { v0, v1, v2, v3 };
    float d2 = 1e20;
    float s = -1e20;
    [unroll]
    for (int i = 0; i < 4; ++i) {
        float2 a = v[i];
        float2 b = v[(i + 1) % 4];
        float sdE = sdSegment(p, a, b);
        d2 = min(d2, sdE * sdE);
        float2 e = b - a;
        float2 n = normalize(float2(e.y, -e.x)); // Outward normal (CCW)
        s = max(s, dot(p - a, n));
    }
    return (s > 0.0) ? sqrt(d2) : -sqrt(d2);
}

// Signed distance to a 2D Arc (Ring Segment)
// p: sampling point
// sc: float2(sin(a), cos(a)) where 'a' is the half-aperture angle
// ra: radius
// rb: thickness (half-width)
float sdArc(float2 p, float2 sc, float ra, float rb) {
    p.x = abs(p.x);
    return ((sc.y * p.x > sc.x * p.y) ? length(p - sc * ra) : abs(length(p) - ra)) - rb;
}

// --- Main Function ---
// User Request: A simple sound icon with a speaker shape and adjustable sound waves
void SoundIconShape_float(float2 UV, float Size, float WaveStrength, float4 Color, out float4 outColor) {
    // PLAN:
    // 1) Center and scale UV coordinates.
    // 2) Define speaker body using a Box (back) and Convex Poly (cone).
    // 3) Define 3 sound waves using Arcs displaced to the right.
    // 4) Mask waves based on WaveStrength parameter.
    // 5) Combine shapes using min() (Union).
    // 6) Apply anti-aliasing and color.

    // 1) Setup Coordinates
    float2 centered = UV - 0.5;
    // Avoid division by zero
    float s = max(Size, 0.001);
    float2 p = centered / s;

    // 2) Speaker Shape Construction
    // Back part (small box on the left)
    float2 boxSize = float2(0.05, 0.08);
    float2 boxPos = float2(-0.15, 0.0);
    float dBox = sdBox(p - boxPos, boxSize);

    // Cone part (trapezoid flaring to the right)
    // Defined as a convex polygon with 4 vertices
    float2 v0 = float2(-0.12, -0.08);
    float2 v1 = float2(-0.12, 0.08);
    float2 v2 = float2(0.08, 0.20);
    float2 v3 = float2(0.08, -0.20);
    float dCone = sdConvexPoly4(p, v0, v1, v2, v3);

    // Combine Speaker Parts
    float dSpeaker = min(dBox, dCone);

    // 3) Sound Waves Construction
    // Rotate coordinates for the arc: standard arc is Y-up, we want X-right.
    // We shift origin to the speaker face (approx x=0.08) and rotate -90 degrees.
    float2 waveOrigin = float2(0.08, 0.0);
    float2 pRel = p - waveOrigin;
    // Rotate: (x,y) -> (-y, x)
    float2 q = float2(-pRel.y, pRel.x);

    // Arc parameters
    // Aperture: 60 degrees half-angle (sin(60)=0.866, cos(60)=0.5)
    float2 sc = float2(0.866025, 0.5);
    float thickness = 0.025;
    
    // Calculate 3 separate waves
    float w1_dist = sdArc(q, sc, 0.15, thickness);
    float w2_dist = sdArc(q, sc, 0.28, thickness);
    float w3_dist = sdArc(q, sc, 0.41, thickness);

    // 4) Apply Wave Strength Logic
    // We push the distance field to infinity (10.0) if the wave shouldn't be visible.
    // This effectively hides it.
    float showW1 = smoothstep(0.0, 0.25, WaveStrength);
    float showW2 = smoothstep(0.33, 0.58, WaveStrength);
    float showW3 = smoothstep(0.66, 0.91, WaveStrength);

    // Lerp distance to 'outside' value (10.0) based on visibility
    w1_dist = lerp(10.0, w1_dist, showW1);
    w2_dist = lerp(10.0, w2_dist, showW2);
    w3_dist = lerp(10.0, w3_dist, showW3);

    // Combine waves
    float dWaves = min(w1_dist, min(w2_dist, w3_dist));

    // 5) Final Shape Combination
    float dist = min(dSpeaker, dWaves);

    // 6) Anti-aliasing and Output
    float aa = fwidth(dist);
    float alpha = 1.0 - smoothstep(-aa, aa, dist);

    outColor = float4(Color.rgb * alpha, Color.a * alpha);
}

// ------------------------------------------------------------------------
//  Visual Result (High-level, parameter-invariant description)
// ------------------------------------------------------------------------
//  This function generates a **stylized 2D sound / speaker icon primitive**
//  using Signed Distance Functions (SDFs).
//
//  The shape is composed of a simple speaker body combined with multiple
//  curved wave elements radiating outward, forming a symbolic sound or
//  audio-emission silhouette. The size, proportions, number and visibility
//  of wave elements, and overall visual appearance are fully controlled by
//  input parameters and are not fixed by the function itself.
//
//  The output is an anti-aliased RGBA color suitable for audio controls,
//  volume indicators, UI icons, and analytic procedural 2D graphics.
// ------------------------------------------------------------------------
