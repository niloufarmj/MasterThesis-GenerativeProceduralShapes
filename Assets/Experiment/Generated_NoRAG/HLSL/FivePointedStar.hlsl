#ifndef PI
#define PI 3.14159265359
#endif

#ifndef TAU
#define TAU 6.28318530718
#endif

void FivePointedStar_float(float2 UV, float Size, float Rotation, float Sharpness, float4 Color, out float4 outColor)
{
    // user request: a five-pointed star with five equal pointed tips
    
    // PLAN:
    // 1. Center the UV coordinates and apply inverse rotation to the sampling point.
    // 2. Convert to polar coordinates (angle, radius).
    // 3. Create a periodic triangle wave based on the angle for 5 points.
    // 4. Use the wave to interpolate between an inner and outer radius, defining the star boundary.
    // 5. The pseudo-SDF is the pixel's radius minus the star's radius at that angle.
    // 6. Use smoothstep for anti-aliasing and output the final color.

    // 1. Center UVs and apply inverse rotation to the sampling point
    float2 p = UV - 0.5;
    float c = cos(Rotation);
    float s = sin(Rotation);
    p = float2(p.x * c + p.y * s, -p.x * s + p.y * c);

    // Define inner and outer radii from inputs
    // Size is diameter, so radius is half
    float r_out = Size * 0.5;
    float r_in = r_out * saturate(Sharpness);

    // 2. Convert to polar coordinates
    float angle = atan2(p.y, p.x);
    float r = length(p);

    // 3. Create triangle wave for 5 points
    // Map angle to a 0-5 range. Add 0.25 offset to make the star point upwards at 0 rotation.
    float a = frac(angle * (5.0 / TAU) + 0.25);
    // Create a 0->1->0 triangle wave from the 0->1 ramp for sharp tips
    float triangle_wave = 1.0 - abs(a * 2.0 - 1.0);
    
    // 4. Interpolate radius to find the star's boundary at this angle
    float star_radius = lerp(r_in, r_out, triangle_wave);

    // 5. Calculate pseudo-SDF (distance from point to the boundary)
    float dist = r - star_radius;
    
    // 6. Anti-aliasing and final color
    float mask = smoothstep(0.01, -0.01, dist);
    
    outColor = float4(Color.rgb * mask, mask);
}