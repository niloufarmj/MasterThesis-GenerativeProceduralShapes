#ifndef PI
#define PI 3.14159265359
#endif

// Circle SDF: distance from point p to a circle of radius r centered at origin
float sdCircle(float2 p, float r)
{
    return length(p) - r;
}

void FunctionName_float(float2 UV, float Radius, float4 FillColor, out float4 outColor)
{
    // USER REQUEST: A clean filled circle centered on the screen with adjustable radius and fill color.

    // PLAN:
    // 1) Center UV to get local coordinates around (0.5, 0.5).
    // 2) Compute SDF of a circle with given Radius.
    // 3) Use smoothstep on the SDF for anti-aliased, sharp-looking edges.
    // 4) Use the resulting mask for RGB and Alpha so the circle stays centered and fully visible.

    // 1) Center UV coordinates so (0.5, 0.5) is the origin
    float2 centered = UV - float2(0.5, 0.5);

    // 2) Circle SDF with radius in UV units (0.5 ~ half screen)
    float dist = sdCircle(centered, Radius);

    // 3) Anti-aliased edge using a fixed small width for crisp edges
    float edge = smoothstep(0.01, -0.01, dist);

    // 4) Output color with alpha based on the mask
    float mask = edge;
    outColor = float4(FillColor.rgb * mask, mask);
}
