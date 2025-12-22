#ifndef PI
#define PI 3.14159265359
#endif

void SunShape_float(float2 UV, float2 Center, float CoreRadius, float RayLength, float RayCount, float RaySharpness, float Rotation, float4 Color, out float4 outColor) {
    // PLAN:
    // 1. Center the coordinates based on input Center.
    // 2. Convert cartesian (x,y) to polar (radius, angle) coordinates.
    // 3. Create a repeating angular pattern (triangle wave) for the rays.
    // 4. Modulate the wave using a power function to control spike sharpness.
    // 5. Define the shape boundary by combining CoreRadius and the modulated rays.
    // 6. Compute Signed Distance Field (SDF) and apply anti-aliasing.

    // 1. Center UVs
    float2 p = UV - Center;
    
    // 2. Polar Coordinates
    float r = length(p);
    float a = atan2(p.y, p.x) - Rotation;
    
    // 3. Periodic Waveform for Rays
    // Normalize angle to [0,1] range and repeat by RayCount
    // We use floor() to ensure a whole number of rays (avoids seams)
    float rays = frac(a * floor(max(1.0, RayCount)) / (2.0 * PI));
    
    // Create a triangle wave from 0 -> 1 -> 0
    // abs(2*x - 1) creates a linear bounce
    float wave = abs(2.0 * rays - 1.0);
    
    // 4. Sharpness Modulation
    // Power function curves the linear triangle into a spike
    // Higher sharpness = thinner rays
    wave = pow(wave, max(0.1, RaySharpness));
    
    // 5. Calculate Shape Radius
    // The radius varies from CoreRadius (at valleys) to CoreRadius + RayLength (at peaks)
    float shapeRadius = CoreRadius + RayLength * wave;
    
    // 6. SDF and Output
    // dist < 0 inside the sun, dist > 0 outside
    float dist = r - shapeRadius;
    
    // Analytic Anti-Aliasing using fwidth (screen-space derivative)
    float aa = fwidth(dist);
    aa = max(aa, 0.001); // Safety clamp to prevent division by zero or super-sharp aliasing
    
    // Smoothstep creates a soft transition at the edge based on pixel size
    float alpha = 1.0 - smoothstep(-aa, aa, dist);
    
    // Final Color Output with Pre-multiplied Alpha logic
    outColor = float4(Color.rgb * alpha, alpha);
}