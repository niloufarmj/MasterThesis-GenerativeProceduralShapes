#ifndef PI
#define PI 3.14159265359
#endif

void HorseshoeMagnet_float(float2 UV, float Size, float LegLength, float Thickness, float Rotation, float4 Color, out float4 outColor) {
    // PLAN:
    // 1) Center UV at (0.5, 0.5) and rotate by Rotation angle.
    // 2) Fold the space along the x-axis (abs(p.x)) to exploit U-shape symmetry.
    // 3) Construct a 'skeleton' SDF consisting of:
    //    - A semi-circle arc in the upper half (y > 0).
    //    - A vertical line segment in the lower half (y <= 0).
    // 4) Subtract half-thickness from the skeleton distance to create the magnet body.
    // 5) Clip the rounded bottom caps to create flat ends using a plane cut.
    // 6) Apply smoothstep anti-aliasing and output the final color.

    // 1. Center and Rotate
    float2 centered = UV - 0.5;
    float c = cos(Rotation);
    float s = sin(Rotation);
    float2 p = float2(centered.x * c - centered.y * s, centered.x * s + centered.y * c);

    // 2. Symmetry (calculate for the right half only)
    p.x = abs(p.x);

    // 3. Skeleton SDF (Distance to the central path of the magnet)
    // The path is an arc of radius 'Size' starting at angle 0 (x-axis) going up,
    // and a straight line going down from the x-axis to -LegLength.
    float d_skeleton;

    if (p.y > 0.0) {
        // Upper half: Distance to the quarter-circle arc
        // Since we are in the quadrant x>0, y>0, simple length difference works
        d_skeleton = abs(length(p) - Size);
    } else {
        // Lower half: Distance to the vertical line segment
        // The segment is fixed at x = Size, extending from y = 0 to y = -LegLength
        float clampedY = clamp(p.y, -LegLength, 0.0);
        d_skeleton = distance(p, float2(Size, clampedY));
    }

    // 4. Expand skeleton to create volume
    // Subtracting half the thickness creates a shell around the skeleton
    float d = d_skeleton - (Thickness * 0.5);

    // 5. Flatten the ends
    // The sdf above creates rounded caps at the bottom. We clip them flat.
    // We want the region where y > -LegLength.
    // The SDF for the plane y = -LegLength (pointing up) is (-LegLength - y).
    // Intersection is max(shape, plane_cut).
    d = max(d, -p.y - LegLength);

    // 6. Anti-aliasing and Output
    float edge = smoothstep(0.01, -0.01, d);
    outColor = float4(Color.rgb * edge, edge);
}