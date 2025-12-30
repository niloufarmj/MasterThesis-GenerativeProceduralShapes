/*
  User Request: A stylized flower with repeated petals in a circular pattern.
  - Adjustable number of petals, length, and width.
  - Separate colors for petals and center.
  - Center drawn on top of petals.
*/

#ifndef PI
#define PI 3.14159265359
#endif

// Helper: Approximate signed distance to an ellipse
// p: local coordinates
// halfAxes: half-width and half-height (radius X, radius Y)
// Source: Adapted from Inigo Quilez / Unity Library references
inline float sdEllipseApprox_Flower(float2 p, float2 halfAxes)
{
    float a = max(halfAxes.x, 1e-8);
    float b = max(halfAxes.y, 1e-8);
    float aa = a * a;
    float bb = b * b;
    
    float x = p.x;
    float y = p.y;
    float F = (x * x) / aa + (y * y) / bb - 1.0;
    
    float gradLen = 2.0 * sqrt((x * x) / (aa * aa) + (y * y) / (bb * bb));
    
    return (gradLen > 1e-8) ? (F / gradLen) : -min(a, b);
}

// Helper: Straight-alpha "src over dst" blending
inline float4 blendOver_Flower(float4 src, float4 dst)
{
    // src is top layer, dst is bottom layer
    float a = src.a + dst.a * (1.0 - src.a);
    // Compute straight RGB (un-premultiplied)
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-8);
    return float4(c, a);
}

void StylizedFlower_float(float2 UV, float PetalCount, float PetalLength, float PetalWidth, float CenterRadius, float Rotation, float4 PetalColor, float4 CenterColor, out float4 outColor)
{
    // PLAN:
    // 1) Center UVs to (0,0) and apply global Rotation.
    // 2) Calculate Petal SDF using polar domain repetition.
    //    - Repeat angle space into N sectors.
    //    - Check neighbor sectors to handle petal overlap gracefully.
    //    - Shape: Ellipse centered on the petal axis.
    // 3) Calculate Center SDF (simple Circle).
    // 4) Compute masks using smoothstep for AA.
    // 5) Composite Center color OVER Petal color OVER background.

    // 1. Center and Rotate Coordinates
    float2 p = UV - 0.5;
    
    // Convert rotation to radians if user provides degrees? 
    // Rule says: "For rotation: use cos/sin with angle in radians". Assuming input is radians.
    float cr = cos(Rotation);
    float sr = sin(Rotation);
    p = float2(cr * p.x - sr * p.y, sr * p.x + cr * p.y);

    // 2. Petals SDF (with neighbor checking for smooth overlap)
    float dPetals = 1e9;
    
    // Angular repetition setup
    float n = max(3.0, round(PetalCount)); // Ensure integer count >= 3
    float sectorAngle = (2.0 * PI) / n;
    
    // Get polar angle and radius
    float angle = atan2(p.y, p.x);
    // Determine which sector we are in (rounding gives index of closest center)
    float currentSectorID = floor(angle / sectorAngle + 0.5);
    
    // Loop through current and neighbor sectors to handle overlapping petals
    // (If PetalWidth is large, petals might cross sector boundaries)
    for (int i = -1; i <= 1; i++)
    {
        float k = currentSectorID + float(i);
        float sectorCenterAngle = k * sectorAngle;
        
        // Rotate p into the local frame of this specific petal sector
        // We align the sector center to the positive X axis
        float c = cos(sectorCenterAngle);
        float s = sin(sectorCenterAngle);
        float2 pLocal = float2(c * p.x + s * p.y, -s * p.x + c * p.y);
        
        // Define Petal Shape (Ellipse)
        // Pivot is at (0,0). Petal extends along +X.
        // Center of ellipse: x = PetalLength/2
        // Radii: x = PetalLength/2, y = PetalWidth/2
        float2 eSize = float2(PetalLength * 0.5, PetalWidth * 0.5);
        float2 eCenter = float2(PetalLength * 0.5, 0.0);
        
        float dist = sdEllipseApprox_Flower(pLocal - eCenter, eSize);
        dPetals = min(dPetals, dist);
    }
    
    // 3. Center Circle SDF
    float dCenter = length(p) - CenterRadius;
    
    // 4. Antialiasing (AA)
    // Calculate approximate pixel width for sharp but smooth edges
    float aa = fwidth(length(p));
    aa = max(aa, 0.001); // Prevent division by zero or too sharp edges
    
    // Generate Alpha Masks (0.0 = transparent, 1.0 = opaque)
    float petalMask = 1.0 - smoothstep(0.0, aa, dPetals);
    float centerMask = 1.0 - smoothstep(0.0, aa, dCenter);
    
    // 5. Coloring & Composition
    // Prepare layers (Straight RGB + Alpha)
    float4 layerPetal = float4(PetalColor.rgb, PetalColor.a * petalMask);
    float4 layerCenter = float4(CenterColor.rgb, CenterColor.a * centerMask);
    
    // Composite: Center OVER Petals
    // Background is assumed transparent (0,0,0,0) implied by the blend function start
    outColor = blendOver_Flower(layerCenter, layerPetal);
}