/*
  Cracker Shape Function
  Generates a square 'cracker' shape with scalloped/wavy edges and a grid of docking holes.
  - Wavy Body: Defined by a box SDF modulated by sine waves along the perimeter.
  - Docking Holes: A grid of circular cutouts computed via UV domain repetition.
  - Style: Flat 2D with adjustable fill, stroke, and dimensions.
*/

void CrackerShape_float(float2 UV, float Size, float WaveFreq, float WaveAmp, float Rows, float Cols, float HoleSize, float Rotation, float4 FillColor, float4 StrokeColor, float StrokeWidth, out float4 outColor) {
    // PLAN:
    // 1) Center and rotate UVs.
    // 2) Compute Box SDF with sine-wave modulation on edges.
    // 3) Compute Grid Hole SDF using domain mapping.
    // 4) Combine using subtraction (max(box, -hole)).
    // 5) Render fill and stroke with AA.

    // 1. Setup coordinates (Center 0,0)
    float2 p = UV - 0.5;
    
    // Apply Rotation
    float rad = Rotation;
    float c = cos(rad);
    float s = sin(rad);
    p = float2(c * p.x - s * p.y, s * p.x + c * p.y);
    
    // 2. Body SDF (Wavy Box)
    // Modulate the distance to the edge using a sine wave of the perpendicular axis
    // This creates the scalloped edge effect along the square sides
    float waveX = sin(p.y * WaveFreq) * WaveAmp;
    float waveY = sin(p.x * WaveFreq) * WaveAmp;
    
    // Box SDF: max(abs(x), abs(y)) - size
    // We add the wave perturbation to the absolute coordinate to wiggle the boundary
    float dBody = max(abs(p.x) + waveY, abs(p.y) + waveX) - Size;
    
    // 3. Holes SDF (Grid of Circles)
    // Define a grid area that covers ~80% of the cracker to keep holes centered
    float2 gridSpan = float2(Size, Size) * 1.6;
    // Map position to 0..1 range within this span
    float2 normUV = (p / gridSpan) + 0.5;
    
    // Determine grid dimensions (ensure at least 1x1)
    float2 gridCount = float2(max(1.0, floor(Cols)), max(1.0, floor(Rows)));
    
    // Identify cell ID and local cell UV centered at 0
    float2 cellID = floor(normUV * gridCount);
    float2 cellUV = frac(normUV * gridCount) - 0.5;
    
    // Convert local cell UV back to world units for correct sizing
    float2 cellP = cellUV / gridCount * gridSpan;
    float dHoles = length(cellP) - HoleSize;
    
    // Mask holes: Only valid if cellID is within [0, count-1]
    // If outside grid, set dHoles to high positive value (solid/non-hole)
    float insideGrid = step(0.0, cellID.x) * step(cellID.x, gridCount.x - 0.9) *
                       step(0.0, cellID.y) * step(cellID.y, gridCount.y - 0.9);
                       
    dHoles = lerp(10.0, dHoles, insideGrid);
    
    // 4. Combine Shapes
    // Subtract holes from body: max(dBody, -dHoles)
    float dFinal = max(dBody, -dHoles);
    
    // 5. Render with Anti-Aliasing
    // Use fwidth for pixel-perfect AA, with a fallback epsilon
    float aa = length(float2(ddx(dFinal), ddy(dFinal))) * 0.7071 + 1e-4;
    
    // Fill Alpha (Inside shape)
    float alpha = 1.0 - smoothstep(-aa, aa, dFinal);
    float4 fill = float4(FillColor.rgb, FillColor.a * alpha);
    
    // Stroke Alpha (Boundary band)
    float halfStroke = StrokeWidth * 0.5;
    float strokeAlpha = smoothstep(halfStroke + aa, halfStroke - aa, abs(dFinal));
    float4 stroke = float4(StrokeColor.rgb, StrokeColor.a * strokeAlpha);
    
    // Composite: Stroke OVER Fill
    // Standard Porter-Duff 'Over' operator
    float outA = stroke.a + fill.a * (1.0 - stroke.a);
    float3 outRGB = (stroke.rgb * stroke.a + fill.rgb * fill.a * (1.0 - stroke.a)) / max(outA, 1e-4);
    
    outColor = float4(outRGB, outA);
}