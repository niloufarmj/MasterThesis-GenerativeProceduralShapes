#ifndef PI
#define PI 3.14159265359
#endif

// --- Helper Functions ---

// Rotate a 2D vector by an angle in radians
float2 Rotate2D(float2 p, float angle) {
    float c = cos(angle);
    float s = sin(angle);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

// Signed distance to a generic polygon (Inigo Quilez)
// Returns negative inside, positive outside
// Vertices must be provided in the loop
float sdLightningShape(float2 p) {
    // Define vertices for a stylized lightning bolt (CCW order for correct sign)
    // V0: Top Left
    // V1: Armpit (Inner)
    // V2: Bottom Tip
    // V3: Hip Right (Outer)
    // V4: Waist Right (Inner)
    // V5: Top Right
    
    // Reversing the previous order to ensure CCW winding
    float2 v[6];
    v[0] = float2(-0.15, 0.5);   // Top Left
    v[1] = float2(-0.05, -0.05); // Armpit Left (Inner)
    v[2] = float2(-0.10, -0.5);  // Bottom Tip
    v[3] = float2(0.30, 0.1);    // Hip Right (Outer)
    v[4] = float2(0.05, 0.1);    // Waist Right (Inner)
    v[5] = float2(0.25, 0.5);    // Top Right

    float d = dot(p - v[0], p - v[0]);
    float s = 1.0;
    
    // Loop through all edges
    // We unroll manually or use a loop. Since it's fixed 6, a loop is fine in HLSL.
    [unroll]
    for (int i = 0; i < 6; i++) {
        int j = (i + 1) % 6;
        float2 e = v[j] - v[i];
        float2 w = p - v[i];
        
        // Distance to segment
        float2 b = w - e * clamp(dot(w, e) / dot(e, e), 0.0, 1.0);
        d = min(d, dot(b, b));
        
        // Winding number / Sign bit
        // Standard ray-casting logic for point-in-polygon
        bool3 cond = bool3(
            p.y >= v[i].y,
            p.y < v[j].y,
            e.x * w.y > e.y * w.x
        );
        
        if (all(cond) || all(!cond)) s *= -1.0;
    }
    
    return s * sqrt(d);
}

// Alpha compositing: Source Over Destination
float4 CompositeLayers(float4 top, float4 bottom) {
    float outA = top.a + bottom.a * (1.0 - top.a);
    float3 outRGB = (top.rgb * top.a + bottom.rgb * bottom.a * (1.0 - top.a)) / max(outA, 1e-6);
    return float4(outRGB, outA);
}

// --- Main Function ---
void LightningBoltIcon_float(float2 UV, float Size, float2 Center, float Rotation, float4 FillColor, float4 StrokeColor, float StrokeWidth, out float4 outColor) {
    // PLAN:
    // 1. Center UVs at 'Center' parameter.
    // 2. Rotate UVs by 'Rotation'.
    // 3. Scale UVs by 'Size' (larger size param = larger visual).
    // 4. Calculate SDF using a robust polygon function.
    // 5. Compute AA factor using fwidth.
    // 6. Compute fill and stroke masks.
    // 7. Composite colors.

    // 1. Center
    float2 p = UV - Center;
    
    // 2. Rotate (negative angle to rotate shape CW for positive input)
    p = Rotate2D(p, -Rotation);
    
    // 3. Scale
    // Size=1 means the bolt fits in approx -0.5 to 0.5 space. 
    // We divide p by Size. Guard against div-by-zero.
    float s = max(Size, 0.0001);
    p /= s;
    
    // 4. SDF
    float dist = sdLightningShape(p);
    
    // 5. Anti-aliasing
    // fwidth(dist) estimates the change of distance across a pixel.
    // This ensures sharp edges at any scale/zoom.
    float aa = fwidth(dist);
    aa = max(aa, 0.0001);
    
    // 6. Masks
    // Fill: Inside (dist < 0)
    float fillMask = smoothstep(aa, -aa, dist);
    
    // Stroke: Centered on edge (dist = 0)
    // StrokeWidth is in UV units. We must scale it to local space (divide by s) 
    // or conceptually, stroke width depends on the scale.
    // Usually StrokeWidth implies "screen/UV thickness", so we scale it.
    float localStrokeWidth = StrokeWidth / s;
    float halfStroke = localStrokeWidth * 0.5;
    float strokeMask = smoothstep(halfStroke + aa, halfStroke - aa, abs(dist));
    
    // 7. Composite
    float4 fillLayer = float4(FillColor.rgb, FillColor.a * fillMask);
    float4 strokeLayer = float4(StrokeColor.rgb, StrokeColor.a * strokeMask);
    
    // Stroke on top of Fill
    outColor = CompositeLayers(strokeLayer, fillLayer);
}

// ------------------------------------------------------------------------
//  Visual Result (High-level, parameter-invariant description)
// ------------------------------------------------------------------------
//  This function generates a **stylized 2D lightning-bolt primitive**
//  using a polygon-based Signed Distance Function (SDF).
//
//  The shape forms a sharp, angular zigzag silhouette commonly associated
//  with electricity or energy symbols. Its proportions, orientation,
//  placement, fill, and outline appearance are fully controlled by input
//  parameters and are not fixed by the function itself.
//
//  The output is an anti-aliased RGBA color suitable for icons,
//  warning symbols, energy indicators, and expressive procedural
//  2D graphics.
// ------------------------------------------------------------------------
