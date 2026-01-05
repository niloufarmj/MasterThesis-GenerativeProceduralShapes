#ifndef PI
#define PI 3.14159265359
#endif

// Helper for straight-alpha compositing (src over dst)
float4 lens_over(float4 src, float4 dst) {
    float a = src.a + dst.a * (1.0 - src.a);
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-8);
    return float4(c, a);
}

void CartoonLensShape_float(float2 UV, float Radius, float Separation, float Rotation, float4 FillColor, float4 OutlineColor, float OutlineWidth, out float4 outColor) {
    // PLAN:
    // 1) Center UVs to (0,0) to work in cartesian space.
    // 2) Rotate the sampling point 'p' by -Rotation so the shape appears rotated by +Rotation.
    // 3) Create a lens shape (Vesica Piscis) by intersecting two offset circles.
    //    - Circle 1 Center: (-Separation, 0)
    //    - Circle 2 Center: (+Separation, 0)
    //    - Intersection SDF = max(distCircle1, distCircle2)
    // 4) Compute SDF for the fill and the stroke (outline).
    // 5) Apply analytic anti-aliasing using smoothstep and fwidth.
    // 6) Composite the Outline over the Fill for the final result.

    // 1. Center UVs
    float2 p = UV - 0.5;

    // 2. Rotate point (passive rotation)
    float c = cos(Rotation);
    float s = sin(Rotation);
    p = float2(c * p.x + s * p.y, -s * p.x + c * p.y);

    // 3. Lens SDF Calculation
    // Ensure safe positive values
    float r = max(Radius, 0.001);
    float sep = max(Separation, 0.0);
    
    // Distance to left circle (centered at -sep) and right circle (centered at +sep)
    float d1 = length(p - float2(-sep, 0.0)) - r;
    float d2 = length(p - float2(sep, 0.0)) - r;
    
    // Intersection operation (max of two distances)
    float dist = max(d1, d2);

    // 4. Anti-aliasing factor
    float aa = fwidth(dist);
    aa = max(aa, 0.001); // Safety clamp for derivatives

    // 5. Fill Layer
    // dist < 0 inside the shape. smoothstep(0, aa, dist) creates a smooth transition at the edge.
    float fillAlpha = 1.0 - smoothstep(0.0, aa, dist);
    float4 fillLayer = float4(FillColor.rgb, FillColor.a * fillAlpha);

    // 6. Outline Layer
    // Outline is a band centered on the shape boundary (dist = 0)
    float halfStroke = max(OutlineWidth * 0.5, 0.0);
    float strokeDist = abs(dist) - halfStroke;
    float strokeAlpha = 1.0 - smoothstep(0.0, aa, strokeDist);
    float4 strokeLayer = float4(OutlineColor.rgb, OutlineColor.a * strokeAlpha);

    // 7. Composite (Stroke OVER Fill)
    outColor = lens_over(strokeLayer, fillLayer);
}

// ------------------------------------------------------------------------
//  Visual Result
// ------------------------------------------------------------------------
//  This function generates a **stylized cartoon lens shape** (also known as
//  a Vesica Piscis) using Signed Distance Functions (SDFs).
//
//  The visual result is composed of:
//  - The intersection of two overlapping circles, creating a symmetrical,
//    almond-like geometry.
//  - Two sharp vertices at opposite ends where the circle perimeters meet.
//  - A smooth, curved body resembling a leaf, an eye, or a seed.
//
//  The shape features adjustable parameters for the circle radius and the
//  separation distance between centers, allowing the shape to range from
//  a nearly circular oval to a thin, sharp sliver.
//
//  A consistent, anti-aliased outline surrounds the shape, making it versatile
//  for use as organic foliage sprites, character eyes, or abstract UI elements.
// ------------------------------------------------------------------------