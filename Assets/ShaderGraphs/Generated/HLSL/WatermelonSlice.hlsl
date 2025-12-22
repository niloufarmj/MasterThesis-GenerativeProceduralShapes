/* 
  Watermelon Slice Shape
  Description: A procedural watermelon slice (semicircle/wedge) with adjustable rind, flesh, and visible seeds.
  Plan:
  1. Define helpers (sdEllipseApprox, rotate).
  2. Center and rotate UV coordinates.
  3. Calculate the main body SDF using an Ellipse intersected with a half-plane (for the slice look).
  4. Calculate Rind vs Flesh masks based on the body distance.
  5. Calculate Seed SDF by placing small ellipses in an arc within the flesh.
  6. Composite Rind, Flesh, and Seeds into final color.
  7. Apply anti-aliasing to edges.
*/

#ifndef PI
#define PI 3.14159265359
#endif

// Signed pseudo-distance to an axis-aligned ellipse
inline float sdEllipseApprox(float2 p, float2 halfAxes) {
    float a = max(halfAxes.x, 1e-8);
    float b = max(halfAxes.y, 1e-8);
    float aa = a * a;
    float bb = b * b;
    float x = p.x, y = p.y;
    float F = (x * x) / aa + (y * y) / bb - 1.0;
    float gradLen = 2.0 * sqrt((x * x) / (aa * aa) + (y * y) / (bb * bb));
    return (gradLen > 1e-8) ? (F / gradLen) : -min(a, b);
}

// 2D Rotation helper
inline float2 rotate(float2 p, float angle) {
    float c = cos(angle);
    float s = sin(angle);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

void WatermelonSlice_float(float2 UV, float2 Center, float Size, float2 Dimensions, float RindThickness, float SeedSize, float Rotation, float4 FleshColor, float4 RindColor, float4 SeedColor, out float4 outColor) {
    // 1. Coordinate setup
    float2 p = UV - Center;
    p = rotate(p, -Rotation);
    
    // 2. Main Body SDF (Semicircle / Sliced Ellipse)
    // We use an ellipse for proportions, cut by y > 0 plane (keeping y < 0)
    // Dimensions.x controls width, Dimensions.y controls height
    float2 halfAxes = Size * Dimensions;
    float dEllipse = sdEllipseApprox(p, halfAxes);
    
    // Intersection: Ellipse AND Lower Half Plane (p.y < 0)
    // Note: p.y > 0 is 'outside' the half-plane y<0, so we use max(d, p.y)
    // Adding a slight offset to p.y allows for exactly half or slightly more/less
    float dMain = max(dEllipse, p.y * 1.5); // *1.5 sharpens the cut plane gradient
    
    // 3. Analytic Anti-Aliasing Width
    float aa = fwidth(dMain) * 1.5;
    float alpha = 1.0 - smoothstep(-aa, aa, dMain);
    
    // 4. Layers (Rind vs Flesh)
    // Rind is the outer shell. Flesh is inside.
    // We use the distance field: -RindThickness is the boundary.
    // Ideally we want a small transition for the white part of the rind.
    float rindBoundary = -max(RindThickness, 0.01);
    float fleshMask = smoothstep(rindBoundary, rindBoundary - 0.02, dMain);
    
    // Add a thin white band between green rind and red flesh
    float whiteMask = smoothstep(rindBoundary + 0.02, rindBoundary, dMain) - fleshMask;
    float4 whiteColor = float4(0.9, 1.0, 0.9, 1.0);
    
    // Base color mix: Rind -> White -> Flesh
    float4 baseColor = lerp(RindColor, whiteColor, whiteMask);
    baseColor = lerp(baseColor, FleshColor, fleshMask);
    
    // 5. Seeds
    // Place 5 seeds in an arc inside the flesh
    float dSeeds = 100.0;
    float seedRad = SeedSize;
    
    // Seed Arc Radius: slightly less than the flesh boundary
    float arcRadiusX = halfAxes.x - RindThickness - 0.05;
    float arcRadiusY = halfAxes.y - RindThickness - 0.05;
    
    // Loop for 5 seeds
    for(int i = 0; i < 5; i++) {
        // Spread angles from approx -PI to 0 (the bottom semicircle)
        // We use a subset like -PI*0.8 to -PI*0.2 to avoid edges
        float t = float(i) / 4.0; // 0 to 1
        float angle = lerp(-PI * 0.85, -PI * 0.15, t);
        
        float2 seedPos = float2(cos(angle) * arcRadiusX, sin(angle) * arcRadiusY);
        // Rotate seed orientation to point outward from center
        float2 localP = p - seedPos;
        localP = rotate(localP, -angle - PI * 0.5);
        
        // Seed shape (teardrop-ish ellipse)
        float dSeedPart = sdEllipseApprox(localP, float2(seedRad * 0.6, seedRad));
        dSeeds = min(dSeeds, dSeedPart);
    }
    
    // Seed masking
    float seedEdge = smoothstep(0.005, -0.005, dSeeds);
    // Only show seeds inside the flesh part
    seedEdge *= fleshMask;
    
    // 6. Final Composite
    // Mix base color with seed color
    float4 finalRGB = lerp(baseColor, SeedColor, seedEdge);
    
    // Apply shape alpha
    outColor = float4(finalRGB.rgb * alpha, alpha);
}