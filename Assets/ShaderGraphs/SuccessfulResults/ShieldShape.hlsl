void ShieldShape_float(float2 UV, float Width, float Height, float4 FillColor, float4 StrokeColor, float StrokeWidth, out float4 outColor) {
    // PLAN:
    // 1) Center UVs to (0,0) range [-1, 1].
    // 2) Shift Y coordinate so the shield is centered visually.
    // 3) Calculate shield SDF using circle intersection method (classic Heater Shield).
    //    - Top edge is flat (y=0 in math space).
    //    - Sides are defined by circles passing through top corners and bottom tip.
    // 4) Compute Fill and Stroke masks using smoothstep AA.
    // 5) Composite Stroke OVER Fill for final result.

    // 1. Center and Scale coordinates
    float2 p = (UV - 0.5) * 2.0;

    // 2. Adjust Y to center the shape
    // The mathematical shape is defined from y=0 (top) down to y=-Height.
    // To center this visually at (0,0), we map world y=Height/2 to math y=0.
    p.y -= Height * 0.5;

    // 3. Shield SDF Geometry
    // Symmetry: work on the right side only
    float2 q = p;
    q.x = abs(q.x);

    float w = max(Width * 0.5, 0.001); // Half-width
    float h = max(Height, 0.001);      // Full height

    // We find a circle that passes through the top corner (w, 0) and bottom tip (0, -h).
    // Circle center (cx, 0). Radius R = w - cx.
    // Solving: (w-cx)^2 + 0 = R^2  AND  (0-cx)^2 + (-h)^2 = R^2
    // Result: cx = (w^2 - h^2) / (2w)
    float cx = (w * w - h * h) / (2.0 * w);
    float r = w - cx;

    // Distance to the defining circle
    float dCircle = length(q - float2(cx, 0.0)) - r;

    // Clip the top flat edge (math y > 0 is outside)
    // Intersection = max(distCircle, distPlane)
    float d = max(dCircle, q.y);

    // 4. Anti-Aliasing & Rendering
    // Calculate derivative for crisp edges at any scale
    float aa = fwidth(d);
    if (aa == 0) aa = 0.01; // Fallback for some shader stages

    // Fill Layer
    float fillMask = 1.0 - smoothstep(0.0, aa, d);
    float4 fillLayer = float4(FillColor.rgb, FillColor.a * fillMask);

    // Stroke Layer
    float halfStroke = StrokeWidth * 0.5;
    // Distance to stroke edge (centered on shape boundary)
    float strokeDist = abs(d) - halfStroke;
    float strokeMask = 1.0 - smoothstep(0.0, aa, strokeDist);
    float4 strokeLayer = float4(StrokeColor.rgb, StrokeColor.a * strokeMask);

    // 5. Composite: Stroke OVER Fill
    // Standard straight-alpha blending equation
    float outA = strokeLayer.a + fillLayer.a * (1.0 - strokeLayer.a);
    float3 outRGB = (strokeLayer.rgb * strokeLayer.a + fillLayer.rgb * fillLayer.a * (1.0 - strokeLayer.a)) / max(outA, 1e-5);

    outColor = float4(outRGB, outA);
}

// ------------------------------------------------------------------------
//  Visual Result (High-level, parameter-invariant description)
// ------------------------------------------------------------------------
//  This function generates a **2D shield-like primitive** using
//  Signed Distance Functions (SDFs).
//
//  The shape forms a vertically symmetric emblem silhouette with a flat
//  upper edge and a smoothly tapering lower point, resembling a classic
//  shield or badge form. The overall proportions, scale, fill, outline,
//  and visual appearance are fully controlled by input parameters and are
//  not fixed by the function itself.
//
//  The output is an anti-aliased RGBA color suitable for icons,
//  status indicators, badges, game UI elements, and analytic procedural
//  2D graphics.
// ------------------------------------------------------------------------
