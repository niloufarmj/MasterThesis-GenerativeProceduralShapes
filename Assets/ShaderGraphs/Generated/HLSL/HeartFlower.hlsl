#ifndef PI
#define PI 3.14159265359
#endif

// PLAN:
// 1) Define SDF helper for a heart shape.
// 2) Center and rotate the UV coordinates.
// 3) Compute SDF for the central round disk.
// 4) Compute SDF for petals using polar domain repetition.
//    - Divide space into N sectors.
//    - Rotate local sector space so X axis is radial.
//    - Shift by CenterRadius to attach petal.
//    - Apply non-uniform scaling for Width/Length.
//    - Evaluate Heart SDF.
// 5) Create anti-aliased masks for center and petals.
// 6) Composite Center OVER Petals.

// Helper: Squared length
float dot2(float2 v) {
    return dot(v, v);
}

// Helper: Signed Distance to a Heart shape
// Returns negative inside, positive outside.
// Adapted from Inigo Quilez. Tip is at (0,0), lobes point roughly +Y.
float sdHeart(float2 p) {
    p.x = abs(p.x);
    if (p.y + p.x > 1.0)
        p = float2(p.y, -p.x) + 1.0;
    return sqrt(dot2(p - float2(0.25, 0.75))) - 0.35355339; // 0.353... is sqrt(2)/4
}

void HeartFlower_float(float2 UV, float CenterRadius, float PetalCount, float PetalLength, float PetalWidth, float4 CenterColor, float4 PetalColor, float Rotation, out float4 outColor) {
    // 1. Center and Rotate UV
    float2 p = UV - 0.5;
    
    // Apply global rotation
    float cr = cos(Rotation);
    float sr = sin(Rotation);
    p = float2(cr * p.x - sr * p.y, sr * p.x + cr * p.y);
    
    // 2. SDF for Center Disk
    float dCenter = length(p) - CenterRadius;
    
    // 3. SDF for Petals (Polar Domain Repetition)
    // Calculate polar angle and radius
    float a = atan2(p.y, p.x);
    
    // Define angular sector size
    float N = max(3.0, PetalCount); // Ensure at least 3 petals
    float sectorSize = 2.0 * PI / N;
    
    // Determine which sector we are in (id) and the center angle of that sector
    float id = floor((a / sectorSize) + 0.5);
    float sectorAngle = id * sectorSize;
    
    // Rotate p into the local coordinate frame of the sector
    // We rotate by -sectorAngle so the sector center aligns with the +X axis
    float cs = cos(-sectorAngle);
    float ss = sin(-sectorAngle);
    float2 pLocal = float2(cs * p.x - ss * p.y, ss * p.x + cs * p.y);
    
    // Shift outward by center radius so petal attaches to disk
    pLocal.x -= CenterRadius;
    
    // The Heart SDF is defined with Y as the "up" axis (lobes up, tip down at 0,0).
    // Our radial direction is X. We map X -> Y (Length) and Y -> X (Width).
    float2 pPetal = float2(pLocal.y, pLocal.x);
    
    // Apply dimensions (Scale)
    // Avoid division by zero
    float w = max(0.001, PetalWidth);
    float l = max(0.001, PetalLength);
    pPetal.x /= w;
    pPetal.y /= l;
    
    // Calculate Heart SDF
    // Multiply by min scale to correct distance field roughly for AA
    float dPetal = sdHeart(pPetal) * min(w, l);
    
    // 4. Anti-aliasing masks
    // fwidth gives a good estimate for pixel-perfect AA width
    float aa = fwidth(length(p));
    // Ensure a minimum softness if fwidth is too small (e.g. far away)
    aa = max(aa, 0.001);
    
    float maskCenter = smoothstep(aa, -aa, dCenter);
    float maskPetal = smoothstep(aa, -aa, dPetal);
    
    // 5. Composite Colors (Center OVER Petals)
    // We treat the inputs as Premultiplied Alpha layers roughly
    float4 layerPetal = float4(PetalColor.rgb, 1.0) * maskPetal * PetalColor.a;
    float4 layerCenter = float4(CenterColor.rgb, 1.0) * maskCenter * CenterColor.a;
    
    // Standard Over operator: Output = Src + Dst * (1 - SrcAlpha)
    float4 finalCol = layerCenter + layerPetal * (1.0 - layerCenter.a);
    
    outColor = finalCol;
}