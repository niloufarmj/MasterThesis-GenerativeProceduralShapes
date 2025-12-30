/* 
  User Request: An eight-pointed star with long sharp spikes. 
  Fixed 8 points, adjustable spike length (inner radius), rotation, and single fill color.
*/

#ifndef PI
#define PI 3.14159265359
#endif

// Helper: Signed Distance Field for an 8-pointed star
// p: centered UV coordinates
// rOuter: radius of the star tips
// rInner: radius of the star valleys
float sdStar8(float2 p, float rOuter, float rInner)
{
    // 8 points means 8 tips distributed over 2*PI
    // The fundamental sector angle is 2*PI / 8 = PI/4 (45 degrees)
    float angleStep = PI * 0.25;
    
    // 1. Angular Domain Repetition
    // Get angle of current point
    float a = atan2(p.y, p.x);
    
    // Map angle to the range [-angleStep/2, angleStep/2]
    // This effectively folds the space into 8 slices centered on each tip
    float sector = (frac((a / angleStep) + 0.5) - 0.5) * angleStep;
    
    // 2. Convert back to Cartesian in the folded sector
    // We use the length of the original vector and the new angle
    p = length(p) * float2(cos(sector), sin(sector));
    
    // 3. Apply symmetry along the tip axis (Y-mirror in the folded frame)
    // This reduces the problem to a single line segment edge
    p.y = abs(p.y);
    
    // 4. Define the star edge segment
    // The tip is on the X-axis at distance rOuter
    // The valley is at angle PI/8 (half sector) at distance rInner
    float valleyAngle = angleStep * 0.5;
    float2 pTip = float2(rOuter, 0.0);
    float2 pValley = float2(rInner * cos(valleyAngle), rInner * sin(valleyAngle));
    
    // 5. Compute distance to the segment (Tip -> Valley)
    float2 pa = p - pTip;
    float2 ba = pValley - pTip;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    float2 dVec = pa - ba * h;
    
    // 6. Determine sign (Inside vs Outside)
    // We use the 2D cross product to check which side of the edge the point lies
    // If the point is 'left' of the Tip->Valley vector, it is inside.
    float cp = (pValley.x - pTip.x) * (p.y - pTip.y) - (pValley.y - pTip.y) * (p.x - pTip.x);
    
    // SDF convention: Negative inside, Positive outside
    // With our vertex order, positive cross product implies inside.
    return length(dVec) * -sign(cp);
}

void StarEightPointed_float(float2 UV, float2 Center, float Size, float InnerRatio, float Rotation, float4 Color, out float4 outColor)
{
    // PLAN:
    // 1) Center the UV coordinates based on input Center.
    // 2) Apply rotation to the coordinate system.
    // 3) Calculate inner radius based on Size and InnerRatio.
    // 4) Compute Signed Distance Field (SDF) for the 8-pointed star.
    // 5) Apply smoothstep for anti-aliased edges.
    // 6) Output the final color with alpha transparency.

    // 1. Center and Rotate
    float2 p = UV - Center;
    
    // Apply Rotation (rotate point by -angle to rotate shape by +angle)
    float c = cos(Rotation);
    float s = sin(Rotation);
    p = float2(c * p.x + s * p.y, -s * p.x + c * p.y);
    
    // 2. Define Radii
    // Size controls the tip radius. InnerRatio controls the spike length.
    float rOuter = Size;
    float rInner = Size * InnerRatio;
    
    // 3. Calculate SDF
    float dist = sdStar8(p, rOuter, rInner);
    
    // 4. Anti-aliasing
    // Create a smooth mask based on the distance field
    // Inside (dist < 0) = 1, Outside (dist > 0) = 0
    // We use a small smoothing width (0.01) for nice edges
    float edge = smoothstep(0.01, -0.01, dist);
    
    // 5. Output Color
    // Multiply RGB by alpha mask, and set Alpha to mask
    outColor = float4(Color.rgb * edge, edge * Color.a);
}