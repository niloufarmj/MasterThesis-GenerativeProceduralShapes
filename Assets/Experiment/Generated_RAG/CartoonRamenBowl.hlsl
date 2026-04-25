float ramen_sdCapsule(float2 p, float2 a, float2 b, float r) {
    float2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h) - r;
}

float ramen_sdWavyLine(float2 p, float x0, float y0, float y1, float freq, float amp, float thick) {
    float y = clamp(p.y, y0, y1);
    float x = x0 + sin(y * freq) * amp;
    return length(p - float2(x, y)) - thick;
}

float ramen_sdNoodleGrid(float2 p, float count, float amp, float freq, float thick) {
    float2 p1 = p;
    p1.x += sin(p1.y * freq) * amp;
    float d1 = abs(frac(p1.x * count + 0.5) - 0.5) / count;
    
    float2 p2 = p;
    p2.y += cos(p2.x * freq) * amp;
    float d2 = abs(frac(p2.y * count + 0.5) - 0.5) / count;
    
    return min(d1, d2) - thick;
}

float4 ramen_blend(float4 top, float4 bottom) {
    float a = top.a + bottom.a * (1.0 - top.a);
    if (a < 1e-6) return float4(0, 0, 0, 0);
    float3 c = (top.rgb * top.a + bottom.rgb * bottom.a * (1.0 - top.a)) / a;
    return float4(c, a);
}

float4 ramen_render(float d, float3 fillCol, float3 outlineCol, float outlineWidth, float aa) {
    float dTotal = d - outlineWidth;
    float alphaTotal = 1.0 - smoothstep(-aa, aa, dTotal);
    float fillAlpha = 1.0 - smoothstep(-aa, aa, d);
    float3 rgb = lerp(outlineCol, fillCol, fillAlpha);
    return float4(rgb, alphaTotal);
}

