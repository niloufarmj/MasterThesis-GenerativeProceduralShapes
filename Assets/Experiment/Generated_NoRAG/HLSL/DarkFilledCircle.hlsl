// USER REQUEST: a filled circle in dark color

void DarkFilledCircle_float(float2 UV, float Radius, float2 Center, float4 Color, out float4 outColor) {
    // PLAN:
    // 1) Remap UV to centered coords based on Center parameter.
    // 2) Compute standard Circle SDF: distance from center minus radius.
    // 3) Use fwidth and smoothstep for an anti-aliased edge.
    // 4) Output color and alpha using the mask.

    // 1) Centered UV
    float2 p = UV - Center;

    // 2) Circle SDF
    float dist = length(p) - max(Radius, 0.0);

    // 3) Anti-aliasing
    float aa = fwidth(dist);
    float mask = 1.0 - smoothstep(0.0, aa, dist);

    // 4) Output (straight alpha)
    outColor = float4(Color.rgb * mask, mask);
}