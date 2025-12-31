#ifndef PI
#define PI 3.14159265359
#endif

// --- Helper Functions ---

// Signed distance to a 2D rounded box
// p: sampling point
// b: half-extents (width/2, height/2)
// r: corner radius
float sdRoundedBox(float2 p, float2 b, float r) {
    float2 q = abs(p) - b + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

// Smooth union of two SDFs to blend shapes organically
// d1, d2: distances
// k: smoothing factor
float opSmoothUnion(float d1, float d2, float k) {
    float h = clamp(0.5 + 0.5 * (d2 - d1) / k, 0.0, 1.0);
    return lerp(d2, d1, h) - k * h * (1.0 - h);
}

// Alpha blending helper (SrcOver)
float4 shape_over(float4 src, float4 dst) {
    float a = src.a + dst.a * (1.0 - src.a);
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-6);
    return float4(c, a);
}

// --- Main Function ---
// User Request: An outlined cartoon hat
void CartoonHat_float(float2 UV, float2 Center, float Size, float Rotation, float4 FillColor, float4 StrokeColor, float StrokeWidth, out float4 outColor) {
    // PLAN:
    // 1. Transform UVs: Recenter, Rotate, and handle Scale.
    // 2. Define Crown SDF: A rounded box sitting on top.
    // 3. Define Brim SDF: A wider, thinner rounded box at the bottom.
    // 4. Combine Crown and Brim using smooth union.
    // 5. Calculate Fill and Stroke masks using smoothstep AA.
    // 6. Optional: Add a 'hat band' by checking coordinate height inside the crown.
    // 7. Composite Stroke over Fill.

    // 1. Coordinate Space
    float2 p = UV - Center;
    
    // Rotation
    float cosR = cos(Rotation);
    float sinR = sin(Rotation);
    p = float2(p.x * cosR - p.y * sinR, p.x * sinR + p.y * cosR);
    
    // Scale
    // We divide p by Size to scale the domain, but must multiply result dist by Size to correct gradients.
    float scale = max(Size, 0.001);
    float2 sp = p / scale;

    // 2. Define Shapes (Relative to scaled space)
    // Crown: Sits slightly above center. 
    // Width ~0.6, Height ~0.7. Center Y shifted up.
    float2 crownCenter = float2(0.0, 0.15);
    float2 crownSize = float2(0.32, 0.35); // Half-extents
    float crownRadius = 0.04;
    float dCrown = sdRoundedBox(sp - crownCenter, crownSize, crownRadius);

    // Brim: Sits at the bottom of the crown.
    // Width ~1.1, Height ~0.15.
    float2 brimCenter = float2(0.0, -0.25);
    float2 brimSize = float2(0.55, 0.05);
    float brimRadius = 0.05;
    float dBrim = sdRoundedBox(sp - brimCenter, brimSize, brimRadius);

    // 3. Combine Shapes
    // Use smooth union to melt the brim into the crown slightly
    float dShapeUnscaled = opSmoothUnion(dCrown, dBrim, 0.03);
    
    // Correct distance for scaling
    float dShape = dShapeUnscaled * scale;

    // 4. Anti-Aliasing parameters
    float aa = fwidth(dShape);
    // Fallback for previews if fwidth is zero (e.g. constant UVs)
    aa = max(aa, 0.001);

    // 5. Fill Logic
    // Basic Fill Mask
    float fillMask = 1.0 - smoothstep(-aa, aa, dShape);
    
    // Hat Band Logic: 
    // If we are inside the crown part, near the bottom, change color to StrokeColor (or a band color).
    // Band area: Y relative to crownCenter. Crown bottom is roughly 0.15 - 0.35 = -0.2.
    // Let's place band just above the brim.
    // We check unscaled Y coordinate relative to rotation.
    bool inBand = (sp.y > -0.2 && sp.y < -0.05) && (dCrown < 0.01) && (dBrim > 0.0);
    
    float4 currentFill = FillColor;
    // Simple selection for band color (using StrokeColor for style cohesion)
    if (inBand) currentFill = StrokeColor;

    float4 fillLayer = float4(currentFill.rgb, currentFill.a * fillMask);

    // 6. Stroke Logic
    float halfStroke = StrokeWidth * 0.5;
    // Outer edge is dShape - halfStroke (visual border)
    // We want a border centered on the shape edge, or expanding outwards.
    // Standard outline: shell around the zero iso-surface.
    float dStroke = abs(dShape) - halfStroke;
    float strokeMask = 1.0 - smoothstep(-aa, aa, dStroke);
    
    float4 strokeLayer = float4(StrokeColor.rgb, StrokeColor.a * strokeMask);

    // 7. Composite
    // Stroke goes OVER fill
    outColor = shape_over(strokeLayer, fillLayer);
}