#ifndef PI
#define PI 3.14159265359
#endif

// Helper: Smooth Minimum for blending shapes (removes creases)
float smin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return lerp(b, a, h) - k * h * (1.0 - h);
}

// Helper: Distance to a line segment
float sdSegment(float2 p, float2 a, float2 b) {
    float2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}

// Helper: Evaluate Quadratic Bezier position at t
float2 getBezierPoint(float2 a, float2 b, float2 c, float t) {
    return lerp(lerp(a, b, t), lerp(b, c, t), t);
}

// Helper: Approximate distance to Quadratic Bezier (Iterative)
// Analytical solution is complex; this is cheap and robust for thick cartoon shapes.
float sdBezierApprox(float2 p, float2 A, float2 B, float2 C, int steps) {
    float minDist = 1e5;
    float2 prevP = A;
    for(int i = 1; i <= steps; i++) {
        float t = float(i) / float(steps);
        float2 currP = getBezierPoint(A, B, C, t);
        minDist = min(minDist, sdSegment(p, prevP, currP));
        prevP = currP;
    }
    return minDist;
}

// MAIN FUNCTION: Cartoon Number 6 Shape
// Constructed from a circular loop at the bottom and a bezier curve stem.
// Parameters control the skeleton size, thickness, and outline.
void CartoonNumberSix_float(float2 UV, float Width, float Height, float Thickness, float OutlineWidth, float CornerRadius, float4 FillColor, float4 OutlineColor, out float4 outColor) {
    // 1. Setup Coordinates
    float2 p = UV - 0.5;
    
    // Handle scaling (avoid divide by zero)
    float w = max(Width, 0.01);
    float h = max(Height, 0.01);
    
    // Scale p so the shape fits the bounds defined by Width/Height
    // We normalize p by these dimensions to work in a consistent 0..1 generic space
    // but we must be careful with SDF distortion. 
    // Better: Define the shape points scaled by w/h, and keep p uniform if possible.
    // Here we define the points relative to w/h.
    
    // 2. Define Skeleton Points for '6'
    // Bottom Loop parameters
    // CornerRadius controls the loop size relative to width (0.2 to 0.4 range typical)
    float loopRadius = w * clamp(CornerRadius, 0.1, 0.45);
    float2 loopCenter = float2(w * 0.05, -h * 0.25); 
    
    // Stem Bezier parameters
    // Start at the left tangent of the loop for smooth connection
    float2 p0 = loopCenter + float2(-loopRadius, 0.0);
    // Control point goes up and slightly left to form the back of the 6
    float2 p1 = float2(loopCenter.x - loopRadius, h * 0.35);
    // End point curves over the top
    float2 p2 = float2(w * 0.3, h * 0.4);
    
    // 3. Compute Signed Distance Fields (SDF)
    // A: Distance to the loop (Circle/Ring centerline)
    float dLoop = abs(length(p - loopCenter) - loopRadius);
    
    // B: Distance to the stem (Bezier centerline)
    // Use 16 steps for sufficient smoothness
    float dStem = sdBezierApprox(p, p0, p1, p2, 16);
    
    // C: Combine loop and stem seamlessly
    // Since we aligned the start point tangent, min() is good, but smin ensures no creases
    float dCenterline = smin(dLoop, dStem, 0.02);
    
    // 4. Create Body and Outline SDFs
    // The shape is defined by expanding the centerline by Thickness
    float dBody = dCenterline - Thickness;
    
    // The outline is an expansion of the body
    float dOutline = dBody - OutlineWidth;
    
    // 5. Anti-aliasing and Masking
    // fwidth gives a sharp pixel-perfect AA width
    float aa = fwidth(dBody);
    aa = max(aa, 0.001);
    
    // Calculate masks (0 = transparent/outside, 1 = opaque/inside)
    // Use smoothstep for soft edges
    float outlineMask = 1.0 - smoothstep(-aa, aa, dOutline);
    float fillMask = 1.0 - smoothstep(-aa, aa, dBody);
    
    // 6. Composition
    // Layer the fill on top of the outline
    // If fillMask is 1, show FillColor. If fillMask is 0 but outlineMask is 1, show OutlineColor.
    float3 finalRGB = lerp(OutlineColor.rgb, FillColor.rgb, fillMask);
    
    // Alpha: The shape exists where the outline exists
    float finalAlpha = outlineMask;
    
    // Apply vertex alpha from inputs if desired (assuming inputs are opaque by default)
    finalAlpha *= max(OutlineColor.a, FillColor.a);
    
    outColor = float4(finalRGB * finalAlpha, finalAlpha);
}