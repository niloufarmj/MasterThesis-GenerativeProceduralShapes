#ifndef CARTOON_FIRE_ICON_INCLUDED
#define CARTOON_FIRE_ICON_INCLUDED

// Polynomial smooth minimum for blending flame lobes seamlessly
float smin_flame(float a, float b, float k) {
    k = max(k, 0.0001);
    float h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * 0.25;
}

// 2D Rotation function for angling the side lobes outward
float2 rotate_flame(float2 v, float a) {
    float s = sin(a);
    float c = cos(a);
    return float2(v.x * c - v.y * s, v.x * s + v.y * c);
}

// Custom SDF for a perfect flame lobe (teardrop shape)
// Features a rounded semi-circular base and a smooth concave taper to a sharp tip
float sdFlameLobe(float2 p, float radius, float height) {
    float y = max(0.0, p.y);
    float t = saturate(y / max(height, 0.0001));
    
    // Exponent of 1.5 creates a beautiful natural flame curvature
    float currentRadius = radius * (1.0 - pow(t, 1.5));
    
    float2 closest = float2(0.0, clamp(p.y, 0.0, height));
    return length(p - closest) - currentRadius;
}

void CartoonFireIcon_float(
    float2 UV,
    float FlameWidth,
    float FlameHeight,
    float SideLobeRatio,
    float SideOffsetX,
    float SideOffsetY,
    float SideRotation,
    float BlendSoftness,
    float CoreRadius,
    float CoreOffsetY,
    float OutlineWidth,
    float4 ColorCore,
    float4 ColorFlameBottom,
    float4 ColorFlameTop,
    float4 ColorOutline,
    out float4 outColor
) {
    // Center UV coordinates at origin
    float2 p = UV - float2(0.5, 0.5);
    
    // Shift coordinate system slightly up so the whole flame sits centered in the icon bounds
    p.y += 0.15;

    // 1. Central Flame Lobe
    float dCenter = sdFlameLobe(p, FlameWidth, FlameHeight);

    // 2. Left Flame Lobe
    // Offset origin to the side lobe's base, then rotate outward, then calculate SDF
    float2 pLeft = p - float2(-SideOffsetX, SideOffsetY);
    pLeft = rotate_flame(pLeft, -SideRotation);
    float dLeft = sdFlameLobe(pLeft, FlameWidth * SideLobeRatio, FlameHeight * SideLobeRatio);

    // 3. Right Flame Lobe
    float2 pRight = p - float2(SideOffsetX, SideOffsetY);
    pRight = rotate_flame(pRight, SideRotation);
    float dRight = sdFlameLobe(pRight, FlameWidth * SideLobeRatio, FlameHeight * SideLobeRatio);

    // Combine all three lobes using smooth union for a fluid, molten look
    float dSides = smin_flame(dLeft, dRight, BlendSoftness);
    float dOuter = smin_flame(dCenter, dSides, BlendSoftness);

    // 4. Inner Bright Core (Circular)
    float2 pCore = p - float2(0.0, CoreOffsetY);
    float dCore = length(pCore) - CoreRadius;

    // Calculate vertical gradient dynamically mapping to the total combined flame height bounds
    // Base of the central flame is exactly at p.y = -FlameWidth, Tip is at p.y = FlameHeight
    float gradientT = saturate((p.y + FlameWidth) / max(FlameHeight + FlameWidth, 0.0001));
    gradientT = pow(gradientT, 1.2); // Slight curve to push deeper colors upward
    float4 flameBaseColor = lerp(ColorFlameBottom, ColorFlameTop, gradientT);

    // Anti-aliasing derivatives based on screen-space distance field changes
    float aaOuter = max(fwidth(dOuter) * 0.5, 0.001);
    float aaCore  = max(fwidth(dCore) * 0.5, 0.001);

    // Mask Generation (1.0 = Inside, 0.0 = Outside)
    float maskOutline = 1.0 - smoothstep(OutlineWidth - aaOuter, OutlineWidth + aaOuter, dOuter);
    float maskOuter   = 1.0 - smoothstep(-aaOuter, aaOuter, dOuter);
    float maskCore    = 1.0 - smoothstep(-aaCore, aaCore, dCore);

    // Layer Compositing (Painter's Algorithm)
    float4 finalColor = float4(0.0, 0.0, 0.0, 0.0);
    
    // Add Background Outline Silhouette
    finalColor = lerp(finalColor, ColorOutline, maskOutline * ColorOutline.a);
    
    // Overlay Main Gradient Flame
    finalColor = lerp(finalColor, flameBaseColor, maskOuter * flameBaseColor.a);
    
    // Overlay Glowing Core Highlight
    finalColor = lerp(finalColor, ColorCore, maskCore * ColorCore.a);

    outColor = finalColor;
}

#endif // CARTOON_FIRE_ICON_INCLUDED
