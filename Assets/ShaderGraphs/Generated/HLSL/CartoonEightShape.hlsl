#ifndef PI
#define PI 3.14159265359
#endif

// --- Helper Functions ---

// Signed Distance to a Rounded Box
// p: point, b: half-extents, r: corner radius
float sdEight_RoundBox(float2 p, float2 b, float r)
{
    float2 q = abs(p) - b + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

// Smooth Minimum (Polynomial)
// Used to blend the top and bottom loops seamlessly
float smin(float a, float b, float k)
{
    float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return lerp(b, a, h) - k * h * (1.0 - h);
}

// Composite Source Over Destination (Straight Alpha)
float4 compositeEight_Over(float4 src, float4 dst)
{
    float outA = src.a + dst.a * (1.0 - src.a);
    float3 outRGB = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(outA, 1e-6);
    return float4(outRGB, outA);
}

// --- Main Function ---
// Generates a seamless cartoon number 8 with adjustable rounding, thickness, and outline.
void CartoonEightShape_float(
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
    // 1. Center UVs and scale inputs by Size.
    // 2. Calculate vertical layout to ensure exact bridge thickness.
    //    - The 'bridge' is the solid connection between the two holes.
    //    - We derive the loop centers so that the holes are separated exactly by 'Thickness'.
    // 3. Define SDFs for Top and Bottom Loops:
    //    - Solid Shapes: Two rounded boxes.
    //    - Holes: Two smaller rounded boxes.
    // 4. Combine Shapes:
    //    - Solid Union: Use smin() (Smooth Min) to merge top and bottom solids seamlessly.
    //      This eliminates the "visible line" or crease at the waist.
    //    - Hole Union: Use min() to combine holes.
    //    - Final Shape: max(Solid, -Holes).
    // 5. Render with anti-aliasing and outline.

    // 1. Coordinates and Scaling
    float2 p = UV - 0.5;
    
    // Apply Size multiplier to dimensions
    float w = Width * Size * 0.5;      // Half-width
    float h_total = Height * Size;     // Total visual height
    float t = Thickness * Size;        // Ring thickness
    float r = CornerRadius * Size;     // Corner radius
    float outline = OutlineWidth * Size;
    float smoothK = 0.05 * Size;       // Smoothing factor for the loop connection

    // 2. Vertical Layout Logic
    // We want the total height to be h_total.
    // The bridge (middle solid part) should have thickness 't'.
    // Let 'cy' be the distance from center to loop center.
    // Let 'hy' be the half-height of the hole.
    // The bridge is the space between the holes: (cy - hy) - (-cy + hy) = 2(cy - hy).
    // We want 2(cy - hy) = t  =>  hy = cy - t/2.
    // The top of the shape is: cy + hy + t = cy + (cy - t/2) + t = 2cy + t/2.
    // We want 2cy + t/2 = h_total / 2  =>  2cy = (h_total - t)/2  =>  cy = (h_total - t) / 4.
    
    float cy = (h_total - t) * 0.25;
    float holeHalfH = max(0.0, cy - (t * 0.5));
    float solidHalfH = holeHalfH + t;
    
    float solidHalfW = w;
    float holeHalfW = max(0.0, w - t);

    // Clamped radii
    float r_solid = clamp(r, 0.0, min(solidHalfW, solidHalfH));
    float r_hole = max(0.0, r_solid - t); // Keep holes roughly concentric or boxy if needed

    // 3. Compute SDFs
    // Shift coordinates for top and bottom loops
    float2 p_top = p - float2(0.0, cy);
    float2 p_bot = p + float2(0.0, cy);

    // Solid parts (Outer Shell)
    float dTopSolid = sdEight_RoundBox(p_top, float2(solidHalfW, solidHalfH), r_solid);
    float dBotSolid = sdEight_RoundBox(p_bot, float2(solidHalfW, solidHalfH), r_solid);
    
    // Smooth Union for the body to prevent visual separation at the waist
    float dSolid = smin(dTopSolid, dBotSolid, smoothK);

    // Hollow parts (Inner Holes)
    float dTopHole = sdEight_RoundBox(p_top, float2(holeHalfW, holeHalfH), r_hole);
    float dBotHole = sdEight_RoundBox(p_bot, float2(holeHalfW, holeHalfH), r_hole);
    
    // Standard Union for holes (we want the union of empty space)
    float dHoles = min(dTopHole, dBotHole);

    // 4. Final SDF Operation: Subtraction
    // Shape = Solid intersected with (Not Holes)
    float dShape = max(dSolid, -dHoles);

    // 5. Rendering
    float aa = fwidth(dShape);
    aa = max(aa, 1e-4);

    // Fill Mask
    float fillMask = 1.0 - smoothstep(0.0, aa, dShape);
    float4 fillLayer = float4(FillColor.rgb, FillColor.a * fillMask);

    // Outline Mask
    // Outline is centered on the boundary (distance 0)
    float dStroke = abs(dShape) - (outline * 0.5);
    float strokeMask = 1.0 - smoothstep(0.0, aa, dStroke);
    float4 strokeLayer = float4(OutlineColor.rgb, OutlineColor.a * strokeMask);

    // Composite Outline OVER Fill
    outColor = compositeEight_Over(strokeLayer, fillLayer);
}