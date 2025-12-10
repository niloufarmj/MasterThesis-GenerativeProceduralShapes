#ifndef PI
#define PI 3.14159265359
#endif

// Helper: Uneven Capsule SDF (Inigo Quilez)
// Creates a capsule with different radii at ends. 
// For a water drop, we set the top radius (r2) to 0.
// p: sampling point
// r1: bottom radius
// r2: top radius
// h: height between centers
float sdUnevenCapsule(float2 p, float r1, float r2, float h)
{
    p.x = abs(p.x);
    float b = (r1 - r2) / h;
    float a = sqrt(1.0 - b * b);
    float k = dot(p, float2(-b, a));
    
    if (k < 0.0) return length(p) - r1;
    if (k > a * h) return length(p - float2(0.0, h)) - r2;
    return dot(p, float2(a, b)) - r1;
}

void WaterDropIcon_float(float2 UV, float Height, float Radius, float2 Center, float Rotation, float4 Color, out float4 outColor) 
{
    // PLAN:
    // 1) Recenter UV coordinates to the input Center.
    // 2) Rotate the coordinate space (rotate point by -Angle).
    // 3) Offset Y to center the droplet shape visually (align geometric center to 0,0).
    // 4) Compute SDF using uneven capsule formula with top radius 0.
    // 5) Apply anti-aliasing using smoothstep and output final color.

    float2 p = UV - Center;

    // Rotate coordinates (CCW shape rotation)
    float c = cos(Rotation);
    float s = sin(Rotation);
    p = float2(c * p.x + s * p.y, -s * p.x + c * p.y);

    // Validate dimensions to avoid math errors
    // Height (h) must be > Radius (r1) for the math to hold, otherwise sqrt(negative)
    // We clamp Height to be slightly larger than Radius.
    float r = max(Radius, 0.0);
    float h = max(Height, r * 1.01);

    // Visual Centering
    // The shape is defined from y = -r (bottom edge) to y = h (top tip).
    // The vertical midpoint is (h - r) / 2.0.
    // We shift the coordinate 'p' down so that the origin (0,0) aligns with this midpoint.
    p.y += (h - r) * 0.5;

    // Calculate Signed Distance Field
    // r1 = r (bottom), r2 = 0.0 (top tip)
    float dist = sdUnevenCapsule(p, r, 0.0, h);

    // Anti-aliasing
    // Use fwidth for consistent edge softness based on screen resolution
    float aa = fwidth(dist);
    // Fallback for previews where derivatives might be zero
    aa = max(aa, 0.001);

    // Compute alpha mask
    // SDF is negative inside, so smoothstep(aa, -aa) gives 1.0 inside, 0.0 outside
    float edge = smoothstep(aa, -aa, dist);

    // Final Output
    // Premultiplied alpha approach: multiply both RGB and Alpha by the mask
    outColor = float4(Color.rgb * edge, Color.a * edge);
}