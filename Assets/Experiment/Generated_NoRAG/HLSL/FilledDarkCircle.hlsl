// User request: a filled circle in dark color

#ifndef PI
#define PI 3.14159265359
#endif

void FilledDarkCircle_float(
    float2 UV,
    float Size,
    float4 Color,
    out float4 outColor)
{
    // PLAN:
    // 1) Center UV coordinates to (-0.5, 0.5) range.
    // 2) Compute circle SDF: dist = length(centered) - Size.
    // 3) Anti-alias the edge using smoothstep.
    // 4) Output dark filled circle with smooth alpha.

    // Step 1: Center UV coordinates
    float2 centered = UV - 0.5;

    // Step 2: Circle SDF (negative inside, positive outside)
    float dist = length(centered) - Size;

    // Step 3: Anti-aliased edge using fwidth for screen-space AA
    float aa = fwidth(dist);
    float edge = 1.0 - smoothstep(-aa, aa, dist);

    // Step 4: Output dark filled circle
    outColor = float4(Color.rgb * edge, Color.a * edge);
}