#ifndef PI
#define PI 3.14159265359
#endif

// Description: A loading spinner with multiple dots arranged in a circle.
// The 'Loading' parameter drives the rotation of the filled color trail.
// Dots are procedural and infinite resolution.

void LoadingSpinner_float(float2 UV, float Loading, float Radius, float DotSize, float Count, float TrailLength, float4 EmptyColor, float4 FilledColor, out float4 outColor) {
    // PLAN:
    // 1) Center UV coordinates to (0,0) relative to the middle of the quad.
    // 2) Convert to polar coordinates to find the angle of the current pixel.
    // 3) Identify the nearest 'dot' index based on the pixel's angle.
    // 4) Calculate the center position of that nearest dot.
    // 5) Compute SDF distance from pixel to the dot's center.
    // 6) Calculate the 'phase' of the dot relative to the Loading value for the color trail.
    // 7) Mix colors and apply anti-aliasing.

    // 1) Center UV coordinates
    float2 p = UV - 0.5;

    // 2) Polar coordinates
    // We use atan2(x, y) so that 0 radians is at the TOP (0, 1), increasing Clockwise.
    // Standard atan2(y, x) would be 0 at Right, increasing Counter-Clockwise.
    float angle = atan2(p.x, p.y);

    // 3) Snap to nearest dot
    // Ensure Count is at least 1 to avoid division by zero
    float n = max(1.0, floor(Count));
    float sectorStep = 2.0 * PI / n;
    
    // Calculate the index of the dot closest to this pixel's angle
    float id = round(angle / sectorStep);
    float dotAngle = id * sectorStep;

    // 4) Position of the nearest dot
    // Note: sin/cos are swapped here because we treated 0 as Up (Y-axis) in step 2
    // x = sin(angle), y = cos(angle) corresponds to Clockwise from Top
    float2 dotPos = float2(sin(dotAngle), cos(dotAngle)) * Radius;

    // 5) Signed Distance Field (SDF) to the dot
    // Negative inside the dot, positive outside
    float dist = length(p - dotPos) - DotSize;

    // 6) Color Logic
    // Normalize dot angle to 0..1 range for easy comparison
    // frac() handles wrapping of angles correctly
    float normDotAngle = frac(dotAngle / (2.0 * PI));
    
    // Normalize loading value to 0..1
    float normLoading = frac(Loading);
    
    // Calculate 'diff' which represents how far this dot is 'behind' the loading head
    // The frac() ensures the difference wraps around the circle
    float diff = frac(normLoading - normDotAngle);
    
    // Calculate intensity based on TrailLength
    // 1.0 means fully filled (at the head), fading down to 0.0
    // smoothstep creates a smooth fade along the trail
    float trail = clamp(TrailLength, 0.001, 1.0);
    // We map diff [0 -> trail] to intensity [1 -> 0]
    float intensity = smoothstep(trail, 0.0, diff);

    // Interpolate between Empty and Filled color based on intensity
    float4 color = lerp(EmptyColor, FilledColor, intensity);

    // 7) Anti-aliasing and Output
    // Soften the edges of the dots
    float edge = smoothstep(0.01, -0.01, dist);

    // Apply mask to RGB and Alpha
    outColor = float4(color.rgb * edge, color.a * edge);
}