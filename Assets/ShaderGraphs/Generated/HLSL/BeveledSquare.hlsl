#ifndef PI
#define PI 3.14159265359
#endif

// Helper for straight-alpha composition (Source Over Destination)
inline float4 beveled_square_over(float4 src, float4 dst) {
    float a = src.a + dst.a * (1.0 - src.a);
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-8);
    return float4(c, a);
}

void BeveledSquare_float(float2 UV, float Size, float BevelSize, float Rotation, float4 FillColor, float4 StrokeColor, float StrokeWidth, out float4 outColor) {
    // PLAN:
    // 1) Center UVs to (0,0) and handle rotation.
    // 2) Apply symmetry to reduce problem to 1st quadrant.
    // 3) Calculate Box SDF (vertical/horizontal bounds).
    // 4) Calculate Bevel SDF (diagonal cutting plane).
    // 5) Combine using max() for intersection.
    // 6) Compute anti-aliased fill and stroke masks.
    // 7) Composite stroke over fill.

    // 1. Coordinates
    float2 p = UV - 0.5;
    
    // 2. Rotation
    float c = cos(Rotation);
    float s = sin(Rotation);
    p = float2(c * p.x + s * p.y, -s * p.x + c * p.y);
    
    // 3. Symmetry (abs)
    p = abs(p);
    
    // 4. SDF Calculation
    // dBox: Distance to standard square edges
    float dBox = max(p.x, p.y) - Size;
    
    // dBevel: Distance to the chamfer/cut plane
    // The cut line connects (Size-Bevel, Size) and (Size, Size-Bevel)
    // Equation: x + y = 2*Size - Bevel
    // Normal: (1,1)/sqrt(2)
    float validBevel = min(BevelSize, Size); // Clamp to prevent inversion
    float dBevel = (p.x + p.y - (2.0 * Size - validBevel)) * 0.70710678;
    
    // Intersection of Box and Chamfer Plane
    float dist = max(dBox, dBevel);
    
    // 5. Anti-aliasing
    // Use fwidth for pixel-perfect edges, fallback to 0.001 if derivatives are zero
    float aa = fwidth(dist);
    aa = max(aa, 0.0001);

    // 6. Masks
    // Fill: 1.0 inside, 0.0 outside
    float fillMask = smoothstep(aa, -aa, dist);
    
    // Stroke: Band around the zero-distance isoline
    float halfStroke = max(StrokeWidth, 0.0) * 0.5;
    float strokeDist = abs(dist) - halfStroke;
    float strokeMask = smoothstep(aa, -aa, strokeDist);
    
    // 7. Composition
    float4 fill = float4(FillColor.rgb, FillColor.a * fillMask);
    float4 stroke = float4(StrokeColor.rgb, StrokeColor.a * strokeMask);
    
    outColor = beveled_square_over(stroke, fill);
}