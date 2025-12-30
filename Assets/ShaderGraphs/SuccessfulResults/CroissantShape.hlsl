#ifndef PI
#define PI 3.14159265359
#endif

void CroissantShape_float(float2 UV, float Thickness, float Curvature, float Length, float Segments, float RidgeDepth, float4 Color, out float4 outColor) {
    // PLAN:
    // 1. Center UVs and define the "Bend" geometry (Pivot point and Radius).
    // 2. Map Cartesian UVs to Polar coordinates relative to the pivot.
    // 3. Project the polar angle onto the arc segment (clamped to Length).
    // 4. Compute distance to the arc spine (SDF base).
    // 5. Modulate the shape's thickness along the arc:
    //    - Taper the ends to zero (elliptical profile) to form pointy tips.
    //    - Add sine-wave ridges for the "segmented" look.
    // 6. Subtract modulated thickness from spine distance to get final SDF.
    // 7. Anti-alias and output color.

    // 1. Setup Coordinates and Curvature
    float2 p = UV - 0.5;

    // Clamp curvature to avoid division by zero. 
    // Higher curvature = tighter bend = smaller radius.
    float k = max(0.05, abs(Curvature));
    float rBend = 1.0 / k;

    // Pivot is placed such that the spine passes through (0,0) (the center of the UV space).
    // We define the shape as an upward curve ("U" shape), so pivot is below.
    float2 pivot = float2(0.0, -rBend);
    
    // 2. Polar Coordinates relative to Pivot
    float2 q = p - pivot;
    // Angle 'a' is 0 along the Y-axis (straight up relative to pivot)
    float a = atan2(q.x, q.y);
    
    // 3. Arc Projection
    // Limit the angle to the arc's extent [-Length/2, Length/2]
    // This defines the "spine" of the croissant.
    float halfArc = Length * 0.5;
    float t = clamp(a, -halfArc, halfArc);
    
    // 4. Distance to Spine
    // Calculate the position of the closest point on the central arc
    float sinT, cosT;
    sincos(t, sinT, cosT);
    float2 spinePos = pivot + float2(sinT, cosT) * rBend;
    
    // Euclidean distance from the current pixel to the spine
    float dist = length(p - spinePos);
    
    // 5. Thickness Modulation
    // Calculate normalized position along the arc: -1 (left tip) to 1 (right tip)
    float tNorm = t / halfArc;
    
    // Tapering: Standard elliptical taper creates the crescent shape.
    // 1.0 at center, 0.0 at tips.
    float taper = sqrt(max(0.0, 1.0 - tNorm * tNorm));
    
    // Ridges: Create bumps based on the angle to simulate segments.
    // We oscillate based on the normalized angle scaled by segment count.
    float ridgePhase = tNorm * Segments * PI;
    float ridges = cos(ridgePhase);
    
    // Calculate final radius at this point on the spine.
    // Base thickness is tapered at ends, then modulated by ridges.
    float shapeRadius = Thickness * taper * (1.0 + RidgeDepth * ridges);
    
    // 6. Final SDF
    // Signed distance: positive outside, negative inside
    float sdf = dist - shapeRadius;
    
    // 7. Rendering
    // Analytic anti-aliasing using fwidth
    float aa = fwidth(sdf);
    float mask = 1.0 - smoothstep(-aa, aa, sdf);
    
    // Output final color
    outColor = float4(Color.rgb * mask, mask);
}