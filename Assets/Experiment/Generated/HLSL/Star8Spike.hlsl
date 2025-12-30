// An 8-pointed star with adjustable spike length, rotation, and sharp corners
#ifndef PI
#define PI 3.14159265359
#endif

void Star8Spike_float(float2 UV, float OuterRadius, float InnerRadius, float Rotation, float4 Color, out float4 outColor) {
    // PLAN:
    // 1. Center UV coordinates at (0.5, 0.5) and apply rotation.
    // 2. Convert to polar coordinates and fold space into a single sector (N=8).
    // 3. Define the star edge as a segment between the peak and the valley.
    // 4. Compute signed distance (SDF) to this segment.
    // 5. Apply smoothstep for anti-aliasing and output color.

    // 1. Center and Rotate
    float2 p = UV - 0.5;
    float c = cos(Rotation);
    float s = sin(Rotation);
    p = float2(p.x * c - p.y * s, p.x * s + p.y * c);

    // 2. Sector Folding (N=8)
    // The star has 8 points, so 8 sectors. Angle per sector is 2*PI/8 = PI/4.
    // We fold this further into a half-sector of PI/8 for symmetry.
    float an = PI / 8.0;
    float bn = 2.0 * an;

    // Polar coordinates (atan2(x,y) puts 0 on the +Y axis, aligning the first spike up)
    float angle = atan2(p.x, p.y);
    float len = length(p);

    // Map angle to the local sector domain [-PI/8, PI/8]
    float sector = floor(angle / bn + 0.5);
    float theta = angle - sector * bn;

    // Convert back to Cartesian in the local folded sector
    // The local Y-axis is the center of the spike
    float2 pRot = float2(sin(theta), cos(theta)) * len;
    
    // Fold symmetry across the local Y-axis to simplify to a single edge segment
    pRot.x = abs(pRot.x);

    // 3. SDF Calculation
    // Define the segment endpoints for the star edge
    // p1: Tip of the spike (on Y-axis at OuterRadius)
    // p2: Valley (at angle 'an' at InnerRadius)
    float2 p1 = float2(0.0, OuterRadius);
    float2 p2 = float2(sin(an) * InnerRadius, cos(an) * InnerRadius);

    // Compute distance to the segment p1-p2
    float2 e = p1 - p2;
    float2 w = pRot - p2;
    
    // Project w onto the segment, clamped to endpoints [0,1]
    float t = clamp(dot(w, e) / dot(e, e), 0.0, 1.0);
    float2 closest = w - e * t;
    float dist = length(closest);

    // Determine sign (Negative = Inside, Positive = Outside)
    // We use the outward-facing normal of the edge vector 'e'
    float2 n = float2(e.y, -e.x);
    // Since the origin is inside the star, and the normal points outward,
    // if dot(w, n) is negative, we are on the 'inside' side of the edge.
    if (dot(w, n) < 0.0)
    {
        dist = -dist;
    }

    // 4. Anti-aliasing
    // Use fwidth for pixel-perfect edge smoothing
    float aa = fwidth(dist);
    aa = max(aa, 0.001); // Safety clamp for previews

    // Mask: 1.0 inside, 0.0 outside
    float mask = 1.0 - smoothstep(-aa, aa, dist);

    // 5. Final Output
    outColor = float4(Color.rgb, Color.a * mask);
}