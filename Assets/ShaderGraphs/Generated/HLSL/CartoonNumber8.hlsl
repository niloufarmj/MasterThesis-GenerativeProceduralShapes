#ifndef PI
#define PI 3.14159265359
#endif

// Helper: Signed Distance to a Rounded Box
// p: point, b: half-extents, r: corner radius
float sdCartoon8_RoundBox(float2 p, float2 b, float r)
{
    float2 q = abs(p) - b + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

// Helper: Composite Color (Source Over Destination)
float4 compositeColors(float4 src, float4 dst)
{
    float outA = src.a + dst.a * (1.0 - src.a);
    float3 outRGB = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(outA, 0.0001);
    return float4(outRGB, outA);
}

// Main Function: Cartoon Number 8 Shape
// Generates a figure-8 using two overlapping rounded rectangles with holes.
void CartoonNumber8_float(
    float2 UV,
    float Size,
    float Width,
    float Height,
    float Thickness,
    float CornerRadius,
    float OutlineWidth,
    float4 FillColor,
    float4 OutlineColor,
    out float4 outColor)
{
    // PLAN:
    // 1. Center UV coordinates (0.5, 0.5 becomes 0,0).
    // 2. Define dimensions for top and bottom loops based on inputs.
    // 3. Create 'Solid' SDF: Union of two overlapping rounded boxes.
    // 4. Create 'Holes' SDF: Union of two smaller rounded boxes.
    // 5. Final Shape = Subtract Holes from Solid.
    // 6. Compute Outline SDF and apply Anti-Aliasing.
    // 7. Composite Outline over Fill.

    // 1. Center UV
    float2 p = UV - 0.5;
    
    // 2. Scale parameters
    // Width/Height are relative to Size. 0.5 Width means half unit wide.
    float w = Width * Size * 0.5;      // Half-width
    float h = Height * Size * 0.5;     // Half-height
    float t = Thickness * Size;        // Scaled thickness
    float r = CornerRadius * Size;     // Scaled radius
    float outW = OutlineWidth * Size;  // Scaled outline

    // Calculate loop geometry
    // To ensure a solid waist, loops must overlap.
    // We overlap enough so the holes (which are smaller) have a bridge between them.
    // overlap = t * 0.6 ensures the solid bridge is approx 0.4*t thick.
    float overlap = t * 0.6;
    float loopHalfHeight = (h / 2.0) + overlap;
    float cy = (h / 2.0) - overlap;
    
    // Clamp corner radius to prevent artifacts
    r = clamp(r, 0.0, min(w, loopHalfHeight));

    // 3. Outer Shape (Solid Figure-8 blob)
    // Union of top and bottom boxes: min(d1, d2)
    float2 posTop = p - float2(0.0, cy);
    float2 posBot = p + float2(0.0, cy);
    float2 boxSize = float2(w, loopHalfHeight);
    
    float dTop = sdCartoon8_RoundBox(posTop, boxSize, r);
    float dBot = sdCartoon8_RoundBox(posBot, boxSize, r);
    float dSolid = min(dTop, dBot);

    // 4. Inner Holes
    // Shrink boxes by thickness 't' to create the void.
    // Inner radius must adjust to keep concentricity (r - t).
    float rInner = max(0.0, r - t);
    float2 holeSize = max(boxSize - float2(t, t), 0.0);

    float dHoleTop = sdCartoon8_RoundBox(posTop, holeSize, rInner);
    float dHoleBot = sdCartoon8_RoundBox(posBot, holeSize, rInner);
    float dHoles = min(dHoleTop, dHoleBot);

    // 5. Final Shape SDF
    // Boolean Subtraction: Intersection(Solid, NOT Holes) -> max(Solid, -Holes)
    float dShape = max(dSolid, -dHoles);

    // 6. Rendering / Anti-aliasing
    float aa = fwidth(dShape);
    // Fallback for preview windows where fwidth might be 0
    aa = max(aa, 0.0001);
    
    // Fill Layer
    float fillMask = 1.0 - smoothstep(0.0, aa, dShape);
    float4 fillLayer = float4(FillColor.rgb, FillColor.a * fillMask);

    // Outline Layer (Centered on edge)
    float strokeDist = abs(dShape) - (outW * 0.5);
    float strokeMask = 1.0 - smoothstep(0.0, aa, strokeDist);
    float4 strokeLayer = float4(OutlineColor.rgb, OutlineColor.a * strokeMask);

    // 7. Composite: Stroke OVER Fill
    outColor = compositeColors(strokeLayer, fillLayer);
}