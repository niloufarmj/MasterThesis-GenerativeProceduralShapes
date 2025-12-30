#ifndef PI
#define PI 3.14159265359
#endif

void CartoonCracker_float(float2 UV, float Size, float WaveCount, float WaveDepth, float HoleRows, float HoleCols, float HoleSize, float4 BodyColor, float4 StrokeColor, float StrokeWidth, float Rotation, out float4 outColor) {
    // PLAN:
    // 1) Center UVs and apply rotation to get local coordinate 'p'.
    // 2) Calculate Body SDF using a Box SDF modulated by sine waves along edges.
    // 3) Calculate Holes SDF using domain repetition (grid) limited to Rows/Cols.
    // 4) Combine SDFs using Difference (max(body, -holes)) to punch holes.
    // 5) Compute Anti-Aliasing (AA) and Stroke using SDF distance.
    // 6) Composite Body and Stroke colors.

    // 1) Coordinates
    float2 center = float2(0.5, 0.5);
    float2 p = (UV - center);
    
    // Rotation
    float c = cos(Rotation);
    float s = sin(Rotation);
    p = float2(p.x * c - p.y * s, p.x * s + p.y * c);

    // 2) Body SDF (Scalloped Square)
    // Base box distance (L-infinity norm)
    float2 q = abs(p);
    // Determine which edge we are closest to for wave modulation
    // If closer to vertical edge (q.x > q.y), use y coord, otherwise x.
    float edgeCoord = (q.x > q.y) ? p.y : p.x;
    
    // Wave calculation: cos(coord * freq) * amp
    // Frequency scales so WaveCount fits along the side length (Size * 2)
    // Note: Use abs(edgeCoord) or just edgeCoord? Symmetric waves usually imply symmetry around 0.
    // Using edgeCoord directly ensures the wave pattern continues seamlessly if WaveCount is odd/even correctly.
    float freq = (max(WaveCount, 1.0) * PI) / max(Size, 0.001);
    float wave = WaveDepth * cos(edgeCoord * freq);
    
    // SDF: Box minus wave offset (pulls edge in/out)
    // We add 'wave' to the distance. If wave is positive (hill), distance increases (moves boundary in).
    // If wave is negative (valley), distance decreases (moves boundary out).
    // Usually 'scalloped' means protruding bumps, so we subtract wave?
    // Let's stick to d = box + wave for standard sine modulation.
    float d_box = max(q.x, q.y) - Size;
    float d_body = d_box + wave;

    // 3) Holes SDF (Grid)
    // Ensure valid grid dimensions
    float rows = max(round(HoleRows), 1.0);
    float cols = max(round(HoleCols), 1.0);
    
    // Calculate spacing to fit holes within the body size
    // Spacing = TotalLength / (Count + 1) for padding on sides
    float2 spacing = float2(Size * 2.0, Size * 2.0) / (float2(cols, rows) + 1.0);
    
    // Calculate offset to center the grid at (0,0)
    // Center of grid logic: (Count - 1) * spacing * 0.5
    float2 gridCenterOffset = (float2(cols, rows) - 1.0) * spacing * 0.5;
    
    // Relativize p to the grid starting corner (0,0 of grid)
    float2 p_rel = p + gridCenterOffset;
    
    // Find grid cell ID
    float2 id = round(p_rel / spacing);
    
    // Clamp ID to valid row/col range so holes don't repeat infinitely
    id = clamp(id, float2(0, 0), float2(cols - 1.0, rows - 1.0));
    
    // Local coordinates within the cell
    float2 p_local = p_rel - id * spacing;
    
    // Distance to hole
    float d_holes = length(p_local) - HoleSize;

    // 4) Combine SDFs
    // 'Cut' holes from body: max(body, -holes)
    // Inside body is negative. Inside hole is negative.
    // -holes is positive inside hole.
    // max(-body, +hole) -> if inside hole, result is positive (outside shape).
    float d_final = max(d_body, -d_holes);

    // 5) Rendering (AA and Stroke)
    float aa = fwidth(d_final);
    float halfStroke = StrokeWidth * 0.5;

    // Fill Mask: 1.0 inside shape, 0.0 outside
    // Smoothstep from 0 to -aa gives a smooth edge at 0
    float fillMask = smoothstep(0.0, -aa, d_final);

    // Stroke Mask: 1.0 on edge, 0.0 elsewhere
    // Absolute distance from 0 should be < halfStroke
    // Smoothstep transition around halfStroke
    float strokeMask = smoothstep(halfStroke + aa, halfStroke - aa, abs(d_final));

    // 6) Output Composition
    // We want the stroke to appear on top or blended at the edge.
    // Common technique: Lerp fill color to stroke color at the border.
    // Border factor: 1.0 at edge, 0.0 inside.
    // Let's define the border region explicitly.
    // Visual border is where abs(d) < halfStroke.
    
    float4 fillColor = BodyColor;
    float4 strokeColor = StrokeColor;
    
    // Composite alpha-blended stroke over fill
    // Or simplified: Area with stroke gets stroke color, inner area gets fill.
    // Let's use the 'strokeMask' to determine stroke coverage.
    // The 'fillMask' determines overall shape opacity (including stroke area?)
    // Wait, d_final > 0 is outside. So abs(d_final) < halfStroke covers both in and out.
    // We want the stroke to be part of the opaque shape.
    
    // Final Opacity (Alpha)
    // The shape extends to 'halfStroke' outside the zero-isoline due to stroke width.
    float shapeAlpha = smoothstep(halfStroke, halfStroke - aa, d_final);
    
    // Mix colors based on stroke mask (which is high at the boundary)
    // However, strokeMask assumes we are strictly on the line.
    // Let's simply mix: if (dist > -halfStroke) use stroke?
    // A clean way:
    float t = smoothstep(-halfStroke + aa, -halfStroke - aa, d_final); // 0 at border, 1 deep inside
    float4 finalColor = lerp(strokeColor, fillColor, t);
    
    outColor = float4(finalColor.rgb * shapeAlpha, shapeAlpha);
}