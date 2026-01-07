#ifndef PI
#define PI 3.14159265359
#endif

// --- Helper Functions ---

// Signed distance to a line segment from a to b
float num9_sdSegment(float2 p, float2 a, float2 b) {
    float2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}

// Signed distance to a lower semi-circle arc (from angle 0 to -PI)
// Center is origin, radius is r. Assumes 0 angle is at (r,0).
// Lower half is y < 0.
float num9_sdArcLower(float2 p, float r) {
    float l = length(p);
    // If we are in the lower half (y < 0), the closest point is on the arc ring.
    if (p.y < 0.0) return abs(l - r);
    // If in upper half, closest point is one of the endpoints (r,0) or (-r,0).
    return min(length(p - float2(r, 0.0)), length(p - float2(-r, 0.0)));
}

// Main Function: Cartoon Number 9
// Plan:
// 1. Center and scale UVs based on Size parameter.
// 2. Define key dimensions (radius, heights) based on Width/Height.
// 3. Construct 9 skeleton using 3 primitives: 
//    - Top Loop (Circle)
//    - Vertical Stem (Line)
//    - Bottom Hook (Arc, controlled by CornerRadius)
// 4. Combine using min() for seamless union.
// 5. Apply Thickness and Outline logic.
// 6. Output final RGBA with anti-aliasing.

void CartoonNumberNine_float(float2 UV, float Size, float Width, float Height, float Thickness, float CornerRadius, float OutlineWidth, float4 FillColor, float4 OutlineColor, out float4 outColor) {
    // 1. Coordinate setup
    // Map UV (0..1) to centered space (-1..1) scaled by Size
    float2 p = (UV - 0.5) * 2.0;
    p /= max(Size, 0.001);
    
    // 2. Dimensions
    // W is the radius of the top loop and the spacing of the stem
    float W = max(Width * 0.5, 0.01);
    // H is half the total height
    float H = max(Height * 0.5, W * 1.1);
    
    // Calculate vertical positions
    // Top circle is at y = H - W
    float yTop = H - W;
    // Bottom of the shape is at y = -H. 
    // The straight stem goes down to -H + BendRadius
    // The hook curves from there down to -H.
    
    // 3. Dynamic Corner Radius (Hook Curvature)
    // Maps 0..1 to a bend radius from 0 (straight) to W (full semi-circle hook)
    float bendR = clamp(CornerRadius * W, 0.0, W);
    float yStemBottom = -H + bendR;
    
    // 4. SDF Construction (Skeleton)
    // Part A: Top Loop (Full Circle centered at 0, yTop)
    float dLoop = abs(length(p - float2(0.0, yTop)) - W);
    
    // Part B: Vertical Stem (Line on right side)
    // Connects tangent of loop (W, yTop) to start of hook (W, yStemBottom)
    float dStem = num9_sdSegment(p, float2(W, yTop), float2(W, yStemBottom));
    
    // Part C: Bottom Hook (Arc)
    // Connects to stem at (W, yStemBottom) and curves left/down.
    // To connect tangentially to a vertical line at x=W going down,
    // and curve left, the center of rotation must be at (W - bendR, yStemBottom).
    // The arc starts at local (bendR, 0) (Angle 0) and goes to (-bendR, 0) (Angle -PI).
    float2 hookCenter = float2(W - bendR, yStemBottom);
    float dHook = num9_sdArcLower(p - hookCenter, bendR);
    
    // Combine parts (Union)
    float dSkeleton = min(dLoop, min(dStem, dHook));
    
    // 5. Apply Thickness to create the shape volume
    // dShape < 0 is inside the '9'
    float dShape = dSkeleton - max(Thickness, 0.001);
    
    // 6. Outline & Rendering
    // We define the outline as a shell strictly OUTSIDE the shape.
    // dShape is the signed distance to the shape edge.
    
    // AA factor based on screen space derivatives
    float aa = length(fwidth(p)) * 0.7;
    
    // Fill Alpha: 1.0 inside shape, 0.0 outside
    float alphaFill = smoothstep(aa, -aa, dShape);
    
    // Outline Alpha: Includes the shape + outline width
    float dOutline = dShape - max(OutlineWidth, 0.0);
    float alphaOutline = smoothstep(aa, -aa, dOutline);
    
    // Composite colors
    // If inside fill, use FillColor. 
    // If in outline region (alphaOutline - alphaFill), use OutlineColor.
    // Standard 'Over' blending: Outline is drawn behind fill, or fill occludes outline.
    // Here we assume Fill is drawn ON TOP of the Outline base.
    
    float3 finalRGB = lerp(OutlineColor.rgb, FillColor.rgb, alphaFill);
    float finalAlpha = alphaOutline; // The silhouette is determined by the outline
    
    // Modulate by vertex alpha inputs
    finalAlpha *= max(FillColor.a, OutlineColor.a); // Simple opacity handling
    
    outColor = float4(finalRGB * finalAlpha, finalAlpha);
}