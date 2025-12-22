#ifndef PI
#define PI 3.14159265359
#endif

// Helper: SDF for a rounded box
// p: point relative to center
// b: half-extents (width/2, height/2)
// r: corner radius
float sdRoundedBox(float2 p, float2 b, float r)
{
    float2 q = abs(p) - (b - r);
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void RectangleRounded_float(float2 UV, float Width, float Height, float Radius, float2 Center, float Rotation, float4 Color, out float4 outColor)
{
    // PLAN:
    // 1) Translate UV to center (UV - Center).
    // 2) Rotate the coordinate system to rotate the shape.
    // 3) Calculate half-dimensions and valid corner radius.
    // 4) Compute Signed Distance Field (SDF).
    // 5) Anti-alias the edge using smoothstep and fwidth.
    // 6) Output final color with alpha.

    // 1) Center coordinates
    float2 p = UV - Center;

    // 2) Rotate coordinates (rotate point by -angle for shape rotation +angle)
    float c = cos(Rotation);
    float s = sin(Rotation);
    p = float2(p.x * c + p.y * s, -p.x * s + p.y * c);

    // 3) Dimensions
    float2 halfSize = float2(abs(Width), abs(Height)) * 0.5;
    
    // Clamp corner radius to not exceed half the shortest dimension
    // This prevents the SDF from breaking if Radius > Width/2
    float r = clamp(Radius, 0.0, min(halfSize.x, halfSize.y));

    // 4) Calculate SDF
    // Negative values are inside, positive outside
    float dist = sdRoundedBox(p, halfSize, r);

    // 5) Anti-aliasing
    // fwidth(dist) approximates the width of 1 pixel in SDF space
    float aa = fwidth(dist);
    // Fallback for cases where derivatives might be zero
    aa = max(aa, 0.0001);
    
    // smoothstep(aa, -aa, dist) creates a smooth transition from 0 to 1 at the edge
    float alpha = smoothstep(aa, -aa, dist);

    // 6) Output
    outColor = float4(Color.rgb, Color.a * alpha);
}

// ------------------------------------------------------------------------
//  Visual Result (High-level, parameter-invariant description)
// ------------------------------------------------------------------------
//  This function generates a **2D rounded-rectangle primitive** using
//  Signed Distance Functions (SDFs).
//
//  The shape consists of a rectangular form with smoothly rounded corners,
//  producing a soft-edged rectangular silhouette. The rectangle’s width,
//  height, corner radius, orientation, placement, and color are fully
//  controlled by input parameters and are not fixed by the function itself.
//
//  The output is an anti-aliased RGBA color suitable for UI elements,
//  buttons, panels, cards, and analytic procedural 2D graphics.
// ------------------------------------------------------------------------
