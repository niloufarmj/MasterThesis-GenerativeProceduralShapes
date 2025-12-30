void RectFrameFill_float(float2 UV, float Width, float Height, float Thickness, float4 Color, float Fill, out float4 outColor) {
    // PLAN:
    // 1) Center UV coordinates and define dimensions.
    // 2) Calculate SDF for a rectangular frame (abs(box) - thickness).
    // 3) Calculate progress 't' along the perimeter (0 to 1) starting from Top-Left.
    // 4) Create a fill mask by comparing 't' with 'Fill' parameter.
    // 5) Combine frame alpha and fill mask, apply Color, output premultiplied alpha.

    // 1. Center coordinates
    float2 p = UV - 0.5;
    
    // 2. Safe dimensions and Half-Size
    float w = max(Width, 0.001);
    float h = max(Height, 0.001);
    float2 halfSize = float2(w, h) * 0.5;
    
    // 3. Rectangular Frame SDF
    // Calculate distance to the outer box edge
    float2 d = abs(p) - halfSize;
    float distOuter = length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
    
    // Create frame by subtracting thickness from absolute distance
    // This centers the border on the rectangle's edge
    // SDF is negative INSIDE the frame stroke
    float distFrame = abs(distOuter) - Thickness * 0.5;
    
    // 4. Anti-aliasing for the frame shape
    float aa = fwidth(distFrame);
    aa = max(aa, 0.001); // Safety for previews
    float shapeAlpha = smoothstep(aa, -aa, distFrame);
    
    // 5. Perimeter Fill Logic
    // Map pixel position to a 0..1 value 't' representing progress clockwise from Top-Left.
    // We divide the space into 4 sectors using diagonals.
    // Diagonals condition: |x|*h == |y|*w
    
    float absX_h = abs(p.x) * h;
    float absY_w = abs(p.y) * w;
    float y_w = p.y * w;
    float x_h = p.x * h;
    
    float t = 0.0;
    
    // Determine Sector and calculate local progress
    if (p.y > 0 && absX_h < y_w) {
        // Top Sector (Fill 0.0 -> 0.25)
        // Progress Left (-w/2) to Right (w/2)
        float normalizedPos = (p.x / w) + 0.5;
        t = normalizedPos * 0.25;
    } 
    else if (p.x > 0 && absY_w < x_h) {
        // Right Sector (Fill 0.25 -> 0.50)
        // Progress Top (h/2) to Bottom (-h/2)
        float normalizedPos = 0.5 - (p.y / h);
        t = 0.25 + normalizedPos * 0.25;
    } 
    else if (p.y < 0 && absX_h < -y_w) {
        // Bottom Sector (Fill 0.50 -> 0.75)
        // Progress Right (w/2) to Left (-w/2)
        float normalizedPos = 0.5 - (p.x / w);
        t = 0.50 + normalizedPos * 0.25;
    } 
    else {
        // Left Sector (Fill 0.75 -> 1.0)
        // Progress Bottom (-h/2) to Top (h/2)
        float normalizedPos = (p.y / h) + 0.5;
        t = 0.75 + normalizedPos * 0.25;
    }
    
    // 6. Fill Mask
    // Visible if Fill > t. Use smoothstep for clean transition.
    // smoothstep(edge0, edge1, x) -> 0 if x < edge0, 1 if x > edge1
    float fillMask = smoothstep(t - 0.005, t + 0.005, Fill);
    
    // 7. Final Composite
    // Combine shape alpha, fill mask, and color alpha
    float finalAlpha = shapeAlpha * fillMask * Color.a;
    
    // Output premultiplied alpha (Standard for Unity transparent shaders)
    outColor = float4(Color.rgb * finalAlpha, finalAlpha);
}