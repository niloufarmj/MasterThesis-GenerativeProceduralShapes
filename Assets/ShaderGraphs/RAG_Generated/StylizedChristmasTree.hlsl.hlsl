#ifndef PI
#define PI 3.14159265359
#endif

// Helper: Straight-alpha compositing (Source Over Destination)
float4 SCT_blendOver(float4 src, float4 dst) {
    float a = src.a + dst.a * (1.0 - src.a);
    if (a < 1e-6) return float4(0.0, 0.0, 0.0, 0.0);
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / a;
    return float4(c, a);
}

// Helper: Signed Distance to a Triangle
float SCT_sdTriangle(float2 p, float2 p0, float2 p1, float2 p2) {
    float2 e0 = p1 - p0;
    float2 e1 = p2 - p1;
    float2 e2 = p0 - p2;

    float2 v0 = p - p0;
    float2 v1 = p - p1;
    float2 v2 = p - p2;

    float2 pq0 = v0 - e0 * clamp(dot(v0, e0) / dot(e0, e0), 0.0, 1.0);
    float2 pq1 = v1 - e1 * clamp(dot(v1, e1) / dot(e1, e1), 0.0, 1.0);
    float2 pq2 = v2 - e2 * clamp(dot(v2, e2) / dot(e2, e2), 0.0, 1.0);

    float s = sign(e0.x * e2.y - e0.y * e2.x);
    float2 d = min(min(float2(dot(pq0, pq0), s * (v0.x * e0.y - v0.y * e0.x)),
                       float2(dot(pq1, pq1), s * (v1.x * e1.y - v1.y * e1.x))),
                       float2(dot(pq2, pq2), s * (v2.x * e2.y - v2.y * e2.x)));

    return -sqrt(d.x) * sign(d.y);
}

// Helper: Signed Distance to a Rounded Box
float SCT_sdRoundBox(float2 p, float2 b, float r) {
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - r;
}

// Helper: Render a single tree tier (triangle shape)
float4 SCT_RenderTier(
    float2 p, float2 center, float w, float h, 
    float4 color, float4 stripeColor, float stripeOffset, float stripeExpand, 
    float roundness, float shadingDarken, float4 bg
) {
    float2 pLocal = p - center;
    float2 p0 = float2(0.0, h);
    float2 p1 = float2(w, -h);
    float2 p2 = float2(-w, -h);
    
    // Main Triangle
    float dMain = SCT_sdTriangle(pLocal, p0, p1, p2) - roundness;
    
    // Shadow / Stripe Triangle (offset downwards)
    float2 pShadow = pLocal - float2(0.0, -stripeOffset);
    float dShadow = SCT_sdTriangle(pShadow, p0, p1, p2) - roundness - stripeExpand;
    
    float aaMain = max(fwidth(dMain), 0.001);
    float aaShadow = max(fwidth(dShadow), 0.001);
    
    float shadowMask = 1.0 - smoothstep(-aaShadow, aaShadow, dShadow);
    float mainMask = 1.0 - smoothstep(-aaMain, aaMain, dMain);
    
    // Shading (Darken right side)
    float aaShade = max(fwidth(pLocal.x), 0.001);
    float shade = smoothstep(-aaShade, aaShade, pLocal.x);
    float4 tierColor = lerp(color, float4(color.rgb * shadingDarken, color.a), shade);
    
    // Composite Shadow over Background
    float4 shadowLayer = float4(stripeColor.rgb, stripeColor.a * shadowMask);
    float4 res = SCT_blendOver(shadowLayer, bg);
    
    // Composite Main over Shadow
    float4 mainLayer = float4(tierColor.rgb, tierColor.a * mainMask);
    res = SCT_blendOver(mainLayer, res);
    
    return res;
}

// Main Shader Function
void StylizedChristmasTree_float(
    float2 UV,
    float2 TopCenter,
    float TopWidth,
    float TopHeight,
    float4 TopColor,
    float2 MidCenter,
    float MidWidth,
    float MidHeight,
    float4 MidColor,
    float2 BotCenter,
    float BotWidth,
    float BotHeight,
    float4 BotColor,
    float Roundness,
    float4 StripeColor,
    float StripeOffset,
    float StripeExpand,
    float ShadingDarken,
    float2 TrunkCenter,
    float TrunkWidth,
    float TrunkHeight,
    float4 TrunkColor,
    out float4 outColor
) {
    // Re-center coordinates so (0.5, 0.5) is (0, 0)
    float2 p = UV - float2(0.5, 0.5);
    
    // Start with a fully transparent background
    float4 finalColor = float4(0.0, 0.0, 0.0, 0.0);
    
    // --- 1. Render Trunk (Bottom-most Layer) ---
    float2 pTrunk = p - TrunkCenter;
    float dTrunk = SCT_sdRoundBox(pTrunk, float2(TrunkWidth * 0.5, TrunkHeight * 0.5), Roundness);
    float aaTrunk = max(fwidth(dTrunk), 0.001);
    float trunkMask = 1.0 - smoothstep(-aaTrunk, aaTrunk, dTrunk);
    
    // Apply left-light/right-dark shading to trunk
    float aaTrunkShade = max(fwidth(pTrunk.x), 0.001);
    float trunkShade = smoothstep(-aaTrunkShade, aaTrunkShade, pTrunk.x);
    float4 trunkColorRes = lerp(TrunkColor, float4(TrunkColor.rgb * ShadingDarken, TrunkColor.a), trunkShade);
    float4 trunkLayer = float4(trunkColorRes.rgb, trunkColorRes.a * trunkMask);
    
    finalColor = SCT_blendOver(trunkLayer, finalColor);
    
    // --- 2. Render Bottom Tier ---
    finalColor = SCT_RenderTier(p, BotCenter, BotWidth, BotHeight, BotColor, 
                                StripeColor, StripeOffset, StripeExpand, 
                                Roundness, ShadingDarken, finalColor);
                                
    // --- 3. Render Middle Tier ---
    finalColor = SCT_RenderTier(p, MidCenter, MidWidth, MidHeight, MidColor, 
                                StripeColor, StripeOffset, StripeExpand, 
                                Roundness, ShadingDarken, finalColor);
                                
    // --- 4. Render Top Tier (Top-most Layer) ---
    finalColor = SCT_RenderTier(p, TopCenter, TopWidth, TopHeight, TopColor, 
                                StripeColor, StripeOffset, StripeExpand, 
                                Roundness, ShadingDarken, finalColor);
                                
    outColor = finalColor;
}
