#ifndef PI
#define PI 3.14159265359
#endif

// Rotates a 2D vector by an angle in radians
float2 Rotate2D(float2 p, float angle) {
    float s = sin(angle);
    float c = cos(angle);
    return float2(p.x * c - p.y * s, p.x * s + p.y * c);
}

// SDF for a Line Segment with varying thickness (Tapered Capsule)
// p: sample point
// a: start point, b: end point
// r1: radius at start, r2: radius at end
float sdTaperedSegment(float2 p, float2 a, float2 b, float r1, float r2) {
    float2 ba = b - a;
    float2 pa = p - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h) - lerp(r1, r2, h);
}

// Smooth Union of two SDFs (k controls smoothness blending)
float smin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return lerp(b, a, h) - k * h * (1.0 - h);
}

void MapleLeafShape_float(
    float2 UV,
    float Scale,
    float4 LeafInnerColor,
    float4 LeafOuterColor,
    float StemLength,
    float StemWidth,
    float4 StemColor,
    float3 LobeSizes, // x=Top, y=UpperSides, z=LowerSides
    float4 VeinColor,
    float OutlineWidth,
    float4 OutlineColor,
    out float4 outColor
) {
    // PLAN:
    // 1) Normalize UV to centered coordinates [-1,1] scaled by Size.
    // 2) Construct Leaf Body using 5 distinct tapered segment SDFs (Lobes).
    // 3) Combine Lobes using smooth union for organic connections.
    // 4) Construct Veins SDF inside the lobes.
    // 5) Construct Stem SDF (tapering from base to leaf center).
    // 6) Calculate Masks with AA (Anti-Aliasing).
    // 7) Composite colors: Stem -> Leaf -> Veins -> Outline.
    
    // 1) Coordinate Setup
    float2 centered = UV - 0.5;
    // Inverse scale: larger Scale input = smaller multiplier = larger shape
    float2 p = centered * (2.0 / max(Scale, 0.001));
    
    // Anti-aliasing width relative to derivative of screen space
    float aa = fwidth(length(p));
    aa = max(aa, 0.001); // Safety clamp

    // 2) Leaf Body Construction
    float dLeaf = 100.0;
    float dVein = 100.0;
    
    // Lobe Configuration
    // Angles for the 5 hands: Top (0), Sides (~50 deg), Bottom (~115 deg)
    float angles[3] = { 0.0, 0.9, 2.05 }; 
    // Lengths from input parameters
    float lengths[3] = { LobeSizes.x, LobeSizes.y, LobeSizes.z };
    
    // Base thickness for lobes (bulge near center)
    float baseThick = 0.25;

    // -- TOP LOBE --
    float2 tip0 = float2(0.0, lengths[0]);
    // Taper from baseThick to 0.0 at tip
    float dLobe0 = sdTaperedSegment(p, float2(0.0, 0.0), tip0, baseThick, 0.0);
    dLeaf = dLobe0;
    // Top Vein (thinner, slightly shorter)
    dVein = sdTaperedSegment(p, float2(0.0, 0.05), tip0 * 0.9, 0.02, 0.002);

    // -- UPPER SIDE LOBES (Symmetry) --
    float2 pUpperR = Rotate2D(p, angles[1]); // Rotate UV left
    float2 pUpperL = Rotate2D(p, -angles[1]); // Rotate UV right
    float2 tip1 = float2(0.0, lengths[1]);
    
    float dLobe1R = sdTaperedSegment(pUpperR, float2(0.0, 0.0), tip1, baseThick * 0.9, 0.0);
    float dLobe1L = sdTaperedSegment(pUpperL, float2(0.0, 0.0), tip1, baseThick * 0.9, 0.0);
    
    float dVein1R = sdTaperedSegment(pUpperR, float2(0.0, 0.05), tip1 * 0.9, 0.02, 0.002);
    float dVein1L = sdTaperedSegment(pUpperL, float2(0.0, 0.05), tip1 * 0.9, 0.02, 0.002);

    // -- LOWER SIDE LOBES (Symmetry) --
    float2 pLowerR = Rotate2D(p, angles[2]);
    float2 pLowerL = Rotate2D(p, -angles[2]);
    float2 tip2 = float2(0.0, lengths[2]);

    float dLobe2R = sdTaperedSegment(pLowerR, float2(0.0, 0.0), tip2, baseThick * 0.8, 0.0);
    float dLobe2L = sdTaperedSegment(pLowerL, float2(0.0, 0.0), tip2, baseThick * 0.8, 0.0);
    
    float dVein2R = sdTaperedSegment(pLowerR, float2(0.0, 0.05), tip2 * 0.9, 0.02, 0.002);
    float dVein2L = sdTaperedSegment(pLowerL, float2(0.0, 0.05), tip2 * 0.9, 0.02, 0.002);

    // 3) Combine Lobes (Smooth Union)
    float blend = 0.2; // Blend factor for organic joint
    dLeaf = smin(dLeaf, dLobe1R, blend);
    dLeaf = smin(dLeaf, dLobe1L, blend);
    dLeaf = smin(dLeaf, dLobe2R, blend);
    dLeaf = smin(dLeaf, dLobe2L, blend);

    // Combine Veins (Sharp Union is fine)
    dVein = min(dVein, min(dVein1R, dVein1L));
    dVein = min(dVein, min(dVein2R, dVein2L));

    // 4) Stem Construction
    // Taper from Thick Base (bottom) to Thin Top (connection point)
    float2 stemBase = float2(0.0, -StemLength);
    float2 stemTop = float2(0.0, 0.0);
    // Base radius = StemWidth, Top radius = 30% of width
    float dStem = sdTaperedSegment(p, stemBase, stemTop, StemWidth, StemWidth * 0.3);

    // 5) Masks & AA
    float leafMask = smoothstep(aa, -aa, dLeaf);
    float stemMask = smoothstep(aa, -aa, dStem);
    // Veins are clipped to be inside the leaf
    float veinMask = smoothstep(aa, -aa, dVein) * leafMask;
    // Outline is a band centered on the leaf edge
    float outlineEdge = abs(dLeaf) - (OutlineWidth * 0.5);
    float outlineMask = smoothstep(aa, -aa, outlineEdge);

    // 6) Shading & Composition
    // Gradient Factor: 0 at center, 1 at tips
    float gradT = saturate(length(p) * 0.8);
    float4 bodyColor = lerp(LeafInnerColor, LeafOuterColor, gradT);

    // Start with background (transparent)
    float3 finalRGB = float3(0,0,0);
    float finalAlpha = 0.0;

    // Layer 1: Stem (Behind)
    finalRGB = lerp(finalRGB, StemColor.rgb, stemMask * StemColor.a);
    finalAlpha = max(finalAlpha, stemMask * StemColor.a);

    // Layer 2: Leaf Body
    finalRGB = lerp(finalRGB, bodyColor.rgb, leafMask * bodyColor.a);
    finalAlpha = max(finalAlpha, leafMask * bodyColor.a);

    // Layer 3: Veins
    finalRGB = lerp(finalRGB, VeinColor.rgb, veinMask * VeinColor.a);
    
    // Layer 4: Outline (On top)
    finalRGB = lerp(finalRGB, OutlineColor.rgb, outlineMask * OutlineColor.a);
    finalAlpha = max(finalAlpha, outlineMask * OutlineColor.a);

    outColor = float4(finalRGB, finalAlpha);
}