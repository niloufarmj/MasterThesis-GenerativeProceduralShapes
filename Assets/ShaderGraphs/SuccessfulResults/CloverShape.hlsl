#ifndef PI
#define PI 3.14159265359
#endif

void CloverShape_float(float2 UV, float Size, float NumLeaves, float Amplitude, float Rotation, float2 Center, float4 Color, out float4 outColor) {
    // PLAN:
    // 1) Translate UV to be relative to the Center.
    // 2) Convert Cartesian coordinates to Polar coordinates (radius, angle).
    // 3) Apply Rotation to the angle.
    // 4) Compute the clover shape radius using a cosine modulation: R = Size + Amp * cos(N * angle).
    // 5) Calculate Signed Distance Field (SDF) as (current_radius - shape_radius).
    // 6) Apply smoothstep for anti-aliasing and apply color.

    // 1. Center UV coordinates
    float2 centered = UV - Center;

    // 2. Convert to Polar Coordinates
    float len = length(centered);
    float angle = atan2(centered.y, centered.x);

    // 3. Apply Rotation
    // Subtracting rotation from the angle rotates the shape pattern
    float finalAngle = angle - Rotation;

    // 4. Calculate Shape Radius
    // The cosine function creates the lobes.
    // NumLeaves determines the frequency (3 = shamrock, 4 = lucky clover).
    // Amplitude determines how deep the "leaves" are cut.
    float shapeRadius = Size + Amplitude * cos(NumLeaves * finalAngle);

    // 5. Calculate Signed Distance
    // dist < 0 is inside, dist > 0 is outside
    // Note: This is a polar distance approximation, accurate enough for rendering
    float dist = len - shapeRadius;

    // 6. Anti-aliasing
    // Smoothstep provides a soft edge transition for AA
    float edge = smoothstep(0.01, -0.01, dist);

    // Output final color with alpha mask
    outColor = float4(Color.rgb * edge, edge);
}

// ------------------------------------------------------------------------
//  Visual Result (High-level, parameter-invariant description)
// ------------------------------------------------------------------------
//  This function generates a **radial, lobe-based 2D organic primitive**
//  using a polar-coordinate Signed Distance formulation.
//
//  The shape is defined by a circular form whose radius is periodically
//  modulated, producing multiple rounded lobes arranged around a center.
//  The number of lobes, their depth, orientation, size, and placement are
//  fully controlled by input parameters and are not fixed by the function.
//
//  The output is an anti-aliased RGBA color suitable for symbolic,
//  decorative, and expressive procedural 2D graphics.
// ------------------------------------------------------------------------
