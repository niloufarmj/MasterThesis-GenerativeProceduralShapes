/* 
  Cross Shape (Plus Sign)
  User Request: A plus-shaped cross made from two rectangles with adjustable arm length and thickness.
*/

// SDF for an axis-aligned box centered at origin
// b = half extents (width/2, height/2)
float sdBox(float2 p, float2 b)
{
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

void CrossShape_float(float2 UV, float ArmLength, float ArmThickness, float2 Center, float4 Color, out float4 outColor) {
    // PLAN:
    // 1) Center the UV coordinates based on input Center.
    // 2) Define dimensions for the vertical and horizontal arms (boxes).
    // 3) Calculate SDF for both boxes.
    // 4) Combine them using min() (union operation).
    // 5) Apply anti-aliasing using smoothstep or fwidth.
    // 6) Output final color.

    // 1) Center UVs
    float2 p = UV - Center;

    // 2) Define Half-Extents
    // Vertical arm: width = Thickness, height = Length
    float2 verticalExtents = float2(ArmThickness, ArmLength) * 0.5;
    // Horizontal arm: width = Length, height = Thickness
    float2 horizontalExtents = float2(ArmLength, ArmThickness) * 0.5;

    // 3) Calculate SDFs
    float dVert = sdBox(p, verticalExtents);
    float dHorz = sdBox(p, horizontalExtents);

    // 4) Union (Cross shape)
    // Taking the minimum distance creates the union of the two shapes
    float dist = min(dVert, dHorz);

    // 5) Anti-aliasing
    // Using fwidth for view-dependent smoothing consistent with screen resolution
    float aa = fwidth(dist);
    // Shape mask: 1.0 inside, 0.0 outside, smoothed at edges
    float mask = 1.0 - smoothstep(0.0, aa, dist);

    // 6) Output Color
    // Apply mask to Alpha. RGB is kept solid to avoid dark fringes, or masked if desired.
    // Standard Transparent setup: RGB, Alpha * Mask
    outColor = float4(Color.rgb, Color.a * mask);
}