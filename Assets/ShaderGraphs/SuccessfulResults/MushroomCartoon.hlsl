#ifndef PI
#define PI 3.14159265359
#endif

// Pseudo-random hash for spot generation
float2 mushroom_hash22(float2 p) {
    float3 p3 = frac(float3(p.xyx) * float3(.1031, .1030, .0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return frac((p3.xx + p3.yz) * p3.zy);
}

void MushroomCartoon_float(float2 UV, float2 Center, float2 StemSize, float2 CapSize, float4 StemColor, float4 CapColor, float4 SpotColor, float SpotDensity, float SpotRadius, out float4 outColor) {
    // PLAN:
    // 1. Center the UV coordinates.
    // 2. Define the Stem SDF (Capsule/Segment) positioned below the cap center.
    // 3. Define the Cap SDF (Semi-Ellipse) positioned at the center.
    // 4. Generate Spots using a jittered grid pattern mapped onto the Cap's coordinate space.
    // 5. Compute alpha masks using smoothstep for anti-aliasing.
    // 6. Layer colors: Stem background, Cap foreground, Spots on top of Cap.
    // 7. Output final composited color.

    // 1. Center Coordinates
    float2 p = UV - Center;

    // --- STEM SHAPE ---
    // Modeled as a vertical capsule (line segment with radius)
    // StemSize.x = Radius (Thickness), StemSize.y = Length
    // Start the stem slightly inside the cap to avoid gaps
    float stemTopY = -CapSize.y * 0.1;
    float stemBottomY = stemTopY - max(StemSize.y, 0.0);
    
    float2 pa = p - float2(0.0, stemTopY);
    float2 ba = float2(0.0, stemBottomY) - float2(0.0, stemTopY);
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    // SDF for stem (negative inside)
    float dStem = length(pa - ba * h) - StemSize.x;

    // --- CAP SHAPE ---
    // Modeled as a semi-ellipse
    // Normalize p by CapSize to work in unit circle space, then scale back distance estimate
    float2 radii = max(CapSize, 0.001);
    float2 q = p;
    // Offset geometric center slightly up for visual balance
    q.y -= radii.y * 0.2;
    
    // Ellipse SDF approximation
    float dEllipse = length(q / radii) - 1.0;
    // Fix distance metric roughly by multiplying by the smallest axis
    dEllipse *= min(radii.x, radii.y);
    
    // Cut the bottom of the ellipse to make a mushroom cap shape
    // Plane equation: y > -offset
    float cutPlaneY = -radii.y * 0.05;
    float dCut = -(q.y - cutPlaneY);
    
    // Final Cap SDF: Intersection of Ellipse and Plane
    float dCap = max(dEllipse, dCut);

    // --- SPOTS GENERATION ---
    // Map spots based on normalized cap coordinates for consistency
    // Scale UVs for density
    float2 spotUV = (p / radii) * SpotDensity;
    float2 i_st = floor(spotUV);
    float2 f_st = frac(spotUV);
    
    float minSpotDist = 10.0;
    
    // 3x3 neighbor search for jittered grid spots (Voronoi-like placement)
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            float2 neighbor = float2(x, y);
            // Random position inside the cell
            float2 pointInCell = mushroom_hash22(i_st + neighbor);
            // Animate position slightly or keep static? Static is safer.
            // Map 0..1 random to -0.5..0.5 jitter
            float2 jitter = 0.5 + 0.4 * sin(pointInCell * 6.2831);
            
            float2 diff = neighbor + jitter - f_st;
            float dist = length(diff);
            minSpotDist = min(minSpotDist, dist);
        }
    }
    
    // SDF for spots (Circle radius in grid space)
    // SpotRadius input defines size relative to grid cell
    float dSpots = minSpotDist - SpotRadius;

    // --- COMPOSITING ---
    // Calculate Anti-Aliasing width
    float aa = fwidth(length(p));
    if (aa == 0) aa = 0.005;

    // 1. Stem Layer
    float stemMask = 1.0 - smoothstep(-aa, aa, dStem);
    float4 stemLayer = float4(StemColor.rgb, StemColor.a * stemMask);

    // 2. Cap Layer
    float capMask = 1.0 - smoothstep(-aa, aa, dCap);
    
    // 3. Spots Layer (Masked by Cap)
    // Smoothstep spots for softness
    float spotMask = 1.0 - smoothstep(-aa, aa, dSpots);
    // Clip spots to be only inside the cap
    spotMask *= capMask;
    
    // Blend Spot Color onto Cap Color
    float3 capFillRGB = lerp(CapColor.rgb, SpotColor.rgb, spotMask * SpotColor.a);
    float4 capLayer = float4(capFillRGB, CapColor.a * capMask);

    // 4. Final Composite: Cap over Stem
    // Porter-Duff 'Source Over' blending
    // out = src + dst * (1 - src.a)
    float finalAlpha = capLayer.a + stemLayer.a * (1.0 - capLayer.a);
    float3 finalRGB = (capLayer.rgb * capLayer.a + stemLayer.rgb * stemLayer.a * (1.0 - capLayer.a)) / max(finalAlpha, 0.0001);

    outColor = float4(finalRGB, finalAlpha);
}

// ------------------------------------------------------------------------
//  Visual Result (High-level, parameter-invariant description)
// ------------------------------------------------------------------------
//  This function generates a **stylized 2D cartoon mushroom primitive**
//  using Signed Distance Functions (SDFs).
//
//  The shape is composed of a rounded vertical stem and a wide, curved
//  mushroom cap, with optional circular spot patterns distributed across
//  the cap surface. The relative proportions of the stem and cap, the
//  placement and density of spots, color composition, scale, and visual
//  styling are fully controlled by input parameters and are not fixed by
//  the function itself.
//
//  The output is an anti-aliased RGBA color suitable for playful icons,
//  game UI elements, decorative graphics, and expressive procedural
//  2D visuals.
// ------------------------------------------------------------------------