void CartoonRamenBowl_float(
    float2 UV,
    float BowlWidth, float BowlHeight, float4 CeramicColor, float RimFlare, float RimThickness,
    float NoodleCount, float NoodleWaveAmp, float NoodleWaveFreq, float NoodleThickness, float4 NoodleColor, float NoodleMoundHeight,
    float2 EggPos, float EggSize, float EggRot, float4 EggWhiteColor, float4 EggYolkColor,
    float2 MeatPos, float MeatSize, float4 MeatColor, float4 MeatRingColor,
    float2 LeafPos, float LeafSize, float LeafRot, float4 LeafColor,
    float2 SteamPos, float SteamHeight, float SteamCurvature, float SteamAmp, float SteamThickness, float4 SteamColor, float SteamOpacity,
    float4 OutlineColor, float OutlineThickness,
    out float4 outColor
) {
    float2 p = UV - 0.5;
    float aa = fwidth(UV.x);
    aa = max(aa, 0.001);
    
    float4 result = float4(0, 0, 0, 0);
    
    // 1. Steam Layer (Background)
    float d_s1 = ramen_sdWavyLine(p, SteamPos.x - 0.15, SteamPos.y, SteamPos.y + SteamHeight, SteamCurvature, SteamAmp, SteamThickness);
    float d_s2 = ramen_sdWavyLine(p, SteamPos.x,       SteamPos.y + 0.05, SteamPos.y + SteamHeight + 0.05, SteamCurvature, SteamAmp * 1.2, SteamThickness * 0.8);
    float d_s3 = ramen_sdWavyLine(p, SteamPos.x + 0.15, SteamPos.y + 0.02, SteamPos.y + SteamHeight - 0.05, SteamCurvature * 0.9, SteamAmp, SteamThickness * 0.9);
    float d_steam = min(d_s1, min(d_s2, d_s3));
    
    float steam_y_norm = saturate((p.y - SteamPos.y) / max(SteamHeight, 0.01));
    float steam_fade = smoothstep(0.0, 0.2, steam_y_norm) * smoothstep(1.0, 0.6, steam_y_norm);
    
    float4 steam_layer = ramen_render(d_steam, SteamColor.rgb, OutlineColor.rgb, OutlineThickness * 0.5, aa);
    steam_layer.a *= steam_fade * SteamOpacity;
    result = ramen_blend(steam_layer, result);
    
    // Base coordinates for bowl
    float bowl_y_center = -0.15;
    float2 bowl_p = p - float2(0.0, bowl_y_center);
    
    // 2. Noodles Layer
    float mound_aspect = max(NoodleMoundHeight, 0.01) / max(BowlWidth * 0.45, 0.01);
    float2 mp_scaled = float2(bowl_p.x, bowl_p.y / mound_aspect);
    float d_mound = length(mp_scaled) - (BowlWidth * 0.45);
    d_mound *= min(1.0, mound_aspect);
    d_mound = max(d_mound, -bowl_p.y); // Bound above rim
    
    float d_noodles_lines = ramen_sdNoodleGrid(bowl_p, NoodleCount, NoodleWaveAmp, NoodleWaveFreq, NoodleThickness);
    float d_noodles = max(d_mound, d_noodles_lines);
    
    float4 noodles_layer = ramen_render(d_noodles, NoodleColor.rgb, OutlineColor.rgb, OutlineThickness, aa);
    result = ramen_blend(noodles_layer, result);
    
    // 3. Bowl Body
    float bowl_aspect = max(BowlHeight, 0.01) / max(BowlWidth * 0.5, 0.01);
    float2 bp_scaled = float2(bowl_p.x, bowl_p.y / bowl_aspect);
    float d_bowl = length(bp_scaled) - BowlWidth * 0.5;
    d_bowl *= min(1.0, bowl_aspect);
    d_bowl = max(d_bowl, bowl_p.y); // Cut off at rim
    
    float4 bowl_layer = ramen_render(d_bowl, CeramicColor.rgb, OutlineColor.rgb, OutlineThickness, aa);
    result = ramen_blend(bowl_layer, result);
    
    // 4. Bowl Rim
    float rim_len = BowlWidth + RimFlare;
    float d_rim = ramen_sdCapsule(bowl_p, float2(-rim_len * 0.5, 0.0), float2(rim_len * 0.5, 0.0), RimThickness * 0.5);
    float4 rim_layer = ramen_render(d_rim, CeramicColor.rgb, OutlineColor.rgb, OutlineThickness, aa);
    result = ramen_blend(rim_layer, result);
    
    // 5. Meat Slice Topping
    float2 meat_p = p - MeatPos;
    float d_meat = length(meat_p) - MeatSize * 0.5;
    float d_meat_ring = abs(length(meat_p) - MeatSize * 0.25) - MeatSize * 0.05;
    float ring_alpha = 1.0 - smoothstep(-aa, aa, d_meat_ring);
    float3 meat_fill = lerp(MeatColor.rgb, MeatRingColor.rgb, ring_alpha);
    float4 meat_layer = ramen_render(d_meat, meat_fill, OutlineColor.rgb, OutlineThickness, aa);
    result = ramen_blend(meat_layer, result);
    
    // 6. Leaf Topping
    float2 leaf_p = p - LeafPos;
    float lc = cos(LeafRot), ls = sin(LeafRot);
    leaf_p = float2(lc * leaf_p.x + ls * leaf_p.y, -ls * leaf_p.x + lc * leaf_p.y);
    float leaf_D = LeafSize * 0.8;
    float leaf_R = LeafSize * 1.2;
    float d_leaf = max(length(leaf_p - float2(-leaf_D, 0.0)) - leaf_R, length(leaf_p - float2(leaf_D, 0.0)) - leaf_R);
    float4 leaf_layer = ramen_render(d_leaf, LeafColor.rgb, OutlineColor.rgb, OutlineThickness, aa);
    result = ramen_blend(leaf_layer, result);
    
    // 7. Soft Boiled Egg Topping
    float2 egg_p = p - EggPos;
    float ec = cos(EggRot), es = sin(EggRot);
    egg_p = float2(ec * egg_p.x + es * egg_p.y, -es * egg_p.x + ec * egg_p.y);
    float egg_r = EggSize * 0.5 * (1.0 - 0.2 * egg_p.y / max(EggSize, 0.01));
    float d_egg = length(egg_p) - egg_r;
    float d_yolk = length(egg_p - float2(0.0, -EggSize * 0.1)) - EggSize * 0.2;
    float yolk_alpha = 1.0 - smoothstep(-aa, aa, d_yolk);
    float3 egg_fill = lerp(EggWhiteColor.rgb, EggYolkColor.rgb, yolk_alpha);
    float4 egg_layer = ramen_render(d_egg, egg_fill, OutlineColor.rgb, OutlineThickness, aa);
    result = ramen_blend(egg_layer, result);
    
    outColor = result;
}