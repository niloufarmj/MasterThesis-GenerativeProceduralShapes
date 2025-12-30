#ifndef PI
#define PI 3.14159265359
#endif

// Signed Distance Function for a 4-pointed star
// p: Point in generic space (centered)
// r: Outer radius (length of the main spikes)
// ratio: Inner radius factor (0.0 to 1.0). Controls sharpness.
//        Small value (e.g. 0.2) = sharp star. Value near 0.707 = square.
float sdStar4(float2 p, float r, float ratio) {
    // 1. Fold symmetry to the first quadrant
    p = abs(p);
    
    // 2. Fold symmetry to the octant (0 to 45 degrees)
    //    We ensure p.x >= p.y by swapping if needed
    if (p.x < p.y) p = p.yx;
    
    // 3. Define the star edge segment in this octant
    //    Outer vertex is on the X axis: (r, 0)
    //    Inner vertex is on the diagonal: (innerR * cos(45), innerR * sin(45))
    float rInner = r * ratio;
    float k = 0.70710678; // 1.0 / sqrt(2.0)
    float2 v1 = float2(r, 0.0);
    float2 v2 = float2(rInner * k, rInner * k);
    
    // 4. Compute signed distance to the segment v1-v2
    float2 e = v2 - v1; // Edge vector
    float2 w = p - v1;  // Vector from v1 to point p
    
    // Project w onto the edge e, clamping to the segment [0, 1]
    // Use a small epsilon to avoid division by zero if vertices overlap
    float edot = dot(e, e);
    float h = clamp(dot(w, e) / max(edot, 1e-6), 0.0, 1.0);
    
    // 'b' is the vector from the closest point on segment to p
    float2 b = w - e * h;
    float d = length(b);
    
    // 5. Determine the sign (negative inside, positive outside)
    //    We use the normal of the edge. For edge e=(ex, ey), 
    //    the outward normal is (ey, -ex) because we walk from outer to inner.
    //    Outer(r,0) -> Inner(x,x). e.x is negative, e.y is positive.
    //    So Normal is (+, +), pointing away from the origin.
    float2 n = float2(e.y, -e.x);
    
    return d * sign(dot(w, n));
}

void FourPointStar_float(float2 UV, float Size, float PointRatio, float4 Color, out float4 outColor) {
    // PLAN:
    // 1) Center the UV coordinates (0.5, 0.5 becomes 0,0).
    // 2) Calculate the Signed Distance Field (SDF) for the 4-pointed star.
    // 3) Use smoothstep for a clean, anti-aliased edge.
    // 4) Apply color and output.
    
    // 1. Center UVs
    float2 p = UV - 0.5;
    
    // 2. Calculate Star SDF
    // Ensure safe values for parameters
    float r = max(Size, 0.0);
    float ratio = clamp(PointRatio, 0.01, 0.99);
    float dist = sdStar4(p, r, ratio);
    
    // 3. Anti-aliasing
    // Use fwidth if available for perfect pixel-width AA, or a fixed value
    // Here we use a small fixed value for simplicity in preview, 
    // but fwidth(dist) is better for screenspace scaling.
    float aa = fwidth(dist);
    float alpha = 1.0 - smoothstep(-aa, aa, dist);
    
    // 4. Output Color
    // We premultiply alpha if desired, or just output mask in alpha.
    // Here we output straight alpha (RGB * 1, Alpha).
    outColor = float4(Color.rgb * alpha, alpha);
}