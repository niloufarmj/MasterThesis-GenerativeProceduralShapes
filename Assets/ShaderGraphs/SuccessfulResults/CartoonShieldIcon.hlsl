#ifndef PI
#define PI 3.14159265359
#endif

// Helper for compositing colors (Source Over Destination)
float4 shield_over(float4 src, float4 dst)
{
    float a = src.a + dst.a * (1.0 - src.a);
    // Avoid div by zero
    float div = max(a, 1e-6);
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / div;
    return float4(c, a);
}

void CartoonShieldIcon_float(
    float2 UV,
    float Width,
    float Height,
    float BorderThickness,
    float4 BorderColor,
    float4 ColorTL,
    float4 ColorTR,
    float4 ColorBL,
    float4 ColorBR,
    out float4 outColor)
{
    // PLAN:
    // 1) Center UVs to p in [-0.5, 0.5] (relative to canvas).
    // 2) Define Heater Shield SDF using intersection of a Circle and a Plane.
    //    - Top edge: Flat line at y = +h
    //    - Sides/Bottom: Two arcs meeting at y = -h.
    // 3) Calculate exact SDF for shape.
    // 4) Determine quadrant color based on UV position.
    // 5) Generate Fill mask (inside shape) and Border mask (around edge).
    // 6) Composite Border over Fill.

    // 1) Coordinates
    float2 p = UV - 0.5;
    
    // Clamp dimensions to avoid degenerate math
    float w = max(Width, 0.01) * 0.5;  // Half-width
    float h = max(Height, 0.01) * 0.5; // Half-height
    
    // 2) Shield Geometry Math
    // We model the shield as the intersection of:
    // A) A half-plane (y < h)
    // B) A circle that passes through (w, h) with vertical tangent, and (0, -h).
    // Derivation:
    // Circle Center (cx, cy). Vertical tangent at (w, h) => cy = h, cx = w - R.
    // Passes through (0, -h) => distance((0, -h), (w-R, h)) = R
    // (w-R)^2 + (h - (-h))^2 = R^2
    // w^2 - 2wR + R^2 + 4h^2 = R^2
    // w^2 + 4h^2 = 2wR  => R = (w^2 + 4h^2) / (2w)
    
    float R = (w * w + 4.0 * h * h) / (2.0 * w);
    float2 circleCenter = float2(w - R, h);
    
    // 3) SDF Calculation
    // Apply symmetry for X axis to handle both sides with one circle
    float2 pSym = float2(abs(p.x), p.y);
    
    // Distance to the defining circle
    float dCircle = length(pSym - circleCenter) - R;
    
    // Distance to the top plane
    float dTop = p.y - h;
    
    // Intersection of convex shapes: exact exterior distance uses length of max vector.
    // Exact interior distance uses min of max distances.
    float2 dVec = float2(dCircle, dTop);
    float dShape = length(max(dVec, 0.0)) + min(max(dVec.x, dVec.y), 0.0);
    
    // 4) Quadrant Color Logic
    // Using original p (not absolute) to determine quadrant
    // x<0, y>0: TL | x>0, y>0: TR
    // x<0, y<0: BL | x>0, y<0: BR
    float2 s = step(0.0, p); // 0 if neg, 1 if pos
    float4 topCol = lerp(ColorTL, ColorTR, s.x);
    float4 botCol = lerp(ColorBL, ColorBR, s.x);
    float4 fillColor = lerp(botCol, topCol, s.y);
    
    // 5) Masks & Antialiasing
    float aa = fwidth(dShape);
    // Ensure sufficient AA falloff even if fwidth is tiny
    aa = max(aa, 0.001);
    
    // Fill Mask: Inside the shape (d < 0)
    float fillMask = 1.0 - smoothstep(0.0, aa, dShape);
    float4 fillLayer = float4(fillColor.rgb, saturate(fillColor.a) * fillMask);
    
    // Border Mask: Band around d=0
    // Thickness is total width. Half extends out, half in.
    float halfBorder = max(BorderThickness, 0.0) * 0.5;
    float dBorder = abs(dShape) - halfBorder;
    float borderMask = 1.0 - smoothstep(0.0, aa, dBorder);
    float4 borderLayer = float4(BorderColor.rgb, saturate(BorderColor.a) * borderMask);
    
    // 6) Composite
    // Draw Border ON TOP of Fill
    outColor = shield_over(borderLayer, fillLayer);
}

// ------------------------------------------------------------------------
//  Visual Result
// ------------------------------------------------------------------------
//  This function generates a **stylized cartoon shield icon** (specifically
//  a "heater shield" shape) using Signed Distance Functions (SDFs).
//
//  The visual result is composed of:
//  - A classic defensive silhouette featuring a flat top edge and curved 
//    sides that converge to a sharp point at the bottom.
//  - A "quartered" internal coloring scheme, dividing the face of the shield
//    into four distinct rectangular zones (Top-Left, Top-Right, Bottom-Left,
//    Bottom-Right).
//  - A thick, uniform border surrounding the entire shape.
//
//  The shape features parameters for the overall width and height, border
//  thickness, and independent color controls for the border and each of the
//  four internal quadrants.
//
//  The output is a crisp, vector-like graphic suitable for RPG defense stats,
//  faction heraldry, or achievement badges.
// ------------------------------------------------------------------------