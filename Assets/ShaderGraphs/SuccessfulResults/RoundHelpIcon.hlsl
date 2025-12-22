#ifndef PI
#define PI 3.14159265359
#endif

// Distance to a line segment
float sdSegment(float2 p, float2 a, float2 b) {
    float2 pa = p - a;
    float2 ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}

// Smooth minimum for blending shapes
float opSmoothUnion(float d1, float d2, float k) {
    float h = clamp(0.5 + 0.5 * (d2 - d1) / k, 0.0, 1.0);
    return lerp(d2, d1, h) - k * h * (1.0 - h);
}

void RoundHelpIcon_float(float2 UV, float Size, float Thickness, float4 Color, out float4 outColor) {
    // PLAN:
    // 1. Center UVs to [-0.5, 0.5] and scale p to correct space.
    // 2. Define the Outer Ring SDF (circle outline).
    // 3. Define the Question Mark SDF using connected segments (Hook) and a Circle (Dot).
    // 4. Combine Ring and Question Mark using union.
    // 5. Apply thickness to strokes.
    // 6. Anti-alias and output color.
    
    // 1. Center coordinates
    float2 p = UV - 0.5;
    
    // Ensure safe values
    float sz = max(Size, 0.01);       // Radius of the icon
    float th = max(Thickness, 0.001); // Stroke width
    
    // 2. Outer Ring SDF
    // Distance to circle edge
    float dRing = abs(length(p) - sz) - th;
    
    // 3. Question Mark SDF
    // We construct the hook from 3 segments smoothly blended
    // Coordinates are relative to Size to scale with the icon
    float s = sz; 
    
    // Key points for the '?' shape
    float2 pStart = float2(-0.25 * s, 0.15 * s); // Left start of hook
    float2 pTop   = float2(0.0, 0.45 * s);       // Top peak
    float2 pRight = float2(0.25 * s, 0.20 * s);  // Right bulge
    float2 pBot   = float2(0.0, -0.15 * s);      // Bottom of the stem
    
    // Calculate distance to segments
    float dSeg1 = sdSegment(p, pStart, pTop);
    float dSeg2 = sdSegment(p, pTop, pRight);
    float dSeg3 = sdSegment(p, pRight, pBot);
    
    // Smoothly blend the segments to create a curvy hook
    float k = 0.15 * s; // Smoothing factor relative to size
    float dHook = opSmoothUnion(dSeg1, dSeg2, k);
    dHook = opSmoothUnion(dHook, dSeg3, k);
    
    // The Dot
    float2 dotPos = float2(0.0, -0.45 * s);
    float dDot = length(p - dotPos);
    
    // Combine Hook and Dot (Question Mark shape)
    // Note: We subtract thickness later for the hook, but the dot is usually solid or same thickness
    // Let's treat the QM as a skeleton line first
    float dQM_Skeleton = min(dHook, dDot);
    float dQuestionMark = dQM_Skeleton - th;
    
    // 4. Combine Ring and Question Mark
    float dTotal = min(dRing, dQuestionMark);
    
    // 5. Anti-aliasing
    // fwidth provides a screen-space derivative for sharp resolution-independent AA
    float aa = fwidth(dTotal);
    float mask = 1.0 - smoothstep(-aa, aa, dTotal);
    
    // 6. Output
    outColor = float4(Color.rgb * mask, mask);
}