/* 
  PLAN:
  1. Center the UV coordinates based on the input Center.
  2. Apply 2D rotation to the centered coordinates.
  3. Compute the Astroid SDF (concave diamond) using the implicit equation: |x|^(2/3) + |y|^(2/3) = r^(2/3).
     This creates a 4-point star shape with inward-curved edges.
  4. Apply a gradient-based correction to approximate Euclidean distance for clean anti-aliasing.
  5. Use smoothstep to create a filled shape with soft edges.
  6. Output the final RGBA color.
*/

void SparkleStarShape_float(float2 UV, float2 Center, float2 Size, float Angle, float4 Color, out float4 outColor) {
    // 1. Center UV
    float2 p = UV - Center;
    
    // 2. Rotate
    float c = cos(Angle);
    float s = sin(Angle);
    p = float2(c * p.x - s * p.y, s * p.x + c * p.y);
    
    // 3. Astroid (Sparkle) SDF Setup
    // We use the implicit form (x/w)^(2/3) + (y/h)^(2/3) - 1 = 0
    p = abs(p);
    
    // Safe size to prevent division by zero
    float2 safeSize = max(Size, 0.001);
    
    // Normalized coordinates (q = p / Size)
    // Clamp to a small epsilon to avoid singularity at axis (where coordinate is 0)
    float2 q = max(p / safeSize, 0.0001);
    
    // Power 2/3 for the astroid curve
    // We calculate x^(2/3) and y^(2/3)
    float k = 2.0 / 3.0;
    float xk = pow(q.x, k);
    float yk = pow(q.y, k);
    
    // Implicit function value F. F < 0 inside, F > 0 outside.
    float F = xk + yk - 1.0;
    
    // 4. Distance Approximation
    // To get a usable SDF for anti-aliasing, we divide F by the magnitude of its gradient.
    // Gradient of F w.r.t p.x is: dF/dx = dF/dq * dq/dx
    // dF/dqx = k * q.x^(k-1)
    // dq/dx = 1/Size.x
    // |grad|^2 = (k/Size.x)^2 * q.x^(2k-2) + (k/Size.y)^2 * q.y^(2k-2)
    // Note: q^(2k-2) = q^(4/3 - 2) = q^(-2/3) = 1 / q^(2/3) = 1 / xk
    
    float gx = k / safeSize.x;
    float gy = k / safeSize.y;
    
    // Gradient squared magnitude
    float g2 = (gx * gx) / xk + (gy * gy) / yk;
    
    // Approximate signed distance: F / |grad|
    // We use rsqrt (1/sqrt) for optimization
    float dist = F * rsqrt(g2);
    
    // 5. Anti-aliased edge
    // Dist is negative inside, positive outside. 
    // smoothstep(eps, -eps, dist) gives 1.0 inside, 0.0 outside.
    float edge = smoothstep(0.01, -0.01, dist);
    
    // 6. Output
    outColor = float4(Color.rgb * edge, edge);
}