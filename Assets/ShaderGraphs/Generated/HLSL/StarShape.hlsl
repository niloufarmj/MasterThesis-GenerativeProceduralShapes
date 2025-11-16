void StarShape_float(float2 UV, float StarInnerRadius, float StarOuterRadius, float4 Color, out float4 outColor) {
    // PLAN:
    // 1) Remap UV to local coordinates centered around (0.5, 0.5)
    // 2) Calculate the radial & angular components of the UV coordinates
    // 3) Define path for the star's outer and inner vertices
    // 4) Generate the signed distance field (SDF) for the star by comparing angles and radii
    // 5) Calculate soft edge (anti-aliasing) using smoothstep based on SDF
    // 6) Output final color using calculated mask

    float2 centered = UV - float2(0.5, 0.5);
    centered *= 2.0;
    float angle = atan2(centered.y, centered.x) + PI;
    float rad = length(centered);
    float nip = 5.0; // Number of star points
    float step = 2.0 * PI / nip;
    float phase = fmod(angle + step / 2.0, step) - step / 2.0;
    float innerOuterMix = cos(phase * nip) * 0.5 + 0.5;
    float radiusMix = lerp(StarInnerRadius, StarOuterRadius, innerOuterMix);
    float dist = radiusMix - rad;
    float edge = smoothstep(0.01, -0.01, dist);
    outColor = float4(Color.rgb * edge, edge);
}