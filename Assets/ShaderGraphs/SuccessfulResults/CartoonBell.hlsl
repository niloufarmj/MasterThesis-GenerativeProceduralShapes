#ifndef PI
#define PI 3.14159265359
#endif

// --- Helpers ---

// Alpha blending helper (src over dst)
inline float4 bell_over(float4 src, float4 dst) {
    float a = src.a + dst.a * (1.0 - src.a);
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-8);
    return float4(c, a);
}

// Smooth Minimum for organic blending (Polynomial)
// k controls the radius/smoothness of the blend
inline float bell_smin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / max(k, 1e-6), 0.0, 1.0);
    return lerp(b, a, h) - k * h * (1.0 - h);
}

// Trapezoid SDF (Inigo Quilez)
// r1: bottom half-width, r2: top half-width, he: half-height
inline float bell_sdTrapezoid(float2 p, float r1, float r2, float he) {
    float2 k1 = float2(r2, he);
    float2 k2 = float2(r2 - r1, 2.0 * he);
    p.x = abs(p.x);
    float2 ca = float2(p.x - min(p.x, (p.y < 0.0) ? r1 : r2), abs(p.y) - he);
    float2 cb = p - k1 + k2 * clamp(dot(k1 - p, k2) / dot(k2, k2), 0.0, 1.0);
    float s = (cb.x < 0.0 && ca.y < 0.0) ? -1.0 : 1.0;
    return s * sqrt(min(dot(ca, ca), dot(cb, cb)));
}

// --- Main Function ---
// User Request: A simple outlined cartoonish bell with adjustable size and roundedness
void CartoonBell_float(float2 UV, float Size, float Roundedness, float4 FillColor, float4 OutlineColor, float OutlineThickness, out float4 outColor) {
    // PLAN:
    // 1) Center UVs to (0,0) and scale by 'Size' to allow resizing.
    // 2) Define Top Dome: A circle shifted upwards.
    // 3) Define Body: A trapezoid (narrow top, wide bottom) shifted downwards.
    // 4) Blend Dome and Body using smooth min (smin) controlled by 'Roundedness'.
    // 5) Define Clapper: A small circle hanging at the bottom.
    // 6) Combine Bell and Clapper.
    // 7) Apply AA and Outline logic using standard SDF techniques.

    // 1. Setup Coordinates
    float2 centered = UV - 0.5;
    float2 p = centered / max(Size, 0.01);

    // 2. Define Bell Parts
    // Dome: Circle at the top (y=0.2), matching trapezoid top width
    // Trapezoid Top Width = 0.25 (Radius)
    float dDome = length(p - float2(0.0, 0.2)) - 0.25;
    
    // Body: Trapezoid. 
    // Center Y = -0.05. Half-Height = 0.25. 
    // Top Y = -0.05 + 0.25 = 0.2 (Meets dome center perfectly)
    // Bottom Y = -0.05 - 0.25 = -0.3
    // Bottom Half-Width = 0.45 (Flare out), Top Half-Width = 0.25
    float dBody = bell_sdTrapezoid(p - float2(0.0, -0.05), 0.45, 0.25, 0.25);

    // 3. Blend Main Bell Shape
    // Use smin to smooth the transition between the round top and the angular body
    float dBell = bell_smin(dDome, dBody, max(Roundedness, 0.01));

    // 4. Clapper (The little ball inside/at bottom)
    // Positioned at y = -0.35, Radius = 0.1
    float dClapper = length(p - float2(0.0, -0.35)) - 0.1;

    // 5. Final SDF Combination
    // Union the bell shape and the clapper. We use min() here to keep the clapper distinct,
    // or we could use smin() for a meltier look. Min is cleaner for "cartoonish".
    float d = min(dBell, dClapper);

    // 6. Rendering (Fill & Outline)
    float aa = fwidth(d);
    
    // Fill Mask (Inside shape)
    float fillMask = 1.0 - smoothstep(0.0, aa, d);
    float4 fillLayer = float4(FillColor.rgb, saturate(FillColor.a) * fillMask);

    // Outline Mask (Band around edge)
    float halfW = 0.5 * max(OutlineThickness, 0.0);
    float edgeDist = abs(d) - halfW;
    float strokeMask = 1.0 - smoothstep(0.0, aa, edgeDist);
    float4 strokeLayer = float4(OutlineColor.rgb, saturate(OutlineColor.a) * strokeMask);

    // 7. Composite (Stroke over Fill)
    outColor = bell_over(strokeLayer, fillLayer);
}

// ------------------------------------------------------------------------
//  Visual Result (High-level, parameter-invariant description)
// ------------------------------------------------------------------------
//  This function generates a **stylized 2D cartoon bell primitive**
//  using Signed Distance Functions (SDFs).
//
//  The shape forms a bell-like silhouette composed of a rounded upper
//  dome, a flared lower body, and a small circular clapper element near
//  the bottom. The overall proportions, roundedness, size, fill color,
//  outline thickness, and outline color are fully controlled by input
//  parameters and are not fixed by the function itself.
//
//  The output is an anti-aliased RGBA color suitable for notification
//  icons, alert indicators, UI symbols, and expressive procedural
//  2D graphics.
// ------------------------------------------------------------------------
