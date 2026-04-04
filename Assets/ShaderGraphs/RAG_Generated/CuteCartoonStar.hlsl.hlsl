#ifndef PI
#define PI 3.14159265359
#endif

#ifndef NM_OVER_HELPER
#define NM_OVER_HELPER
inline float4 nm_over(float4 src, float4 dst)
{
    float a = src.a + dst.a * (1.0 - src.a);
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-8);
    return float4(c, a);
}
#endif

#ifndef SD_STAR5_HELPER
#define SD_STAR5_HELPER
inline float sdStar5(float2 p, float r, float rf)
{
    const float2 k1 = float2(0.809016994375, -0.587785252292);
    const float2 k2 = float2(-k1.x, k1.y);
    p.x = abs(p.x);
    p -= 2.0 * max(dot(k1, p), 0.0) * k1;
    p -= 2.0 * max(dot(k2, p), 0.0) * k2;
    p.x = abs(p.x);
    p.y -= r;
    float2 ba = rf * float2(-k1.y, k1.x) - float2(0, 1);
    float h = clamp( dot(p,ba)/dot(ba,ba), 0.0, r );
    return length(p-ba*h) * sign(p.y*ba.x-p.x*ba.y);
}
#endif

#ifndef SD_CAPSULE_HELPER
#define SD_CAPSULE_HELPER
inline float sdCapsule(float2 p, float2 a, float2 b, float r) {
    float2 pa = p - a, ba = b - a;
    float h = clamp( dot(pa,ba)/dot(ba,ba), 0.0, 1.0 );
    return length( pa - ba*h ) - r;
}
#endif

#ifndef SD_MOUTH_HELPER
#define SD_MOUTH_HELPER
inline float sdMouth(float2 p, float radius, float thickness) {
    // Creates a U-shape smile
    if (p.y > 0.0) {
        return length(float2(abs(p.x) - radius, p.y)) - thickness;
    } else {
        return abs(length(p) - radius) - thickness;
    }
}
#endif

void CuteCartoonStar_float(
    float2 UV,
    float2 Center,
    float StarSize,
    float4 StarColor,
    float Curvature,
    float LegLength,
    float4 OutlineColor,
    float OutlineWidth,
    float4 FaceColor,
    float EyesSize,
    float EyesDistance,
    float MouthCurve,
    out float4 outColor
) {
    // Center UV coordinates
    float2 p = UV - Center;
    
    // Normalize scale relative to a base size to keep features proportionate
    float scale = max(StarSize / 0.4, 0.001);
    
    // Compute star structure parameters
    // Subtracting Curvature from base radius to allow inflation for rounded corners
    float r = max(0.01, StarSize - Curvature);
    float rf = r * (1.0 - clamp(LegLength, 0.0, 0.9));
    
    // Base Shape SDF (Inflation rounds outer tips)
    float d_star = sdStar5(p, r, rf) - Curvature;
    
    // Anti-aliasing width based on local gradient
    float aa = fwidth(d_star);
    aa = max(aa, 0.001);
    
    // Generate main fill mask
    float fillAlpha = smoothstep(aa, -aa, d_star);
    
    // --- 2D Lighting Effects (Inner Rims) ---
    // Inner bottom-right shadow
    float d_shadow = sdStar5(p - float2(-0.02, 0.02) * scale, r, rf) - Curvature;
    float shadowMask = smoothstep(aa, -aa, d_star) * smoothstep(-aa, aa, d_shadow);
    
    // Inner top-left highlight rim
    float d_light = sdStar5(p - float2(0.015, -0.015) * scale, r, rf) - Curvature;
    float lightMask = smoothstep(aa, -aa, d_star) * smoothstep(-aa, aa, d_light);
    
    // Composite Base Color with lighting rims
    float3 base_rgb = StarColor.rgb;
    base_rgb = lerp(base_rgb, base_rgb * 0.85, shadowMask * 0.8); // Darken for shadow
    base_rgb = lerp(base_rgb, lerp(base_rgb, float3(1.0, 1.0, 1.0), 0.5), lightMask * 0.7); // Brighten for rim
    
    // --- Facial Features ---
    float2 faceCenter = float2(0.0, 0.02) * scale;
    
    // Eyes (Slightly tall ovals, mirrored)
    float2 p_eyes = p - faceCenter;
    p_eyes.x = abs(p_eyes.x);
    float d_eyes = length(float2(p_eyes.x - EyesDistance * 0.5 * scale, p_eyes.y * 0.8)) - EyesSize * scale;
    
    // Mouth (Small U-curve centered below eyes)
    float2 p_mouth = p - faceCenter - float2(0.0, -0.06) * scale;
    float d_mouth = sdMouth(p_mouth, MouthCurve * scale, EyesSize * 0.4 * scale);
    
    // Combine face
    float d_face = min(d_eyes, d_mouth);
    float faceAlpha = smoothstep(aa, -aa, d_face);
    
    // --- Specular Highlight ---
    // Top-left angled capsule conforming to the star edge
    float2 hl_a = float2(-0.12, 0.30) * scale;
    float2 hl_b = float2(-0.22, 0.18) * scale;
    float d_hl = sdCapsule(p, hl_a, hl_b, 0.02 * scale);
    float hlAlpha = smoothstep(aa, -aa, d_hl);
    
    // --- Outline ---
    // Outline straddles the edge of the star
    float d_outline = abs(d_star) - OutlineWidth * 0.5;
    float outlineAlpha = smoothstep(aa, -aa, d_outline);
    
    // --- Final Composition ---
    // 1. Solid Star Body
    float4 finalColor = float4(base_rgb, fillAlpha);
    
    // 2. Blend Face Details (Ensuring they stay inside the star mask)
    finalColor.rgb = lerp(finalColor.rgb, FaceColor.rgb, faceAlpha * fillAlpha);
    
    // 3. Blend White Highlight Capsule
    finalColor.rgb = lerp(finalColor.rgb, float3(1.0, 1.0, 1.0), hlAlpha * fillAlpha);
    
    // 4. Stroke / Outline drawn ON TOP of the entire composite
    float4 strokeColor = float4(OutlineColor.rgb, OutlineColor.a * outlineAlpha);
    outColor = nm_over(strokeColor, finalColor);
}
