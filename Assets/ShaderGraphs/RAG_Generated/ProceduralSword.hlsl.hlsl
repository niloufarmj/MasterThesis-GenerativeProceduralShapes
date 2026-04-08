#ifndef PI
#define PI 3.14159265359
#endif

// --- Helpers ---

inline float4 over_Sword(float4 top, float4 bottom) {
    float a = top.a + bottom.a * (1.0 - top.a);
    float3 c = (top.rgb * top.a + bottom.rgb * bottom.a * (1.0 - top.a)) / max(a, 1e-6);
    return float4(c, a);
}

inline float4 getSplitColor_Sword(float x, float aa, float4 left, float4 right) {
    // smoothstep creates a perfectly anti-aliased vertical split at x=0
    float mask = smoothstep(-aa, aa, x);
    return lerp(left, right, mask);
}

inline float sdBladeExact_Sword(float2 p, float halfW, float len, float tipHeight) {
    float tipBaseY = len - tipHeight;
    // Calculate circle radius for the gothic arch tip (ensures G1 continuity)
    float R = (halfW * halfW + tipHeight * tipHeight) / max(2.0 * halfW, 0.001);
    float2 q = float2(abs(p.x), p.y);
    
    float2 center = float2(halfW - R, tipBaseY);
    float d_arch = length(q - center) - R;
    float d_shaft = max(q.x - halfW, -q.y);
    
    // Branchless selection: use arch above tipBaseY, shaft below
    return lerp(d_shaft, d_arch, step(tipBaseY, q.y));
}

inline float sdBox_Sword(float2 p, float2 b) {
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

inline float sdRoundBox_Sword(float2 p, float2 b, float r) {
    float2 q = abs(p) - b + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

inline float sdCircle_Sword(float2 p, float r) {
    return length(p) - r;
}

// --- Main Function ---

void ProceduralSword_float(
    float2 UV,
    float2 Center,
    float BladeLength,
    float BladeWidth,
    float BladeTipHeight,
    float BladeInset,
    float4 BladeOuterColorLeft,
    float4 BladeOuterColorRight,
    float4 BladeInnerColorLeft,
    float4 BladeInnerColorRight,
    float GuardWidth,
    float GuardHeight,
    float4 GuardColorLeft,
    float4 GuardColorRight,
    float GripLength,
    float GripWidth,
    float4 GripColorLeft,
    float4 GripColorRight,
    float PommelOuterRadius,
    float PommelInnerRadius,
    float4 PommelOuterColorLeft,
    float4 PommelOuterColorRight,
    float4 PommelInnerColorLeft,
    float4 PommelInnerColorRight,
    out float4 outColor
) {
    // 1. Setup global coordinates and anti-aliasing
    float2 p = UV - Center;
    float aa = fwidth(length(p));
    if (aa == 0.0) aa = 0.001;
    
    // 2. BLADE (Back layer)
    // Push blade down slightly so the bottom is cleanly hidden behind the guard
    float2 p_blade = p - float2(0.0, -0.05);
    float d_bladeOuter = sdBladeExact_Sword(p_blade, BladeWidth * 0.5, BladeLength, BladeTipHeight);
    float d_bladeInner = d_bladeOuter + BladeInset; // Instant exact inset!
    
    float m_bladeOuter = 1.0 - smoothstep(-aa, aa, d_bladeOuter);
    float m_bladeInner = 1.0 - smoothstep(-aa, aa, d_bladeInner);
    
    float4 c_bladeOuter = getSplitColor_Sword(p.x, aa, BladeOuterColorLeft, BladeOuterColorRight);
    float4 c_bladeInner = getSplitColor_Sword(p.x, aa, BladeInnerColorLeft, BladeInnerColorRight);
    
    // Subtle vertical gradient to match image lighting
    float bladeGrad = saturate(p_blade.y / max(BladeLength, 0.001));
    c_bladeOuter.rgb *= lerp(0.85, 1.0, bladeGrad);
    c_bladeInner.rgb *= lerp(0.85, 1.0, bladeGrad);
    
    float4 colOuter = float4(c_bladeOuter.rgb, c_bladeOuter.a * m_bladeOuter);
    float4 colInner = float4(c_bladeInner.rgb, c_bladeInner.a * m_bladeInner);
    float4 finalBlade = over_Sword(colInner, colOuter);
    
    // 3. GRIP (Middle layer, extends downwards)
    float2 p_grip = p - float2(0.0, -GripLength * 0.5);
    float d_grip = sdBox_Sword(p_grip, float2(GripWidth * 0.5, GripLength * 0.5));
    float m_grip = 1.0 - smoothstep(-aa, aa, d_grip);
    float4 c_grip = getSplitColor_Sword(p.x, aa, GripColorLeft, GripColorRight);
    c_grip = float4(c_grip.rgb, c_grip.a * m_grip);
    
    // 4. POMMEL (Middle-front layer, centered at bottom of grip)
    float2 p_pommel = p - float2(0.0, -GripLength);
    float d_pommelOuter = sdCircle_Sword(p_pommel, PommelOuterRadius);
    float d_pommelInner = sdCircle_Sword(p_pommel, PommelInnerRadius);
    
    float m_pommelOuter = 1.0 - smoothstep(-aa, aa, d_pommelOuter);
    float m_pommelInner = 1.0 - smoothstep(-aa, aa, d_pommelInner);
    
    float4 c_pommelOuter = getSplitColor_Sword(p.x, aa, PommelOuterColorLeft, PommelOuterColorRight);
    float4 c_pommelInner = getSplitColor_Sword(p.x, aa, PommelInnerColorLeft, PommelInnerColorRight);
    
    // Subtle vertical gradient on pommel
    float pommelGrad = saturate((p_pommel.y + PommelOuterRadius) / max(2.0 * PommelOuterRadius, 0.001));
    c_pommelOuter.rgb *= lerp(0.85, 1.0, pommelGrad);
    c_pommelInner.rgb *= lerp(0.85, 1.0, pommelGrad);
    
    float4 colPomOuter = float4(c_pommelOuter.rgb, c_pommelOuter.a * m_pommelOuter);
    float4 colPomInner = float4(c_pommelInner.rgb, c_pommelInner.a * m_pommelInner);
    float4 finalPommel = over_Sword(colPomInner, colPomOuter);
    
    // 5. CROSS-GUARD (Front layer, covers all joints at y=0)
    float guardRadius = GuardHeight * 0.15;
    float d_guard = sdRoundBox_Sword(p, float2(GuardWidth * 0.5, GuardHeight * 0.5), guardRadius);
    float m_guard = 1.0 - smoothstep(-aa, aa, d_guard);
    float4 c_guard = getSplitColor_Sword(p.x, aa, GuardColorLeft, GuardColorRight);
    c_guard = float4(c_guard.rgb, c_guard.a * m_guard);
    
    // 6. COMPOSITION (Back to Front)
    float4 result = float4(0, 0, 0, 0);
    result = over_Sword(finalBlade, result);
    result = over_Sword(c_grip, result);
    result = over_Sword(finalPommel, result);
    result = over_Sword(c_guard, result);
    
    outColor = result;
}
