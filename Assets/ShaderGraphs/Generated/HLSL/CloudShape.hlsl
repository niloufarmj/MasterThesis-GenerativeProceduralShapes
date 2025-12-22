#ifndef PI
#define PI 3.14159265359
#endif

// Helper: Smooth Minimum (Polynomial)
// Blends a and b with smoothness k. Used to create puffy merges between shapes.
float cloud_smin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / max(k, 0.0001), 0.0, 1.0);
    return lerp(b, a, h) - k * h * (1.0 - h);
}

void CloudShape_float(float2 UV, float Size, float Puffiness, float4 Color, out float4 outColor) {
    // PLAN:
    // 1) Center UV coordinates and scale them by Size parameter.
    // 2) Define 3 circles (one large top, two smaller sides) and a base rectangle.
    // 3) Combine these shapes using a smooth minimum (smin) to create organic connections.
    // 4) Use Puffiness parameter to control the blending strength (smoothness) of the smin.
    // 5) Apply anti-aliasing using SDF distance and fwidth.
    // 6) Output final color with alpha.

    // 1) Center and Scale
    float2 centered = UV - 0.5;
    float s = max(Size, 0.001); // Prevent division by zero
    float2 p = centered / s;

    // 2) Shape Definitions
    // Top Center Circle
    float dTop = length(p - float2(0.0, 0.15)) - 0.4;
    
    // Left Lobe Circle
    float dLeft = length(p - float2(-0.45, -0.15)) - 0.3;
    
    // Right Lobe Circle
    float dRight = length(p - float2(0.45, -0.15)) - 0.3;
    
    // Bottom Filler (Rounded Box) to flatten the base slightly and connect lobes
    float2 boxSize = float2(0.35, 0.15);
    float2 dBoxRaw = abs(p - float2(0.0, -0.25)) - boxSize;
    float dBase = length(max(dBoxRaw, 0.0)) + min(max(dBoxRaw.x, dBoxRaw.y), 0.0) - 0.15;

    // 3) & 4) Blend Shapes using Smooth Minimum
    // Puffiness controls the blend factor 'k'
    float k = clamp(Puffiness, 0.01, 0.6);
    
    float d = cloud_smin(dTop, dLeft, k);
    d = cloud_smin(d, dRight, k);
    d = cloud_smin(d, dBase, k);

    // 5) Anti-aliasing
    // fwidth(d) allows for consistent edge softness regardless of scale
    float aa = fwidth(d);
    float mask = 1.0 - smoothstep(-aa, aa, d);

    // 6) Final Color Output
    // Combine shape mask with input alpha
    float finalAlpha = mask * saturate(Color.a);
    outColor = float4(Color.rgb * finalAlpha, finalAlpha);
}