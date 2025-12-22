/* 
  Dollar Sign SDF Shape
  - Generates a bold 'S' shape with a vertical bar.
  - Uses rotational symmetry for the S construction.
  - Supports dynamic Size and Thickness.
*/

#ifndef PI
#define PI 3.14159265359
#endif

void DollarSignShape_float(float2 UV, float Size, float Thickness, float4 Color, out float4 outColor) {
    // 1. Center and scale UVs
    // Map UV(0,1) to p(-1,1) centered, then scale by Size
    float2 center = float2(0.5, 0.5);
    float2 p = (UV - center) * 2.0;
    p /= max(Size, 0.0001);

    // 2. Vertical Bar SDF
    // A simple box extending vertically. 
    // Width matches the curve thickness (Thickness is half-width).
    // Height 1.1 covers the S shape (radius 0.5 + 0.5 vertical shift + extra).
    float2 dBarVec = abs(p) - float2(Thickness, 1.2);
    float dBar = length(max(dBarVec, 0.0)) + min(max(dBarVec.x, dBarVec.y), 0.0);

    // 3. S-Shape Construction
    // The S has 180-degree rotational symmetry.
    // We map the bottom half (y < 0) to the top half using p = -p.
    // This simplifies the SDF to drawing just the top hook of the S.
    float2 q = (p.y < 0.0) ? -p : p;

    // Top Hook Geometry:
    // A ring segment centered at (0, 0.5) with Radius 0.5.
    // Relative to this center, the arc starts at -90 deg (connecting to the other half)
    // and ends at +45 deg (the cap).
    float radius = 0.5;
    float2 c = float2(0.0, 0.5);
    float2 localP = q - c;
    
    // Base Ring SDF
    float dRing = abs(length(localP) - radius) - Thickness;

    // Angle-based Clipping (The "Gap")
    // We want to remove the ring in the sector between the connection (-90 deg) and the cap (+45 deg).
    // atan2 gives angle in range [-PI, PI].
    // -90 deg = -1.57 rad. +45 deg = 0.785 rad.
    // We add a small overlap (0.05) to the start angle to ensure a seamless weld at x=0.
    float angle = atan2(localP.y, localP.x);
    float gapStart = -1.57 + 0.02; // Start just after bottom (-90)
    float gapEnd = 0.785;          // End at top-right (+45)
    
    // If we are in the gap angle, push the distance to infinity (remove the shape)
    if (angle > gapStart && angle < gapEnd) {
        dRing = 1e5;
    }

    // Add a Rounded Cap at the gap end (+45 deg)
    // This restores the shape at the tip with a nice rounded end.
    float2 capDir = float2(cos(gapEnd), sin(gapEnd));
    float2 capPos = c + radius * capDir;
    float dCap = length(q - capPos) - Thickness;

    // Combine the clipped ring and the cap
    float dS = min(dRing, dCap);

    // 4. Final Combination (Union of Bar and S)
    float dist = min(dBar, dS);

    // 5. Anti-aliasing and Color Output
    // Use fwidth for pixel-perfect smoothing independent of scale
    float aa = fwidth(dist);
    float alpha = smoothstep(aa, -aa, dist);

    outColor = float4(Color.rgb * alpha, alpha);
}