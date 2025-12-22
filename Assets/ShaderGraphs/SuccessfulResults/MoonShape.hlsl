#ifndef PI
#define PI 3.14159265359
#endif

void MoonShape_float(float2 UV, float OuterRadius, float InnerRadius, float Offset, float2 Center, float Rotation, float4 Color, out float4 outColor) {
    // PLAN:
    // 1) Recenter UV coordinates to the shape center.
    // 2) Rotate the coordinate system to handle shape rotation.
    // 3) Calculate SDF for the main outer circle.
    // 4) Calculate SDF for the inner cutting circle, offset to create the crescent.
    // 5) Perform SDF subtraction (Outer - Inner).
    // 6) Apply anti-aliasing and output final color.

    // 1) Center UV
    float2 p = UV - Center;

    // 2) Rotate sampling point (inverse rotation of shape)
    float c = cos(Rotation);
    float s = sin(Rotation);
    p = float2(p.x * c + p.y * s, -p.x * s + p.y * c);

    // 3) Outer Circle SDF
    // Signed distance: negative inside, positive outside
    float dOuter = length(p) - OuterRadius;

    // 4) Inner Circle SDF (The Cutter)
    // We offset the cutter along the local X axis.
    // Adjusting Offset changes the thickness of the crescent.
    float2 pInner = p - float2(Offset, 0.0);
    float dInner = length(pInner) - InnerRadius;

    // 5) Subtract Inner from Outer
    // Boolean subtraction in SDF is max(A, -B)
    // This keeps the area where we are inside Outer (dOuter < 0) 
    // AND outside Inner (dInner > 0 -> -dInner < 0).
    float dist = max(dOuter, -dInner);

    // 6) Anti-aliasing
    // fwidth gives us the pixel derivative for sharp, resolution-independent edges
    float aa = fwidth(dist);
    // Fallback for very flat derivatives to avoid div by zero issues (optional but safe)
    aa = max(aa, 0.0001);
    
    // Smoothstep creates a soft mask at the edge
    // Returns 1.0 inside the shape, 0.0 outside
    float mask = smoothstep(aa, -aa, dist);

    // 7) Final Output
    outColor = float4(Color.rgb * mask, Color.a * mask);
}

// ------------------------------------------------------------------------
//  Visual Result (High-level, parameter-invariant description)
// ------------------------------------------------------------------------
//  This function generates a **stylized 2D crescent-moon-like primitive**
//  using Signed Distance Functions (SDFs).
//
//  The shape is formed by subtracting one circular region from another,
//  producing a curved crescent silhouette. The thickness, curvature,
//  orientation, placement, and overall appearance of the crescent are
//  fully controlled by input parameters and are not fixed by the function
//  itself.
//
//  The output is an anti-aliased RGBA color suitable for icons,
//  symbolic UI elements, decorative graphics, and expressive procedural
//  2D visuals.
// ------------------------------------------------------------------------
