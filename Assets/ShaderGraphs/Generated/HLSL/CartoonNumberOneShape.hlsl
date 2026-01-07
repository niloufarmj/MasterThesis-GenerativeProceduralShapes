#ifndef PI
#define PI 3.14159265359
#endif

// Helper: Rotate vector
float2 nm_rotate(float2 p, float angle) {
    float c = cos(angle);
    float s = sin(angle);
    return float2(c*p.x - s*p.y, s*p.x + c*p.y);
}

// Helper: Box SDF
float nm_sdBox(float2 p, float2 b) {
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// Helper: Porter-Duff "Over" compositing
float4 nm_over(float4 src, float4 dst) {
    float a = src.a + dst.a * (1.0 - src.a);
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-8);
    return float4(c, a);
}

void CartoonNumberOneShape_float(float2 UV, float2 Center, float Size, float Rotation, 
                          float StemHeight, float BeakLength, float Thickness, float BeakAngle, float CornerRadius,
                          float4 FillColor, float4 OutlineColor, float OutlineWidth, 
                          out float4 outColor) {
    // PLAN:
    // 1. Center and Scale UVs to create local coordinate space.
    // 2. Define Box Primitives for the vertical Body (Stem) and diagonal Flag (Beak).
    // 3. Transform Beak (Rotate/Translate) to join the Stem seamlessly.
    // 4. Combine primitives with Union (min) to merge them.
    // 5. Apply Corner Radius (SDF - r) for rounded edges.
    // 6. Compute AA and Outline using smoothstep.
    // 7. Composite Stroke over Fill.
    
    // 1. Normalize coordinates
    // Map UV (0..1) to p (-1..1) centered at 'Center'
    float2 p = (UV - Center) * 2.0;
    // Apply global rotation
    p = nm_rotate(p, -Rotation);
    // Apply global scale (Size)
    p /= max(Size, 0.0001);

    // 2. Dimensions & Safe Guards
    float th = max(Thickness, 0.001);
    float sh = max(StemHeight, 0.001);
    float bl = max(BeakLength, 0.001);
    
    // 3. Stem SDF (Vertical Body)
    // Centered vertically on Y=0 in local space
    float2 stemSize = float2(th, sh) * 0.5;
    float dStem = nm_sdBox(p, stemSize);
    
    // 4. Beak SDF (Top Flag)
    // We want the beak to attach to the top-left of the stem.
    // Pivot Point: Top-left of the stem's bounding box, adjusted for thickness overlap
    // Stem Top edge Y = +sh/2. Beak Center Y should be offset by half thickness to align top edges.
    float2 pivot = float2(-stemSize.x, stemSize.y - th * 0.5);
    
    // Transform coordinate space for beak relative to pivot
    float2 pBeak = p - pivot;
    pBeak = nm_rotate(pBeak, -BeakAngle); // Rotate relative to pivot
    
    // Define Beak Box
    // Extends to the LEFT (-x) in the rotated space to form the flag
    float2 beakSize = float2(bl, th) * 0.5;
    // Shift box center so its right edge touches the pivot
    float dBeak = nm_sdBox(pBeak - float2(-beakSize.x, 0.0), beakSize);
    
    // 5. Union & Rounding
    // min() creates a seamless union of the two shapes
    float dShape = min(dStem, dBeak);
    // Subtract radius to round the convex corners (expands the shape slightly)
    float r = max(CornerRadius, 0.0);
    float dFinal = dShape - r;
    
    // 6. Rendering (Anti-Aliasing & Outline)
    float aa = fwidth(dFinal);
    float halfOutline = max(OutlineWidth, 0.0) * 0.5;
    
    // Fill Layer (Inner Shape)
    float fillMask = 1.0 - smoothstep(-aa, aa, dFinal);
    float4 layerFill = float4(FillColor.rgb, FillColor.a * fillMask);
    
    // Stroke Layer (Outline)
    // Outline is a band centered on the zero-distance edge
    float dStroke = abs(dFinal) - halfOutline;
    float strokeMask = 1.0 - smoothstep(-aa, aa, dStroke);
    float4 layerStroke = float4(OutlineColor.rgb, OutlineColor.a * strokeMask);
    
    // 7. Composite
    // Draw outline over the fill
    outColor = nm_over(layerStroke, layerFill);
}