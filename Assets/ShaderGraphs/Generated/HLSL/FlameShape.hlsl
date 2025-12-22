/*
  PLAN:
  1. Center UV coordinates at the given Center position.
  2. Normalize coordinates by Size to create a radius-based distance field.
  3. Apply a vertical offset to position the flame's wide base relative to the center.
  4. Apply a non-uniform scaling (tapering) to the X-axis based on the Y-height.
     - Lower part (y < 0) remains spherical (multiplier ~ 1.0).
     - Upper part (y > 0) becomes narrower (multiplier > 1.0) to form a tip.
  5. Compute Signed Distance Field (SDF) and restore global scale.
  6. Apply smoothstep for antialiasing/softness and output final color.
*/

void FlameShape_float(float2 UV, float2 Center, float Size, float Smoothness, float4 Color, out float4 outColor) {
    // 1. Center and Scale
    float2 p = UV - Center;
    
    // Avoid division by zero
    float radius = max(Size, 0.0001);
    
    // Normalize space: q is in units of "radii"
    float2 q = p / radius;
    
    // 2. Shape Distortion
    // Shift y up so the coordinate origin (center of the bulb) is lower,
    // making the flame sit nicely relative to the pivot.
    q.y += 0.3;
    
    // Tapering logic: 
    // We modify the X coordinate's contribution to the distance.
    // max(0.0, q.y) ensures the bottom (negative y) stays round like a circle,
    // while the top (positive y) gets compressed effectively (x * big_val).
    float taper = 1.0 + max(0.0, q.y * 1.5);
    
    // 3. Distance Calculation
    // anisotropic length calculation defines the implicit shape
    // length(...) - 1.0 gives a distance field where 0 is the surface.
    float dist_norm = length(float2(q.x * taper, q.y)) - 1.0;
    
    // Convert back to world units for correct AA width
    float dist = dist_norm * radius;
    
    // 4. Rendering
    // Calculate edge softness: intrinsic AA (fwidth) + user Smoothness
    float edgeWidth = max(fwidth(dist), Smoothness);
    
    // Smoothstep for alpha mask
    // dist < 0 is inside the shape. 
    // We map [-edge, edge] to [1, 0] for opacity.
    float alpha = smoothstep(edgeWidth, -edgeWidth, dist);
    
    // Output
    outColor = float4(Color.rgb * alpha, alpha);
}