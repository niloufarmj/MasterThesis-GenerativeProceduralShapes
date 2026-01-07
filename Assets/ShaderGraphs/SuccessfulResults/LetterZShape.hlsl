/*
PLAN:
1. Define constants and helpers (sdBox, rotate).
2. Center UVs based on input Center parameter.
3. Calculate dimensions for the Z shape based on Size.
4. Construct the Z from 3 parts: Top Bar, Bottom Bar, Diagonal.
   - Top/Bottom are axis-aligned boxes.
   - Diagonal is a rotated box connecting the corners.
5. Adjust thickness to account for corner radius (subtract radius from box size, subtract radius from SDF).
6. Combine parts using min() for union.
7. Compute fill and outline masks using smoothstep and SDF distance.
8. Composite Fill over Outline and output final color.
*/

#ifndef PI
#define PI 3.14159265359
#endif

// SDF for an axis-aligned box
float sdBox(float2 p, float2 b) {
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// 2D Rotation helper
float2 rotate(float2 p, float angle) {
    float c = cos(angle);
    float s = sin(angle);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

void LetterZShape_float(float2 UV, float Size, float4 Color, float2 Center, float Thickness, float CornerRadius, float4 OutlineColor, float OutlineThickness, out float4 outColor) {
    // 1. Center the UV coordinates
    float2 p = UV - Center;
    
    // 2. Dimensions setup
    // We use Size as the half-extent of the letter's bounding box
    float w = max(Size, 0.0);
    float h = max(Size, 0.0);
    
    // 3. Handle Thickness and Corner Radius
    // effectively, the box thickness is (Thickness/2 - Radius)
    // and we subtract Radius from the final SDF to round it.
    float halfThick = max(Thickness * 0.5, 0.001);
    float r = clamp(CornerRadius, 0.0, halfThick);
    float boxThick = halfThick - r;
    
    // 4. Shape Parts Construction
    
    // Top Bar: Horizontal box at y = +h
    // Extends from x = -w to x = +w
    float dTop = sdBox(p - float2(0.0, h), float2(w, boxThick));
    
    // Bottom Bar: Horizontal box at y = -h
    // Extends from x = -w to x = +w
    float dBot = sdBox(p - float2(0.0, -h), float2(w, boxThick));
    
    // Diagonal: Connects Top-Right (w, h) to Bottom-Left (-w, -h)
    // Vector from TR to BL
    float2 start = float2(w, h);
    float2 end = float2(-w, -h);
    float2 diagVec = end - start;
    float diagLen = length(diagVec);
    float diagAngle = atan2(diagVec.y, diagVec.x);
    
    // Rotate p to align diagonal with X axis
    // We rotate p by -angle
    float2 pDiag = rotate(p, -diagAngle);
    // The center of diagonal is (0,0) because Z is symmetric around center
    float dDiag = sdBox(pDiag, float2(diagLen * 0.5, boxThick));
    
    // 5. Combine parts (Union)
    float d = min(dTop, min(dBot, dDiag));
    
    // 6. Apply Corner Radius (Round the union)
    d = d - r;
    
    // 7. Anti-aliasing and Outline
    float aa = fwidth(d);
    
    // Fill Mask (inside the shape)
    float fillMask = smoothstep(aa, -aa, d);
    
    // Outline Mask (band outside the shape)
    // We want the outline to be 'OutlineThickness' wide outside the shape
    float outlineEdge = smoothstep(OutlineThickness + aa, OutlineThickness - aa, d);
    
    // 8. Composition
    // Start with Outline Color
    float4 finalCol = OutlineColor;
    
    // Blend Fill Color on top of Outline Color
    // Uses straight alpha blending logic: result = fill * fill.a + outline * (1-fill.a)
    // But here we just lerp based on coverage
    finalCol = lerp(finalCol, Color, fillMask);
    
    // Apply final alpha (outline shape defines the total visibility)
    finalCol.a *= outlineEdge;
    
    outColor = finalCol;
}