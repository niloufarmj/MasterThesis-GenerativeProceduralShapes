void FilledCircleDark_float(float2 UV, float Radius, float4 Color, out float4 outColor)
{
    // a filled circle in dark color

    // PLAN:
    // 1. Center UV coordinates to make (0,0) the center of the screen.
    // 2. Calculate the Signed Distance Field (SDF) for a circle.
    // 3. Use smoothstep with the screen-space derivative (fwidth) for anti-aliasing.
    // 4. Output the final color, using the result as a mask for color and alpha.

    // 1. Center UV coordinates
    float2 centered = UV - 0.5;

    // 2. Circle Signed Distance Field
    // The distance is negative inside the circle, 0 on the edge, and positive outside.
    float dist = length(centered) - Radius;

    // 3. Anti-aliased edge calculation
    // fwidth provides a screen-space derivative for consistent blur at any scale.
    float aa = fwidth(dist);
    float mask = smoothstep(aa, -aa, dist);

    // 4. Output final color
    // The mask is used for both the color and the alpha channel.
    outColor = float4(Color.rgb * mask, Color.a * mask);
}