#ifndef PI
#define PI 3.14159265359
#endif

// --- Helpers ---

// Random hash for jittered grid
float2 mush_hash22(float2 p) {
    float3 p3 = frac(float3(p.xyx) * float3(.1031, .1030, .0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return frac((p3.xx + p3.yz) * p3.zy);
}

// Source Over blending
float4 mush_over(float4 src, float4 dst) {
    float a = src.a + dst.a * (1.0 - src.a);
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-8);
    return float4(c, a);
}

// Renders a filled shape with an outer stroke based on its SDF
float4 mush_renderLayer(float d, float4 fill, float4 stroke, float strokeWidth, float aa) {
    float totalAlpha = 1.0 - smoothstep(-aa, aa, d - strokeWidth);
    float fillMix = 1.0 - smoothstep(-aa, aa, d);
    float3 rgb = lerp(stroke.rgb, fill.rgb, fillMix);
    return float4(rgb, totalAlpha * fill.a);
}

// Gradient-corrected Ellipse SDF for perfectly uniform stroke width
float mush_sdEllipse(float2 p, float2 ab) {
    ab = max(ab, 0.0001);
    float2 p_ab = abs(p) / ab;
    float l = length(p_ab);
    if (l < 0.0001) return -min(ab.x, ab.y);
    float d = l - 1.0;
    float2 grad = p_ab / (ab * l);
    return d / length(grad);
}

// Stylized Grass Blade SDF
float mush_sdBlade(float2 p, float2 root, float height, float width, float bend) {
    p -= root;
    p.x -= bend * (p.y / max(height, 0.001)) * (p.y / max(height, 0.001));
    
    float t = saturate(p.y / max(height, 0.001));
    float localW = width * (1.0 - t * t);
    
    float dx = abs(p.x) - localW;
    float dy = max(-p.y, p.y - height);
    return length(max(float2(dx, dy), 0.0)) + min(max(dx, dy), 0.0);
}

// Grass Group Composite
float mush_sdGrassGroup(float2 p) {
    float d1 = mush_sdBlade(p, float2(-0.16, -0.40), 0.14, 0.02, -0.1);
    float d2 = mush_sdBlade(p, float2(-0.25, -0.38), 0.09, 0.015, -0.2);
    float d3 = mush_sdBlade(p, float2(0.16, -0.40), 0.12, 0.02, 0.15);
    float d4 = mush_sdBlade(p, float2(0.25, -0.38), 0.08, 0.015, 0.2);
    return min(min(d1, d2), min(d3, d4));
}

// --- Main Shader ---
void MushroomProcedural_float(
    float2 UV,
    float2 CapSize,
    float CapCurve,
    float2 InnerCapSize,
    float InnerCapOffset,
    float StemWidth,
    float StemHeight,
    float BodyCurve,
    float SpotsDensity,
    float SpotsSize,
    float4 BackgroundColor,
    float4 GroundColor,
    float4 GrassColor,
    float4 StemColor,
    float4 InnerCapColor,
    float4 CapColor,
    float4 SpotsColor,
    float4 StrokeColor,
    float StrokeWidth,
    out float4 outColor
) {
    // 1. Coordinates and AA
    float2 p = UV - float2(0.5, 0.5);
    float aa = fwidth(p.x) * 1.5;
    if (aa == 0.0) aa = 0.005;

    outColor = BackgroundColor;

    // 2. Ground Shadow Patch
    float dGround = mush_sdEllipse(float2(p.x, p.y + 0.40), float2(0.35, 0.05));
    float groundAlpha = 1.0 - smoothstep(-aa, aa, dGround);
    outColor = mush_over(float4(GroundColor.rgb, GroundColor.a * groundAlpha), outColor);

    // 3. Inner Cap (Dark Red Underside)
    float2 icP = p;
    icP.y -= InnerCapOffset;
    icP.y += CapCurve * (icP.x / max(InnerCapSize.x, 0.001)) * (icP.x / max(InnerCapSize.x, 0.001));
    float dInner = mush_sdEllipse(icP, InnerCapSize);
    
    // Inner Cap Stripes (Gills)
    float angle = atan2(p.y - InnerCapOffset, abs(p.x));
    float stripePattern = abs(frac(angle * 8.0) - 0.5);
    float stripeMask = 1.0 - smoothstep(0.01, 0.05, stripePattern);
    float3 innerRGB = lerp(InnerCapColor.rgb, StrokeColor.rgb, stripeMask * 0.7);
    float4 innerDynamicColor = float4(innerRGB, InnerCapColor.a);
    
    outColor = mush_over(mush_renderLayer(dInner, innerDynamicColor, StrokeColor, StrokeWidth, aa), outColor);

    // 4. Stem (White Body)
    float topY = 0.02;
    float bottomY = topY - StemHeight;
    float tStem = saturate((topY - p.y) / max(StemHeight, 0.001));
    float wStem = StemWidth * (1.0 + BodyCurve * tStem * tStem);
    float clY = clamp(p.y, bottomY, topY);
    float dStem = length(float2(p.x, p.y) - float2(0.0, clY)) - wStem;
    
    // Stem Shadows (Ambient Occlusion at top, ground dirt at bottom)
    float stemTopShadow = 1.0 - smoothstep(0.0, 0.1, topY - p.y);
    float stemBotShadow = 1.0 - smoothstep(0.0, 0.15, p.y - bottomY);
    float stemShadow = max(stemTopShadow, stemBotShadow);
    float3 stemRGB = lerp(StemColor.rgb, float3(0.8, 0.75, 0.65), stemShadow * 0.6);
    
    outColor = mush_over(mush_renderLayer(dStem, float4(stemRGB, StemColor.a), StrokeColor, StrokeWidth, aa), outColor);

    // 5. Main Cap (Red Dome)
    float2 abCap = CapSize;
    abCap.x += min(0.0, p.y) * 0.5; // Slight inward taper at the bottom edges
    float dDome = mush_sdEllipse(float2(p.x, max(0.0, p.y)), abCap);
    float dCut = -CapCurve * (p.x / max(CapSize.x, 0.001)) * (p.x / max(CapSize.x, 0.001)) - p.y;
    float dCap = max(dDome, dCut);

    // Cap Spots Generation
    float2 spotUV = p * SpotsDensity;
    float2 i_st = floor(spotUV);
    float2 f_st = frac(spotUV);
    float minDist = 10.0;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            float2 neighbor = float2(x, y);
            float2 cellHash = mush_hash22(i_st + neighbor);
            float2 jitter = 0.5 + 0.3 * sin(cellHash * 6.2831);
            float2 diff = neighbor + jitter - f_st;
            float dist = length(diff);
            float spotRadius = SpotsSize * (0.6 + 0.4 * cellHash.x);
            minDist = min(minDist, dist - spotRadius);
        }
    }
    float dSpots = minDist / max(SpotsDensity, 0.001);
    
    // Mask spots to be strictly inside the Cap stroke
    float spotsAlpha = 1.0 - smoothstep(-aa, aa, dSpots);
    float capInsideMask = 1.0 - smoothstep(-aa, aa, dCap + StrokeWidth + 0.01);
    spotsAlpha *= capInsideMask;
    
    float3 capBaseRGB = lerp(CapColor.rgb, SpotsColor.rgb, spotsAlpha * SpotsColor.a);
    float4 capDynamicColor = float4(capBaseRGB, CapColor.a);

    outColor = mush_over(mush_renderLayer(dCap, capDynamicColor, StrokeColor, StrokeWidth, aa), outColor);

    // 6. Grass Base
    float dGrass = mush_sdGrassGroup(p);
    outColor = mush_over(mush_renderLayer(dGrass, GrassColor, StrokeColor, StrokeWidth, aa), outColor);
}
