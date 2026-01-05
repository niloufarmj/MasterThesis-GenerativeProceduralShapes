/*
  PLAN:
  1. Center the UV coordinates (0.5, 0.5).
  2. Apply 2D rotation.
  3. Define the S shape using a piecewise sine wave function x = -A * sin(ky).
     - Top half (y > 0) and Bottom half (y < 0) are handled separately to allow
       Vertical Balance adjustments (stretching/squashing top vs bottom).
  4. Ensure C1 continuity (smooth join) at y=0 by scaling Amplitude proportionally to Height.
  5. Compute signed distance to the sine curve using the gradient normalization trick:
     dist = |x - f(y)| / sqrt(1 + f'(y)^2).
  6. Clip the shape vertically with a soft box to create the S terminals.
  7. Subtract Thickness to create the stroke.
  8. Apply smoothstep for anti-aliasing and output color.
*/

#ifndef PI
#define PI 3.14159265359
#endif

void LetterSShape_float(float2 UV, float Size, float Tightness, float Thickness, float VerticalBalance, float Rotation, float4 Color, out float4 outColor) {
    // 1. Center UV coordinates
    float2 p = UV - 0.5;
    
    // 2. Rotation
    float rad = Rotation;
    float c = cos(rad);
    float s = sin(rad);
    p = float2(c * p.x - s * p.y, s * p.x + c * p.y);
    
    // 3. Vertical Balance Logic
    // Determine height of top and bottom lobes based on balance (0.5 = equal)
    // We clamp balance slightly to prevent zero-height errors.
    float bal = clamp(VerticalBalance, 0.01, 0.99);
    float totalH = max(Size, 0.001); // Half-height reference effectively
    
    // Split total vertical space (2 * Size) according to balance
    // topH + botH = 2.0 * Size
    float topH = totalH * bal * 2.0;
    float botH = totalH * (1.0 - bal) * 2.0;
    
    // Check which lobe we are in
    bool isTop = p.y > 0.0;
    float currentH = isTop ? topH : botH;
    
    // 4. Sine Wave Geometry
    // To form an 'S', we need roughly a PI phase range for each lobe.
    // We use slightly more (1.1 * PI) to make the tips curl inward a bit.
    float phaseLimit = PI * 1.05;
    float freq = phaseLimit / currentH;
    float theta = p.y * freq;
    
    // Amplitude must scale with height to keep the derivative at y=0 continuous.
    // Tightness controls the Width-to-Height ratio of the lobes.
    float amp = Tightness * currentH;
    
    // Curve Function: x = -amp * sin(theta)
    // y>0 -> theta>0 -> sin>0 -> x is negative (Left Bulge)
    // y<0 -> theta<0 -> sin<0 -> x is positive (Right Bulge)
    // This creates the standard S curvature.
    float xVal = -amp * sin(theta);
    
    // 5. Gradient Normalization for accurate thickness
    // Derivative dx/dy = -amp * cos(theta) * freq
    float dxdy = -amp * cos(theta) * freq;
    float gradLen = sqrt(1.0 + dxdy * dxdy);
    
    // Approx Euclidean distance to the curve
    float dCurve = abs(p.x - xVal) / gradLen;
    
    // 6. Vertical Clipping (Caps)
    // Cut the sine wave before it loops back. We clip at 90% of the calculated height
    // to ensure we stop at the nice terminals.
    float yClipTop = topH * 0.9;
    float yClipBot = -botH * 0.9;
    // dClip is positive if we are vertically outside the valid S range
    float dClip = max(p.y - yClipTop, yClipBot - p.y);
    
    // Combine curve distance and vertical clip (Intersection)
    float dSDF = max(dCurve, dClip);
    
    // 7. Apply Thickness (Stroke)
    // Subtract thickness to expand the zero-thickness curve into a stroke
    float dFinal = dSDF - Thickness;
    
    // 8. Anti-aliasing and Output
    float edge = smoothstep(0.005, -0.005, dFinal);
    outColor = float4(Color.rgb * edge, edge);
}