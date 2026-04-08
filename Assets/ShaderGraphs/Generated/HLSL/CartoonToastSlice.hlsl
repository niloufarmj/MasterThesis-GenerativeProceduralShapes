/* 
  PLAN:
  1. Define helpers: Random hash, SmoothMin (smin), Over (blending).
  2. Define SDF for Toast shape: 
     - Combine a rounded box (for the body and bottom corners) 
     - With two circles (for the double-hump top).
  3. Define Bubble/Hole pattern logic using a grid-based pseudo-random approach (Voronoi-like).
  4. Main Function:
     - Center and scale UVs.
     - Calculate Toast SDF.
     - Calculate Crust mask (inner offset of SDF).
     - Calculate Holes mask (tiled SDF check).
     - Compute Stroke mask (outline).
     - Layer colors: Stroke -> Base -> Crust -> Bread -> Holes.
*/

#ifndef PI
#define PI 3.14159265359
#endif

// --- Helpers ---

// Pseudo-random 2D hash
float2 hash22(float2 p) {
    float3 p3 = frac(float3(p.xyx) * float3(.1031, .1030, .0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return frac((p3.xx + p3.yz) * p3.zy);
}

// Smooth Minimum for blending shapes
float smin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return lerp(b, a, h) - k * h * (1.0 - h);
}

// Rounded Box SDF
float sdRoundedBox(float2 p, float2 b, float4 r) {
    // r.x = top-right, r.y = bottom-right, r.z = top-left, r.w = bottom-left
    r.xy = (p.x > 0.0) ? r.xy : r.zw;
    r.x  = (p.y > 0.0) ? r.x  : r.y;
    float2 q = abs(p) - b + r.x;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r.x;
}

// Alpha compositing helper
float4 over(float4 src, float4 dst) {
    float a = src.a + dst.a * (1.0 - src.a);
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-6);
    return float4(c, a);
}

// --- Main Shape Function ---
void CartoonToastSlice_float(
    float2 UV,
    float Size,
    float Width,            // Width ratio of the body
    float Height,           // Height ratio of the body
    float TopHumpRadius,    // Radius of the top humps
    float BottomCornerRadius, // Radius of bottom corners
    float TopCurveSmoothing, // Smooth blending for the top dip
    float CrustThickness,
    float4 BreadColor,
    float4 CrustColor,
    float4 HoleColor,
    float HoleDensity,
    float HoleSize,
    float HoleVariance,
    float StrokeWidth,
    float4 StrokeColor,
    out float4 outColor
) {
    // 1. Center and Scale
    // Default center at 0.5, 0.5. Scale controls 'zoom'.
    float2 p = (UV - 0.5) / max(Size, 0.001);
    
    // 2. Build Toast SDF
    // Calculate half-extents
    float hw = Width * 0.5;
    float hh = Height * 0.5;
    
    // To allow the humps to sit on top, we define the box part slightly lower
    // We want the total visual height to be roughly 'Height'
    // Let's place the main box body
    float bodyHeight = hh - TopHumpRadius * 0.5; 
    float2 boxSize = float2(hw, bodyHeight);
    
    // Shift body down slightly so the humps align with the intended top
    float2 pBox = p - float2(0.0, -TopHumpRadius * 0.5);
    
    // Box with rounded bottom corners only (top corners sharp-ish or small radius)
    // We use a small epsilon for top corners to keep SDF valid, or 0.0
    float4 corners = float4(0.01, BottomCornerRadius, 0.01, BottomCornerRadius);
    float dBody = sdRoundedBox(pBox, boxSize, corners);
    
    // Top Humps
    // Two circles placed at the top corners of the box
    float humpOffset = max(0.0, hw - TopHumpRadius);
    float humpY = bodyHeight - TopHumpRadius * 0.5; // Align with top of box
    
    float2 cLeft = float2(-humpOffset, humpY);
    float2 cRight = float2(humpOffset, humpY);
    
    float dLeftHump = length(pBox - cLeft) - TopHumpRadius;
    float dRightHump = length(pBox - cRight) - TopHumpRadius;
    
    // Combine: The toast is the union of the body and the two humps
    // Use smin for the "smooth central dip"
    float dHumps = smin(dLeftHump, dRightHump, TopCurveSmoothing);
    
    // Final Shape SDF
    float dShape = smin(dBody, dHumps, 0.02); 

    // 3. Analytic Anti-Aliasing width
    float aa = fwidth(dShape);
    
    // 4. Calculate Bubbles/Holes (Voronoi/Grid Pattern)
    // Only compute where we are roughly inside the bread to save cost
    float dHoles = 1.0;
    if (dShape < CrustThickness + 0.1) {
        // Scale UVs for tiling
        float2 holeUV = UV * HoleDensity;
        float2 id = floor(holeUV);
        float2 gv = frac(holeUV) - 0.5;
        
        // Check 3x3 neighbors to handle holes crossing cell boundaries
        float minHoleDist = 100.0;
        for(int y = -1; y <= 1; y++) {
            for(int x = -1; x <= 1; x++) {
                float2 offs = float2(x, y);
                float2 cellID = id + offs;
                
                // Randomize position and size
                float2 rand = hash22(cellID);
                float sizeMod = lerp(1.0, 0.5, rand.y * HoleVariance); // Variance
                float currentHoleSize = HoleSize * sizeMod;
                
                // Jitter position (-0.5 to 0.5 range)
                float2 posJitter = (hash22(cellID + 13.37) - 0.5) * 0.8;
                
                float dist = length(gv - offs - posJitter) - currentHoleSize;
                minHoleDist = min(minHoleDist, dist);
            }
        }
        dHoles = minHoleDist;
    }

    // 5. Layering & Coloring
    
    // -- Mask for the main body fill --
    float fillAlpha = 1.0 - smoothstep(-aa, aa, dShape);
    
    // -- Mask for the Outline (Stroke) --
    // Outline is drawn centered on the edge or outside? 
    // "distinct thick outer crust border" implies internal feature, "stroke" implies external outline.
    // Let's draw stroke centered on edge.
    float halfStroke = StrokeWidth * 0.5;
    float strokeAlpha = 1.0 - smoothstep(0.0, aa, abs(dShape) - halfStroke);
    float4 strokeLayer = float4(StrokeColor.rgb, StrokeColor.a * strokeAlpha);
    
    // -- Internal Fill Logic --
    // Mix Bread and Crust based on SDF distance
    // Crust is the area near the edge (dShape > -CrustThickness)
    float crustMask = smoothstep(-CrustThickness - aa, -CrustThickness + aa, dShape);
    // But strictly inside the shape
    crustMask *= fillAlpha; 
    
    float4 baseFill = lerp(BreadColor, CrustColor, crustMask);
    
    // -- Apply Holes --
    // Holes only appear on the bread part (inner), not the crust rim ideally, or maybe both.
    // Usually holes are in the soft part.
    // Hole mask: Inside hole SDF
    float holeMask = 1.0 - smoothstep(-aa, aa, dHoles);
    // Mask out holes that overlap the crust or outline too much if desired, 
    // but simple composition is holes exist everywhere on bread.
    // Let's restrict holes to inner bread (not crust)
    holeMask *= (1.0 - crustMask);
    
    float4 finalFill = lerp(baseFill, HoleColor, holeMask * HoleColor.a);
    finalFill.a *= fillAlpha; // Apply shape alpha

    // -- Composite Stroke over Fill --
    outColor = over(strokeLayer, finalFill);
}