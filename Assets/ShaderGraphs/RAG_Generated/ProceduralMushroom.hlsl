#ifndef PI
#define PI 3.14159265359
#endif

#ifndef MUSHROOM_HELPERS
#define MUSHROOM_HELPERS

float mush_smax(float a, float b, float k) {
    k = max(k, 1e-5);
    float h = clamp(0.5 + 0.5 * (a - b) / k, 0.0, 1.0);
    return lerp(b, a, h) + k * h * (1.0 - h);
}

float2 mush_hash22(float2 p) {
    float3 p3 = frac(float3(p.xyx) * float3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return frac((p3.xx + p3.yz) * p3.zy);
}

float4 mush_over(float4 src, float4 dst) {
    float a = src.a + dst.a * (1.0 - src.a);
    if (a < 1e-6) return float4(0.0, 0.0, 0.0, 0.0);
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / a;
    return float4(c, a);
}

float4 mush_getShapeWithStroke(float d, float4 fillColor, float4 strokeColor, float strokeWidth, float aa) {
    float fillAlpha = 1.0 - smoothstep(0.0, aa, d);
    float outerAlpha = 1.0 - smoothstep(0.0, aa, d - max(strokeWidth, 0.0));
    
    float a0 = fillColor.a * fillAlpha;
    float3 c0 = fillColor.rgb * a0;
    
    float a1 = strokeColor.a * outerAlpha;
    float3 c1 = strokeColor.rgb * a1;
    
    float outA = a0 + a1 * (1.0 - a0);
    float3 outC = float3(0.0, 0.0, 0.0);
    if (outA > 1e-6) {
        outC = (c0 + c1 * (1.0 - a0)) / outA;
    }
    
    return float4(outC, outA);
}

#endif

void ProceduralMushroom_float(
    float2 UV,
    float CapLength,
    float CapHeight,
    float CapCurve,
    float CapEdgeRoundness,
    float InnerCapLength,
    float InnerCapHeight,
    float InnerCapCurve,
    float BodyHeight,
    float BodyWidth,
    float BodyCurve,
    float SpotsDensity,
    float SpotsSize,
    float4 CapColor,
    float4 InnerCapColor,
    float4 BodyColor,
    float4 SpotsColor,
    float StrokeWidth,
    float4 StrokeColor,
    out float4 outColor
) {
    float4 result = float4(0.0, 0.0, 0.0, 0.0);
    
    // --- BODY (Stem) ---
    float2 pBody = UV - float2(0.5, 0.6 - BodyHeight * 0.5);
    float bodyHNorm = clamp(pBody.y / max(BodyHeight, 0.001) + 0.5, 0.0, 1.0);
    pBody.x -= BodyCurve * sin(bodyHNorm * PI);
    
    float bodyHalfH = max(BodyHeight, 0.0) * 0.5;
    pBody.y -= clamp(pBody.y, -bodyHalfH, bodyHalfH);
    float dBody = length(pBody) - BodyWidth * 0.5;
    
    float aaB = max(fwidth(dBody), 0.001);
    float4 bodyLayer = mush_getShapeWithStroke(dBody, BodyColor, StrokeColor, StrokeWidth, aaB);
    result = mush_over(bodyLayer, result);
    
    // --- INNER CAP ---
    float2 pInner = UV - float2(0.5, 0.6);
    pInner.y += InnerCapCurve * (pInner.x * pInner.x);
    float dInnerBase = length(pInner / max(float2(InnerCapLength, InnerCapHeight), 0.001)) - 1.0;
    float dInner = dInnerBase * min(InnerCapLength, InnerCapHeight);
    
    float aaI = max(fwidth(dInner), 0.001);
    float4 innerLayer = mush_getShapeWithStroke(dInner, InnerCapColor, StrokeColor, StrokeWidth, aaI);
    result = mush_over(innerLayer, result);
    
    // --- CAP ---
    float2 pCap = UV - float2(0.5, 0.6);
    float bentY = pCap.y + CapCurve * (pCap.x * pCap.x);
    float dCapBase = length(float2(pCap.x, bentY) / max(float2(CapLength, CapHeight), 0.001)) - 1.0;
    dCapBase *= min(CapLength, CapHeight);
    
    float capCutoffY = pCap.y + InnerCapCurve * (pCap.x * pCap.x);
    float dCap = mush_smax(dCapBase, -capCutoffY, CapEdgeRoundness);
    
    float aaC = max(fwidth(dCap), 0.001);
    float4 capLayer = mush_getShapeWithStroke(dCap, CapColor, StrokeColor, StrokeWidth, aaC);
    result = mush_over(capLayer, result);
    
    // --- SPOTS ---
    float2 pSpots = UV - float2(0.5, 0.6);
    float spotBentY = pSpots.y + CapCurve * (pSpots.x * pSpots.x);
    float2 spotUV = float2(pSpots.x / max(CapLength, 0.001), spotBentY / max(CapHeight, 0.001)) * max(SpotsDensity, 1e-3);
    float2 id = floor(spotUV);
    
    float dSpot = 999.0;
    for(int y=-1; y<=1; y++) {
        for(int x=-1; x<=1; x++) {
            float2 neighborId = id + float2(x, y);
            float2 h = mush_hash22(neighborId);
            float2 offset = (h - 0.5) * 0.7; 
            float2 center = neighborId + 0.5 + offset;
            float dist = length(spotUV - center) - SpotsSize * (0.5 + 0.5 * h.x);
            dSpot = min(dSpot, dist);
        }
    }
    dSpot = dSpot / max(SpotsDensity, 1e-3) * min(CapLength, CapHeight);
    
    float aaS = max(fwidth(dSpot), 0.001);
    float spotAlpha = 1.0 - smoothstep(0.0, aaS, dSpot);
    
    // Mask spots to the fill area of the Cap
    float capMask = 1.0 - smoothstep(0.0, aaC, dCap);
    spotAlpha *= capMask;
    
    float4 spotLayer = float4(SpotsColor.rgb, SpotsColor.a * spotAlpha);
    result = mush_over(spotLayer, result);
    
    outColor = result;
}
