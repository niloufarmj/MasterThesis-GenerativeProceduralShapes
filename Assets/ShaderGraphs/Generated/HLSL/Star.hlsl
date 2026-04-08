#ifndef STAR_INCLUDED
#define STAR_INCLUDED

void Star_float(float2 UV, float2 Center, float Points, float InnerRadius, float OuterRadius, float Rotation, out float Out)
{
    // Remap UV to be centered around (0,0)
    float2 p = UV - Center;
    
    // Calculate angle and distance
    float angle = atan2(p.y, p.x) + Rotation;
    float dist = length(p);
    
    // Map angle to 0-1 range for one star point segment
    // Each point consists of two segments (up and down)
    float angleStep = 3.14159265359 / Points;
    
    // Modulo the angle to repeat the pattern
    // We add PI to angle to handle negative values from atan2 correctly in mod
    float currentAngle = fmod(angle + 3.14159265359, angleStep * 2.0);
    
    // Calculate the radius at the current angle
    // We want a value that oscillates between InnerRadius and OuterRadius
    // The pattern is symmetric within each point
    float segmentAngle = abs(currentAngle - angleStep);
    float t = segmentAngle / angleStep; // 0 at tip, 1 at valley
    
    // Linear interpolation for the star edge
    // You can use smoothstep or other functions for curved stars
    float currentRadius = lerp(OuterRadius, InnerRadius, t);
    
    // Generate the star shape
    // 1 if inside the star, 0 if outside
    // Using smoothstep for anti-aliasing if desired, but for hard edge:
    Out = 1.0 - step(currentRadius, dist);
}

#endif // STAR_INCLUDED
