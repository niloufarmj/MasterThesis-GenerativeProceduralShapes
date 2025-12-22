#ifndef PI
#define PI 3.14159265359
#endif

// SDF for a capsule with different radii at ends (Uneven Capsule)
// p: sampling point
// r1: radius at origin (y=0)
// r2: radius at height h (y=h)
// h: height of the segment on y-axis
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

void LocationPinShape_float(float2 UV, float Size, float Width, float Height, float4 Color, out float4 outColor) {
    // PLAN: Location Pin Shape (Rounded top, pointed bottom)
    // 1) Center and scale UV coordinates using Size.
    // 2) Validate dimensions: Height must be >= Width to maintain the pointed shape.
    // 3) Offset coordinates to vertically center the shape based on its total height.
    // 4) Compute SDF using an uneven capsule (tapered cone) with a rounded top and pointed bottom.
    // 5) Apply smoothstep anti-aliasing and output final color.

    // 1. Center and Scale
    float2 p = UV - 0.5;
    float s = max(Size, 0.001);
    p /= s;

    // 2. Setup Dimensions
    // Width determines the diameter of the circular head
    // Height is the total vertical extent from tip to top
    float w = max(Width, 0.001);
    
    // Enforce Height >= Width. 
    // A pin cannot be shorter than its width (radius > length) without breaking the cone math.
    float h = max(Height, w);
    
    float r = w * 0.5;          // Radius of the top circle
    float segmentLength = h - r; // Length of the tapered part (from tip to circle center)

    // 3. Center Vertically
    // The shape extends from y = -h/2 (tip) to y = h/2 (top of circle).
    // The uneven capsule primitive starts at (0,0) and goes up.
    // We shift p.y so the visual bottom (tip) aligns with the capsule origin.
    p.y += h * 0.5;

    // 4. Calculate SDF
    // Bottom radius (tip) is 0.0, Top radius (head) is r
    float dist = sdUnevenCapsule(p, 0.0, r, segmentLength);

    // 5. Anti-aliasing and Color
    // Use fwidth for resolution-independent smoothness
    float aa = max(fwidth(dist), 0.001);
    float edge = 1.0 - smoothstep(-aa, aa, dist);
    
    outColor = float4(Color.rgb * edge, edge);
}