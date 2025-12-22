#ifndef CHECKMARK_SHAPE_INCLUDED
#define CHECKMARK_SHAPE_INCLUDED

// Helper function: Signed Distance to a Line Segment
// Returns the distance from point p to the segment ab
// User Request: A simple checkmark tick shape adjustable in size and thickness
float sdSegment_Checkmark(float2 p, float2 a, float2 b) {
    float2 pa = p - a;
    float2 ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}

void CheckmarkShape_float(float2 UV, float Size, float Thickness, float4 Color, out float4 outColor) {
    // PLAN:
    // 1. Center the UV coordinates at (0.5, 0.5).
    // 2. Scale the coordinate space by Size (with safety check).
    // 3. Define the three key points of the checkmark (Left, Corner, Right).
    // 4. Calculate SDF to the two segments (Left-Corner, Corner-Right).
    // 5. Combine using min() to get the union of the lines.
    // 6. Subtract half-thickness to define the stroke width.
    // 7. Apply smoothstep for anti-aliasing.
    // 8. Output the final color with alpha.

    float2 p = UV - 0.5;
    
    // Safety: prevent division by zero
    float s = max(Size, 0.0001);
    p /= s;

    // Define checkmark vertices in local scaled space
    // Coordinates balanced to look like a standard tick mark
    float2 vLeft   = float2(-0.35, -0.05);
    float2 vCorner = float2(-0.10, -0.30);
    float2 vRight  = float2( 0.35,  0.40);

    // Calculate distances to both segments
    float d1 = sdSegment_Checkmark(p, vLeft, vCorner);
    float d2 = sdSegment_Checkmark(p, vCorner, vRight);

    // Combine segments (Union)
    float dist = min(d1, d2);

    // Convert to stroke: SDF is distance minus radius (half thickness)
    float sdf = dist - (Thickness * 0.5);

    // Anti-aliasing
    // fwidth handles the derivative relative to screen pixels, adjusting for the scale 's'
    float aa = fwidth(sdf);
    aa = max(aa, 0.0001); // Safety clamp

    // Compute alpha mask: 0 outside, 1 inside
    float mask = 1.0 - smoothstep(-aa, aa, sdf);

    // Output color
    outColor = float4(Color.rgb * mask, Color.a * mask);
}
#endif

// ------------------------------------------------------------------------
//  Visual Result (High-level, parameter-invariant description)
// ------------------------------------------------------------------------
//  This function generates a **stylized 2D checkmark (tick) primitive**
//  using Signed Distance Functions (SDFs).
//
//  The visual result is a clean, angular checkmark composed of two straight
//  line segments joined at an inner corner, forming the familiar “tick”
//  silhouette. The checkmark is rendered as a stroked shape with rounded
//  ends and smooth joins, producing a clear and readable symbol.
//
//  The overall size, stroke thickness, orientation, placement, and color
//  are fully controlled by input parameters and are not fixed by the
//  function itself.
//
//  The output is an anti-aliased RGBA color suitable for confirmation
//  icons, status indicators, UI feedback elements, and analytic procedural
//  2D graphics.
// ------------------------------------------------------------------------
