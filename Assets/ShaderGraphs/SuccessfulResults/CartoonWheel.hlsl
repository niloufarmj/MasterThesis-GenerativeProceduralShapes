#ifndef PI
#define PI 3.14159265359
#endif

#ifndef OVER_HELPER
#define OVER_HELPER
// Helper: Porter-Duff "Over" operator for blending layers
// src is the top layer, dst is the bottom layer
inline float4 nm_over(float4 src, float4 dst)
{
    float a = src.a + dst.a * (1.0 - src.a);
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-8);
    return float4(c, a);
}
#endif

void CartoonWheel_float(float2 UV, float Radius, float RingThickness, float SpokeCount, float SpokeWidth, float CenterRadius, float4 CenterColor, float4 SpokeColor, float4 RingColor, out float4 outColor)
{
    // PLAN:
    // 1. Center UV coordinates to (0,0).
    // 2. Define SDFs for: Spokes (radial repetition), Ring (annulus), and Center (circle).
    // 3. Calculate anti-aliasing factor based on screen derivatives.
    // 4. Composite the layers using the painter's algorithm (Center over Ring over Spokes).
    
    float2 p = UV - 0.5;
    
    // Analytic AA factor (width of the transition area)
    float aa = fwidth(length(p));
    if (aa < 0.0001) aa = 0.001; // Safety fallback for previews

    // --- 1. Spokes SDF ---
    // Radial repetition logic
    float n = max(SpokeCount, 1.0);
    float an = 2.0 * PI / n;
    
    // Calculate angle and identify sector
    float angle = atan2(p.y, p.x);
    float sector = floor(angle / an + 0.5);
    float sectorAngle = sector * an;
    
    // Rotate p into the canonical sector space (aligning spoke with X axis)
    float c = cos(sectorAngle);
    float s = sin(sectorAngle);
    float2 pRot = float2(c * p.x + s * p.y, -s * p.x + c * p.y);
    
    // Signed Distance for a straight spoke (box of infinite length along X, finite width along Y)
    float dSpokeRaw = abs(pRot.y) - SpokeWidth * 0.5;
    // Intersection: Clip the spokes to be strictly inside the outer radius
    float dSpoke = max(dSpokeRaw, length(p) - Radius);

    // --- 2. Outer Ring SDF ---
    // Annulus shape: distance from the middle of the ring minus half thickness
    float rMid = Radius - RingThickness * 0.5;
    float dRing = abs(length(p) - rMid) - RingThickness * 0.5;

    // --- 3. Center Hub SDF ---
    // Simple circle
    float dCenter = length(p) - CenterRadius;

    // --- 4. Layer Masks ---
    // Generate smooth masks for each part using SDFs
    float aSpoke = 1.0 - smoothstep(-aa, aa, dSpoke);
    float aRing = 1.0 - smoothstep(-aa, aa, dRing);
    float aCenter = 1.0 - smoothstep(-aa, aa, dCenter);

    // --- 5. Layer Colors ---
    // Prepare RGBA layers (Straight alpha assumption, modulated by shape mask)
    float4 lSpoke = float4(SpokeColor.rgb, SpokeColor.a * aSpoke);
    float4 lRing = float4(RingColor.rgb, RingColor.a * aRing);
    float4 lCenter = float4(CenterColor.rgb, CenterColor.a * aCenter);

    // --- 6. Composition ---
    // Stack layers: Background < Spokes < Ring < Center
    // This ensures the ring covers the spoke ends, and center covers spoke starts
    float4 comp = lSpoke;
    comp = nm_over(lRing, comp);   // Draw Ring over Spokes
    comp = nm_over(lCenter, comp); // Draw Center over Ring/Spokes

    outColor = comp;
}

// ------------------------------------------------------------------------
//  Visual Result (High-level, parameter-invariant description)
// ------------------------------------------------------------------------
//  This function generates a **stylized 2D cartoon wheel primitive**
//  using Signed Distance Functions (SDFs).
//
//  The visual result consists of three layered components: a circular
//  outer ring forming the wheel rim, multiple evenly distributed straight
//  radial spokes extending inward from the rim, and a solid circular
//  center hub. The spokes are clipped so they remain inside the rim,
//  and the hub visually covers the inner ends of the spokes, creating
//  a clean, layered wheel silhouette.
//
//  The wheel radius, rim thickness, number of spokes, spoke width,
//  center hub size, color composition, scale, rotation, and placement
//  are fully controlled by input parameters and are not fixed by the
//  function itself.
//
//  The output is an anti-aliased RGBA color suitable for icons,
//  mechanical symbols, decorative UI elements, and analytic procedural
//  2D graphics.
// ------------------------------------------------------------------------
