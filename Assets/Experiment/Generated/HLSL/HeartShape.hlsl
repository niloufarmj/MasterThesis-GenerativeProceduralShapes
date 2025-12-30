// User Request: A classic heart shape centered on the screen. Adjustable size, smooth edges, single fill color.

#ifndef PI
#define PI 3.14159265359
#endif

// --- Helper Functions ---

// Squared length of a vector
inline float dot2(float2 v) {
    return dot(v, v);
}

// Signed Distance Function for a Heart (Inigo Quilez)
// Returns negative inside, positive outside.
// The shape is defined roughly in the range x:[-1,1], y:[0,1] with the tip at (0,0)
inline float sdHeart(float2 p) {
    p.x = abs(p.x);

    if (p.y + p.x > 1.0)
        return sqrt(dot2(p - float2(0.25, 0.75))) - 0.35355339059; // sqrt(2)/4
    return sqrt(min(dot2(p - float2(0.00, 1.00)),
                    dot2(p - 0.5 * max(p.x + p.y, 0.0)))) * sign(p.x - p.y);
}

// --- Main Function ---
// PLAN:
// 1) Remap UV from [0,1] to centered [-1,1] space.
// 2) Scale coordinates by 'Size' to allow resizing.
// 3) Offset Y coordinate so the visual center of the heart aligns with UV center.
// 4) Compute SDF distance.
// 5) Apply smoothstep for clean anti-aliased edges.
// 6) Output final RGBA color.

void HeartShape_float(float2 UV, float Size, float4 Color, out float4 outColor) {
    // 1) Center UV coordinates to [-1, 1]
    float2 p = (UV - 0.5) * 2.0;
    
    // 2) Scale by Size (avoid division by zero)
    // A Size of 1.0 fills roughly the [-1,1] range
    float s = max(Size, 0.0001);
    p /= s;
    
    // 3) Offset Y to center the shape
    // The heart SDF sits roughly between y=0 (tip) and y=1 (lobes).
    // We shift p.y up by ~0.5 so that (0,0) in UV space maps to the center of the heart.
    p.y += 0.55;

    // 4) Calculate Signed Distance
    float dist = sdHeart(p);
    
    // Correct distance for scaling to maintain constant edge softness
    dist *= s;

    // 5) Anti-aliasing
    // Use fwidth for automatic edge width based on screen resolution
    float aa = fwidth(dist);
    // SDF is negative inside, so we use smoothstep to create a mask where inside = 1
    float mask = 1.0 - smoothstep(-aa, aa, dist);

    // 6) Output
    // Apply mask to both RGB and Alpha for premultiplied-like blending or straight alpha usage
    outColor = float4(Color.rgb * mask, mask);
}