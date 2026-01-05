#ifndef PI
#define PI 3.14159265359
#endif

// --- Helper Functions ---

// Signed distance to a box (2D)
float hg_sdBox(float2 p, float2 b) {
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// Signed distance to a rounded box (2D) with uniform radius
float hg_sdRoundedBox(float2 p, float2 b, float r) {
    float2 q = abs(p) - b + r;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

// Smooth minimum for connecting shapes (Glass blowing effect)
float hg_smin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return lerp(b, a, h) - k * h * (1.0 - h);
}

// Alpha blending helper (src over dst)
float4 hg_over(float4 src, float4 dst) {
    float a = src.a + dst.a * (1.0 - src.a);
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-6);
    return float4(c, a);
}

// --- Main Shader Function ---
// Draws a cartoon hourglass with adjustable glass bulbs, neck, caps, and dynamic sand levels.
void HourglassIcon_float(
    float2 UV,
    float Size,
    float2 BulbSize,       // Width, Height of the bulbs
    float BulbRadius,      // Roundness of the bulbs
    float2 NeckSize,       // Width, Height of the connecting neck
    float2 CapSize,        // Width, Height of the top/bottom plates
    float2 SandLevels,     // x = Top Level (0-1), y = Bottom Pile Height (0-1)
    float StreamWidth,
    float StrokeWidth,
    float4 GlassColor,
    float4 SandColor,
    float4 CapColor,
    float4 StrokeColor,
    out float4 outColor)
{
    // 1. Center and Scale UVs
    float2 p = (UV - 0.5) * 2.0;
    p /= max(Size, 0.001);

    // 2. Define Dimensions
    // Half-extents for SDFs
    float2 bulbHalf = BulbSize * 0.5;
    float2 neckHalf = NeckSize * 0.5;
    float2 capHalf = CapSize * 0.5;
    
    // Vertical positioning
    // The neck is centered at 0. The bulbs sit above and below the neck.
    // Bulb Center Y = NeckHalfHeight + BulbHalfHeight
    float bulbCenterY = neckHalf.y + bulbHalf.y;
    float totalGlassHeight = neckHalf.y * 2.0 + bulbHalf.y * 2.0;
    
    // Cap Center Y = Top of bulb + Half Cap Height
    float capCenterY = neckHalf.y + BulbSize.y + capHalf.y;

    // 3. Glass Body SDF (Symmetric vertically and horizontally)
    float2 pSym = float2(abs(p.x), abs(p.y));
    
    // Neck SDF
    float dNeck = hg_sdBox(p, neckHalf);
    
    // Bulb SDF (Shifted vertically)
    // We use symmetry on Y, so we only define the top bulb, mirroring handles the bottom.
    float dBulb = hg_sdRoundedBox(pSym - float2(0.0, bulbCenterY), bulbHalf, BulbRadius);
    
    // Smooth Union for glass body
    float dGlassBody = hg_smin(dNeck, dBulb, 0.02);
    
    // 4. Cap Plates SDF
    // Shifted to sit on top/bottom
    float dCaps = hg_sdBox(float2(p.x, pSym.y - capCenterY), capHalf);

    // 5. Sand Logic
    // We need to determine where the sand is relative to the *insides* of the glass.
    // Glass Inner Boundary approx = dGlassBody + StrokeWidth/2 (assuming stroke is centered)
    // But for a clean cartoon look, we'll just check if we are 'inside' the glass shape.
    float glassInnerMask = step(dGlassBody, 0.0); 
    
    // Top Sand: Defined by a horizontal cut level
    // Map SandLevels.x (0-1) to the bulb's vertical range
    float bulbBottomY = neckHalf.y;
    float bulbTopY = neckHalf.y + BulbSize.y;
    float topSandY = lerp(bulbBottomY, bulbTopY, SandLevels.x);
    float isTopSand = step(p.y, topSandY) * step(0.0, p.y); // Only in top half
    
    // Bottom Sand: A pile shape
    // Simple triangular/conical pile equation: Y < Base + Height - |X|*Slope
    float pileHeight = SandLevels.y * BulbSize.y;
    float pileBase = -bulbTopY;
    // Slope logic: Pile goes to 0 height at the edge of the bulb width
    float pileSlope = pileHeight / max(bulbHalf.x, 0.001);
    float pileY = pileBase + pileHeight - abs(p.x) * 1.5; // 1.5 arbitrary slope factor for aesthetic
    // Smooth min to round the top of the pile slightly
    float isBottomSand = step(p.y, pileY) * step(p.y, 0.0); // Only in bottom half
    
    // Stream: Vertical line connecting top sand to bottom pile
    // Exists only if there is sand in the top (SandLevels.x > 0.01)
    float dStream = hg_sdBox(p - float2(0.0, (topSandY + pileBase)/2.0), float2(StreamWidth * 0.5, (topSandY - pileBase)/2.0));
    float isStream = step(dStream, 0.0) * step(p.y, topSandY) * step(pileY, p.y) * step(0.01, SandLevels.x);
    
    // Combine Sand
    // Mask sand by the glass shape to keep it inside
    float sandShape = max(isTopSand, max(isBottomSand, isStream));
    float dSand = dGlassBody; // Reuse glass SDF for clipping
    // Refined Sand Mask: Inside glass AND inside sand definition
    // We use smoothstep on SDF for soft AA clipping of the sand at glass edges
    float aa = fwidth(dGlassBody);
    float sandCoverage = sandShape * (1.0 - smoothstep(-aa, 0.0, dGlassBody + StrokeWidth * 0.5));

    // 6. Rendering / Compositing
    
    // A. Glass Body Fill
    float glassBodyAlpha = 1.0 - smoothstep(0.0, aa, dGlassBody);
    float4 layerGlass = float4(GlassColor.rgb, GlassColor.a * glassBodyAlpha);
    
    // B. Sand Fill (On top of Glass Fill)
    float4 layerSand = float4(SandColor.rgb, SandColor.a * sandCoverage);
    float4 comp1 = hg_over(layerSand, layerGlass);
    
    // C. Glass Outline
    float halfStroke = StrokeWidth * 0.5;
    float glassOutline = abs(dGlassBody) - halfStroke;
    float glassOutlineAlpha = 1.0 - smoothstep(0.0, aa, glassOutline);
    // To make outline clean, we usually draw it *over* the fill, but mask the inner part if we want 'stroke only'
    // Here we want a solid cartoon stroke on top.
    // However, the stroke center is at d=0. We want the stroke to cover the edge.
    float4 layerGlassStroke = float4(StrokeColor.rgb, StrokeColor.a * glassOutlineAlpha);
    // To avoid double-blending internal fill, we can just blend stroke over comp1
    float4 comp2 = hg_over(layerGlassStroke, comp1);
    
    // D. Caps Fill
    float aaCap = fwidth(dCaps);
    float capFillAlpha = 1.0 - smoothstep(0.0, aaCap, dCaps);
    float4 layerCapFill = float4(CapColor.rgb, CapColor.a * capFillAlpha);
    float4 comp3 = hg_over(layerCapFill, comp2);
    
    // E. Caps Outline
    float capOutline = abs(dCaps) - halfStroke;
    float capOutlineAlpha = 1.0 - smoothstep(0.0, aaCap, capOutline);
    float4 layerCapStroke = float4(StrokeColor.rgb, StrokeColor.a * capOutlineAlpha);
    float4 finalComp = hg_over(layerCapStroke, comp3);

    outColor = finalComp;
}

// ------------------------------------------------------------------------
//  Visual Result
// ------------------------------------------------------------------------
//  This function generates a **stylized cartoon hourglass icon** using 
//  Signed Distance Functions (SDFs).
//
//  The visual result is composed of:
//  - A glass body formed by two symmetric, rounded **bulbs** connected by a
//    thin vertical **neck**.
//  - Two flat horizontal **caps** (plates) sealing the top and bottom of the glass.
//  - Dynamic **sand** fills inside the bulbs:
//      - The top level is cut horizontally.
//      - The bottom pile forms a conical mound.
//      - A vertical stream connects the two when sand is present in the top.
//
//  The shape features extensive parameter controls for the bulb size and 
//  roundness, neck dimensions, cap size, and the specific levels of sand 
//  in the top and bottom chambers.
//
//  The output is a flat-shaded graphic with a thick, cohesive outline around
//  the glass and caps, suitable for loading screens, timer indicators, or 
//  game UI.
// ------------------------------------------------------------------------