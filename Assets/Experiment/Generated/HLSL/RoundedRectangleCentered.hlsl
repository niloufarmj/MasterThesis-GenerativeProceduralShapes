#ifndef PI
#define PI 3.14159265359
#endif

// Signed distance to an axis-aligned rectangle centered at origin.
// halfSize = (width/2, height/2) in the same units as p.
float sdRectangle(float2 p, float2 halfSize)
{
    float2 d = abs(p) - halfSize;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// Rounded rectangle via SDF offset:
// d_round = sdRectangle(p, halfSize - r) - r;  (caller clamps r)
float sdRoundRectangle(float2 p, float2 halfSize, float r)
{
    return sdRectangle(p, halfSize - r) - r;
}

void FunctionName_float(float2 UV, float Width, float Height, float CornerRadius, float4 FillColor, out float4 outColor)
{
    // USER REQUEST: A rectangle with rounded corners, centered on the screen with adjustable roundness, width, height, and fill color.

    // PLAN:
    // 1) Recenter UV to have origin at screen center (0.5, 0.5).
    // 2) Build a rounded-rectangle SDF using width, height, and corner radius.
    // 3) Use smoothstep with a small fixed AA width for smooth edges.
    // 4) Output FillColor multiplied by the mask, with alpha equal to the mask.

    // 1) Center UV coordinates
    float2 centered = UV - 0.5;

    // 2) Rounded rectangle SDF in UV units
    float2 halfSize = 0.5 * float2(max(Width, 0.0), max(Height, 0.0));
    float maxRadius = min(halfSize.x, halfSize.y);
    float r = clamp(CornerRadius, 0.0, maxRadius);
    float dist = sdRoundRectangle(centered, halfSize, r);

    // 3) Anti-aliased edge (fixed AA width in UV space)
    float edge = smoothstep(0.01, -0.01, dist);

    // 4) Output with smooth alpha
    outColor = float4(FillColor.rgb * edge, edge);
}
