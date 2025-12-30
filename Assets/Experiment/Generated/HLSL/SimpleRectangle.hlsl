// User Request: A simple rectangle centered on the screen. The width and height should be adjustable separately. I want a single solid fill color. The edges should be sharp and clean.

// Helper function: Signed Distance Field for a Box
// p: point relative to center
// b: half-extents (width/2, height/2)
float sdBox(float2 p, float2 b) {
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

void SimpleRectangle_float(float2 UV, float Width, float Height, float4 Color, out float4 outColor) {
    // PLAN:
    // 1. Center the UV coordinates (0.5, 0.5 becomes 0,0).
    // 2. Define box dimensions (half-size) from input Width/Height.
    // 3. Compute signed distance to the box.
    // 4. Calculate anti-aliasing factor using screen-space derivatives (fwidth).
    // 5. Create a smooth mask for the shape.
    // 6. Output the final color with the mask applied to alpha.

    // 1. Center UV
    float2 centered = UV - 0.5;
    
    // 2. Scale half-size (Width and Height are full dimensions)
    float2 halfSize = float2(Width, Height) * 0.5;
    
    // 3. Calculate SDF (negative inside, positive outside)
    float dist = sdBox(centered, halfSize);
    
    // 4. Anti-aliasing
    // fwidth gives the rate of change of the distance field per pixel
    // This ensures edges look equally sharp regardless of zoom or resolution
    float aa = fwidth(dist);
    
    // 5. Mask generation
    // smoothstep(0, aa, dist) returns 0 inside, 1 outside (at the edge)
    // We invert it to get 1 inside (opaque), 0 outside (transparent)
    float mask = 1.0 - smoothstep(0.0, aa, dist);
    
    // 6. Final Output
    // Apply mask to both RGB (premultiplied appearance) and Alpha
    outColor = float4(Color.rgb * mask, mask * Color.a);
}