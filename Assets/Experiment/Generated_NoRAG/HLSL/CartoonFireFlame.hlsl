// PLAN:
// 1) Remap UV to centered coordinates (p) and scale by Size.
// 2) Offset p.y to center the flame vertically based on its Height and Width.
// 3) Create central flame lobe using an exact Gothic arch + half-circle SDF.
// 4) Create two side flame lobes by mirroring X, offsetting, and scaling.
// 5) Combine lobes using smooth union for continuous, fluid cartoon curves.
// 6) Create a smaller core flame SDF for the glowing center.
// 7) Compute vertical gradient for the main flame fill.
// 8) Compute masks for fill, core, and outline with robust fwidth-based AA.
// 9) Composite the layers: base fill -> core -> outline.

#ifndef NM_OVER_HELPER
#define NM_OVER_HELPER
inline float4 nm_over(float4 src, float4 dst)
{
    float a = src.a + dst.a * (1.0 - src.a);
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-8);
    return float4(c, a);
}
#endif

#ifndef FLAME_LOBE_SDF
#define FLAME_LOBE_SDF
// Exact SDF for a flame lobe: upper part is a Gothic arch, lower part is a half-circle
inline float nm_sdFlameLobe(float2 p, float w, float h) {
    p.x = abs(p.x);
    
    // Enforce valid proportions to maintain geometry
    w = max(w, 0.001);
    h = max(h, w + 0.001); 
    
    if (p.y <= 0.0) {
        return length(p) - w;
    }
    
    // Center and radius of the arc circle connecting (w, 0) and (0, h)
    float cx = (w * w - h * h) / (2.0 * w);
    float R = (w * w + h * h) / (2.0 * w);
    
    float2 center = float2(cx, 0.0);
    float2 N = float2(-cx, h); 
    float2 V = p - center;
    
    // Cross product to check if p is outside the angular bound of the arc tip
    if (N.x * V.y - N.y * V.x > 0.0) {
        return length(p - float2(0.0, h));
    }
    
    return length(V) - R;
}

inline float nm_opSmoothUnion(float d1, float d2, float k) {
    float h = clamp(0.5 + 0.5 * (d2 - d1) / max(k, 1e-5), 0.0, 1.0);
    return lerp(d2, d1, h) - k * h * (1.0 - h);
}
#endif

void CartoonFireFlame_float(
    float2 UV,
    float Size,
    float Width,
    float Height,
    float SideRatio,
    float2 SideOffset,
    float CoreRadius,
    float4 CoreColor,
    float4 InnerColor,
    float4 OuterColor,
    float4 OutlineColor,
    float OutlineWidth,
    out float4 outColor)
{
    // 1) Remap UV
    float2 p = UV - 0.5;
    p /= max(Size, 0.001);
    
    // 2) Center the flame vertically
    // The main flame spans from y = -Width to y = Height
    // Midpoint is (Height - Width) / 2
    p.y -= (Height - Width) * 0.5;
    
    // 3) Central Flame
    float dCenter = nm_sdFlameLobe(p, Width, Height);
    
    // 4) Side Flames
    float2 sideP = p;
    sideP.x = abs(sideP.x) - SideOffset.x * Width;
    sideP.y -= SideOffset.y * Height;
    float sideW = Width * max(SideRatio, 0.0);
    float sideH = Height * max(SideRatio, 0.0);
    float dSide = nm_sdFlameLobe(sideP, sideW, sideH);
    
    // 5) Combine lobes
    float blendK = max(Width * 0.15, 0.001);
    float dFlame = nm_opSmoothUnion(dCenter, dSide, blendK);
    
    // 6) Core Flame
    float coreW = Width * max(CoreRadius, 0.0);
    float coreH = Height * max(CoreRadius, 0.0);
    float dCore = nm_sdFlameLobe(p, coreW, coreH);
    
    // 7) Gradient Fill calculation
    float t = saturate((p.y + Width) / max(Height + Width, 0.001));
    t = smoothstep(0.0, 1.0, t);
    float3 gradColor = lerp(InnerColor.rgb, OuterColor.rgb, t);
    float gradAlpha = lerp(InnerColor.a, OuterColor.a, t);
    
    // 8) Masks & Anti-Aliasing
    // Uniform AA factor based on screen-space derivatives of local coordinates
    float aa = length(float2(fwidth(p.x), fwidth(p.y))) * 0.707;
    aa = max(aa, 1e-5);
    
    float fillMask = 1.0 - smoothstep(0.0, aa, dFlame);
    float coreMask = 1.0 - smoothstep(0.0, aa, dCore);
    
    float halfOutline = 0.5 * max(OutlineWidth, 0.0);
    float outlineDist = abs(dFlame) - halfOutline;
    float outlineMask = 1.0 - smoothstep(0.0, aa, outlineDist);
    
    // 9) Compositing
    float4 baseFillOut = float4(gradColor, gradAlpha * fillMask);
    float4 coreOut = float4(CoreColor.rgb, saturate(CoreColor.a) * coreMask);
    
    // Layer core over base fill
    float4 totalFill = nm_over(coreOut, baseFillOut);
    
    // Layer outline over total fill
    float4 strokeOut = float4(OutlineColor.rgb, saturate(OutlineColor.a) * outlineMask);
    outColor = nm_over(strokeOut, totalFill);
}