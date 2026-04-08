#ifndef PI
#define PI 3.14159265359
#endif

// Helper: Calculate signed distance to a 2D triangle (CCW vertices)
// Returns negative inside, positive outside
float sdSimpleTriangle_Helper(float2 p, float2 p0, float2 p1, float2 p2)
{
    float2 e0 = p1 - p0;
    float2 e1 = p2 - p1;
    float2 e2 = p0 - p2;

    float2 v0 = p - p0;
    float2 v1 = p - p1;
    float2 v2 = p - p2;

    float2 pq0 = v0 - e0 * clamp(dot(v0, e0) / max(dot(e0, e0), 1e-8), 0.0, 1.0);
    float2 pq1 = v1 - e1 * clamp(dot(v1, e1) / max(dot(e1, e1), 1e-8), 0.0, 1.0);
    float2 pq2 = v2 - e2 * clamp(dot(v2, e2) / max(dot(e2, e2), 1e-8), 0.0, 1.0);

    // Winding number / sign determination
    float s = sign(e0.x * e2.y - e0.y * e2.x);
    
    // Combine distances to 3 edges
    float2 d = min(min(float2(dot(pq0, pq0), s * (v0.x * e0.y - v0.y * e0.x)),
                       float2(dot(pq1, pq1), s * (v1.x * e1.y - v1.y * e1.x))), 
                       float2(dot(pq2, pq2), s * (v2.x * e2.y - v2.y * e2.x)));

    // Return signed distance
    return -sqrt(d.x) * sign(d.y);
}

void SimpleTriangle_float(float2 UV, float2 Position, float Size, float Rotation, float4 Color, float MaxCornerRadius, float AnimationSpeed, float Time, out float4 outColor)
{
    // Translate to center position
    float2 p = UV - Position;

    // Apply rotation
    float c = cos(Rotation);
    float s = sin(Rotation);
    p = float2(c * p.x + s * p.y, -s * p.x + c * p.y);

    // Calculate animatable radius
    // Sinuous change from 0.0 (sharp) to 1.0 (fully rounded) and back.
    float anim = sin(Time * AnimationSpeed) * 0.5 + 0.5;

    // Size defines the circumscribed radius of the equilateral triangle
    float R = max(Size, 0.0001);
    
    // Maximum rounding radius is limited to R/2 to prevent inverting the shape 
    // (an inscribed circle has radius R/2)
    float maxR = min(max(MaxCornerRadius, 0.0), R * 0.5);
    
    // Current corner radius based on animation
    float r = maxR * anim;
    
    // Shrink the base triangle by 2*r so that after rounding (which inflates by r),
    // the straight edges remain exactly at their original positions.
    float effectiveSize = max(R - 2.0 * r, 0.0001);

    // Define vertices (Equilateral triangle pointing upwards)
    // cos(30 deg) = 0.86602540378, sin(30 deg) = 0.5
    float2 v0 = float2(0.0, effectiveSize);
    float2 v1 = float2(effectiveSize * 0.86602540378, -effectiveSize * 0.5);
    float2 v2 = float2(-effectiveSize * 0.86602540378, -effectiveSize * 0.5);

    // Calculate SDF and round corners by subtracting the animated radius r
    float dist = sdSimpleTriangle_Helper(p, v0, v1, v2) - r;

    // Smooth anti-aliasing
    float aa = fwidth(dist);
    float fillMask = 1.0 - smoothstep(0.0, max(aa, 1e-5), dist);

    // Output final blended color
    outColor = float4(Color.rgb, saturate(Color.a) * fillMask);
}
