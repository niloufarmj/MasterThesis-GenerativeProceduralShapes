#ifndef PI
#define PI 3.14159265359
#endif

// --- Helper Functions ---

// Signed distance to a box
// p: position relative to center
// b: half-extents (width/2, height/2)
float sdBox(float2 p, float2 b) {
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// 2D Rotation helper
float2 rotate(float2 p, float angle) {
    float c = cos(angle);
    float s = sin(angle);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

// Signed distance to a circular arc
// p: point
// sc: sin/cos of half-aperture angle
// ra: radius
// rb: half-thickness
float sdArc(float2 p, float2 sc, float ra, float rb) {
    p.x = abs(p.x);
    return ((sc.y * p.x > sc.x * p.y) ? length(p - sc * ra) : abs(length(p) - ra)) - rb;
}

// --- Main Function ---
// Generates a cartoon number 5 with adjustable parameters
void CartoonNumber5_float(float2 UV, float Width, float Height, float Thickness, float CornerRadius, float4 Color, float4 OutlineColor, float OutlineThickness, out float4 outColor) {
    // PLAN:
    // 1. Center and scale UV coordinates to create a consistent canvas.
    // 2. Define geometry parameters (half-sizes, adjusted thickness).
    // 3. Construct the '5' using 4 primitives:
    //    - Top horizontal bar (Box)
    //    - Vertical neck (Box)
    //    - Horizontal bridge (Box)
    //    - Bottom belly (Arc)
    // 4. Combine primitives using smooth minimum or simple min for clean joints.
    // 5. Apply rounded corners via SDF manipulation.
    // 6. Compute Fill and Outline masks.
    // 7. Composite final color.

    // 1. Setup Coordinates
    // Center UV at (0,0)
    float2 p = UV - 0.5;
    // Visual scale factor (optional, keeps shapes reasonable size)
    p *= 2.0;

    // 2. Geometry Setup
    float hw = max(Width, 0.001) * 0.5;
    float hh = max(Height, 0.001) * 0.5;
    float th = max(Thickness, 0.001);
    float hth = th * 0.5;
    
    // Clamp corner radius to prevent artifacts (can't be larger than half thickness)
    float cr = clamp(CornerRadius, 0.0, hth);
    
    // Effective half-thickness for SDFs (subtracting radius for rounding later)
    float eff_hth = hth - cr;
    
    // 3. Construct Primitives
    
    // --- Part A: Top Bar ---
    // Centered at top, spans full width
    float2 top_center = float2(0.0, hh - hth);
    float2 top_size = float2(hw - cr, eff_hth); // -cr compensates for rounding
    float d_top = sdBox(p - top_center, top_size) - cr;

    // --- Part B: The Belly Geometry ---
    // The belly is an arc filling the bottom width.
    // Radius is derived to fit between the neck (left) and right edge.
    float belly_radius = (Width - th) * 0.5;
    float belly_cy = -hh + belly_radius + hth; // Bottom aligns with -hh
    float2 belly_center = float2(0.0, belly_cy);
    
    // --- Part C: Neck (Vertical) ---
    // Connects Top Bar to the Bridge (which is at top of Belly)
    // X: Left aligned (-hw + hth)
    // Y Top: Top Bar Bottom (hh - th)
    // Y Bottom: Belly Top (belly_cy + belly_radius)
    float neck_x = -hw + hth;
    float bridge_y = belly_cy + belly_radius;
    float neck_top_y = hh - hth; // Overlap slightly with top bar center
    float neck_h = (neck_top_y - bridge_y) * 0.5;
    float neck_cy = bridge_y + neck_h;
    
    float2 neck_center = float2(neck_x, neck_cy);
    float2 neck_size = float2(eff_hth, max(neck_h + eff_hth, 0.0)); // Add eff_hth to overlap top
    float d_neck = sdBox(p - neck_center, neck_size) - cr;

    // --- Part D: Bridge (Horizontal) ---
    // Connects Neck to Belly Top (Angle PI/2)
    // Spans from Neck X to Center X
    float bridge_w = abs(neck_x) * 0.5;
    float bridge_cx = neck_x + bridge_w;
    float2 bridge_center = float2(bridge_cx, bridge_y);
    float2 bridge_size = float2(bridge_w + cr, eff_hth); // Add cr to overlap joints
    float d_bridge = sdBox(p - bridge_center, bridge_size) - cr;

    // --- Part E: Belly Arc ---
    // We need an arc from Angle PI/2 (Top) -> Right -> Bottom -> Left
    // Range: 90 deg down to -180 deg. (270 degree span)
    // Center of this range: -45 deg (-PI/4)
    // Half-aperture: 135 deg (3PI/4)
    float aperture_angle = radians(135.0);
    float2 sc = float2(sin(aperture_angle), cos(aperture_angle));
    
    // Rotate p to align the arc's symmetry axis with X axis for the sdArc function
    // The arc center is -45 deg, so we rotate by +45 deg
    float rot_angle = radians(45.0);
    float2 p_arc = rotate(p - belly_center, rot_angle);
    
    // Compute arc SDF
    float d_arc = sdArc(p_arc, sc, belly_radius, eff_hth) - cr;

    // 4. Combine Shapes
    // Use min for Union. The overlaps (due to construction) ensure seamlessness.
    float d_shape = min(d_top, min(d_neck, min(d_bridge, d_arc)));

    // 5. Rendering
    // AA factor based on derivatives
    float aa = fwidth(d_shape);
    
    // Fill Mask (Inner color)
    float fillAlpha = 1.0 - smoothstep(-aa, aa, d_shape);
    
    // Outline Mask (Outer border)
    // Outline extends OUTWARDS from the shape edge (d=0 to d=OutlineThickness)
    float outlineWidth = max(OutlineThickness, 0.0);
    float outlineEdge = d_shape - outlineWidth;
    float outlineAlpha = 1.0 - smoothstep(-aa, aa, outlineEdge);
    
    // Composite
    // We draw the outline, then blend the fill on top.
    // Since we computed full alphas, we can use simple mixing.
    float4 finalColor = lerp(OutlineColor, Color, fillAlpha);
    
    // Final alpha is the outline's coverage (since outline includes the fill area)
    // If OutlineThickness is 0, outlineAlpha equals fillAlpha.
    float finalAlpha = outlineAlpha;
    
    // Apply outline color opacity properly
    finalColor.a = finalAlpha;

    // Output
    outColor = float4(finalColor.rgb * finalAlpha, finalAlpha);
}