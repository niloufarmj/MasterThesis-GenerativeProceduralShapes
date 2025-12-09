#ifndef STAR_INCLUDED
#define STAR_INCLUDED

// Creates a star shape mask.
// UV: The input UV coordinates (usually connected to a UV node)
// Points: The number of points on the star (e.g. 5)
// InnerRadius: The radius of the inner vertices (0.0 to 1.0)
// OuterRadius: The radius of the outer vertices (0.0 to 1.0)
// Out: The resulting star mask (1.0 inside, 0.0 outside)
void Star_float(float2 UV, float Points, float InnerRadius, float OuterRadius, out float Out)
{
    // Center the UVs at (0.5, 0.5)
    float2 p = UV - 0.5;
    
    // Calculate angle and distance from center
    // Note: atan2(y, x) is standard, but we use x, y to rotate it to start pointing up/right appropriately if needed.
    // Here we use standard atan2(y, x).
    float angle = atan2(p.y, p.x) + 3.14159265359; // Shift to 0-2PI range
    float dist = length(p);
    
    float angleStep = 6.28318530718 / Points;
    float halfStep = angleStep * 0.5;
    
    // Repeat the angle domain to create the star segments
    // We shift by halfStep so the "point" (OuterRadius) aligns with the start of the repetition logic if we want
    // But let's align 0 angle to OuterRadius.
    // fmod(angle, angleStep) goes 0..angleStep.
    // We want the segment from 0 (Outer) to halfStep (Inner) and back.
    
    // Normalize angle to -halfStep to +halfStep relative to the nearest outer point
    float localAngle = fmod(angle + halfStep, angleStep) - halfStep;
    float theta = abs(localAngle); // 0 to halfStep
    
    // We are defining the edge between polar coordinates:
    // (OuterRadius, 0) and (InnerRadius, halfStep)
    
    // Polar form of a line segment:
    // r(theta) = (r1 * r2 * sin(theta2 - theta1)) / (r1 * sin(theta2 - theta) + r2 * sin(theta - theta1))
    // theta1 = 0, r1 = OuterRadius
    // theta2 = halfStep, r2 = InnerRadius
    
    float num = OuterRadius * InnerRadius * sin(halfStep);
    float den = OuterRadius * sin(halfStep - theta) + InnerRadius * sin(theta);
    
    // Avoid division by zero if radii are very small, though typically user provides valid radii
    float r = num / (den + 0.00001);
    
    // Create sharp edge
    Out = step(dist, r);
}

// Half precision version for mobile/optimization
void Star_half(half2 UV, half Points, half InnerRadius, half OuterRadius, out half Out)
{
    half2 p = UV - 0.5;
    half angle = atan2(p.y, p.x) + 3.14159265359;
    half dist = length(p);
    
    half angleStep = 6.28318530718 / Points;
    half halfStep = angleStep * 0.5;
    
    half localAngle = fmod(angle + halfStep, angleStep) - halfStep;
    half theta = abs(localAngle);
    
    half num = OuterRadius * InnerRadius * sin(halfStep);
    half den = OuterRadius * sin(halfStep - theta) + InnerRadius * sin(theta);
    
    half r = num / (den + 0.00001);
    
    Out = step(dist, r);
}

#endif

