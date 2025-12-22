#ifndef PI
#define PI 3.14159265359
#endif

// Rotates a point around the origin (0,0)
// angle is in radians. Positive angle = Counter-Clockwise in standard math,
// but we will negate it in main to make positive = Clockwise (Visual Clock).
float2 RotateUV(float2 p, float angle) {
    float c = cos(angle);
    float s = sin(angle);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

// Signed distance to a line segment from point A to B
float sdSegment(float2 p, float2 a, float2 b) {
    float2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}

// Simple blending helper (Source Over Destination)
float4 BlendLayers(float4 fg, float4 bg) {
    float outA = fg.a + bg.a * (1.0 - fg.a);
    float3 outRGB = (fg.rgb * fg.a + bg.rgb * bg.a * (1.0 - fg.a)) / max(outA, 1e-6);
    return float4(outRGB, outA);
}

void ClockIcon_float(float2 UV, float Size, float HourAngle, float MinuteAngle, float4 FaceColor, float4 HandColor, out float4 outColor) {
    // Description: A simple clock icon with adjustable hands and colors.
    
    // 1. Center coordinates. Map [0,1] to [-1,1] space relative to Size.
    float2 p = UV - 0.5;
    
    // 2. Anti-aliasing factor based on screen-space derivatives
    float aa = length(fwidth(p));
    aa = max(aa, 0.001); // Safety for previews

    // --- Clock Face (Background) ---
    // Circle centered at 0 with radius = Size
    float dFace = length(p) - Size;
    float faceMask = 1.0 - smoothstep(-aa, aa, dFace);
    float4 faceLayer = float4(FaceColor.rgb, FaceColor.a * faceMask);

    // --- Details (Border + Hands) ---
    
    // 1. Border (Ring)
    // A ring inside the outer edge. Thickness relative to size.
    float borderThick = Size * 0.1;
    float borderRadius = Size - borderThick * 0.5;
    float dBorder = abs(length(p) - borderRadius) - borderThick * 0.5;

    // 2. Hour Hand
    // Rotate p by negative angle so positive input = clockwise rotation
    float2 pHour = RotateUV(p, -HourAngle);
    // Segment from center (0,0) to (0, length)
    float hLen = Size * 0.5;
    float hWidth = Size * 0.06;
    float dHour = sdSegment(pHour, float2(0,0), float2(0, hLen)) - hWidth;

    // 3. Minute Hand
    float2 pMin = RotateUV(p, -MinuteAngle);
    float mLen = Size * 0.8;
    float mWidth = Size * 0.04;
    float dMin = sdSegment(pMin, float2(0,0), float2(0, mLen)) - mWidth;

    // 4. Center Dot
    float dotRadius = Size * 0.1;
    float dDot = length(p) - dotRadius;

    // Combine all Detail SDFs (Union = min)
    float dDetails = min(dBorder, min(dHour, min(dMin, dDot)));
    
    // Detail Mask
    float detailMask = 1.0 - smoothstep(-aa, aa, dDetails);
    float4 detailLayer = float4(HandColor.rgb, HandColor.a * detailMask);

    // --- Composite ---
    // Draw Details OVER Face
    outColor = BlendLayers(detailLayer, faceLayer);
}