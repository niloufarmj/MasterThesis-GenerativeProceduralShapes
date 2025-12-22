#ifndef PI
#define PI 3.14159265359
#endif

// SDF for a box centered at origin with half-extents b
float sdBox(float2 p, float2 b) {
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// Helper to rotate a 2D vector by an angle (radians)
float2 rotate(float2 p, float angle) {
    float c = cos(angle);
    float s = sin(angle);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

// Main Function: Round Close Icon with X
// User Request: A round close icon with an X in the center that I can adjust in size and thickness
void RoundCloseIcon_float(float2 UV, float Size, float Thickness, float XScale, float4 BackgroundColor, float4 XColor, out float4 outColor) {
    // PLAN:
    // 1) Center UVs to (0,0).
    // 2) Compute Circle SDF for the background.
    // 3) Compute X SDF (Union of two rotated boxes) for the foreground.
    // 4) Compute Anti-aliased masks for both shapes.
    // 5) Composite Foreground (X) over Background (Circle) using premultiplied alpha blending.

    // 1. Center UV coordinates (0.5, 0.5 becomes 0,0)
    float2 p = UV - 0.5;

    // 2. Circle SDF (Background)
    // Distance from center minus radius (Size)
    float dCircle = length(p) - Size;
    float circleAA = fwidth(dCircle);
    // Soft mask for circle (1.0 inside, 0.0 outside)
    float alphaCircle = 1.0 - smoothstep(-circleAA, circleAA, dCircle);

    // 3. X Shape SDF (Foreground)
    // Rotate point by 45 degrees to turn a + into an X
    float2 pRot = rotate(p, radians(45.0));
    
    // Dimensions for the X arms
    // xHalfLen is the distance from center to tip of the X arm
    float xHalfLen = Size * XScale;
    // xHalfThick is half the width of the stroke
    float xHalfThick = Thickness * 0.5;
    
    // Calculate SDFs for two crossing boxes
    float dBox1 = sdBox(pRot, float2(xHalfLen, xHalfThick)); // Arm 1
    float dBox2 = sdBox(pRot, float2(xHalfThick, xHalfLen)); // Arm 2
    
    // Union of the two boxes (min distance)
    float dX = min(dBox1, dBox2);
    
    float xAA = fwidth(dX);
    // Soft mask for X (1.0 inside, 0.0 outside)
    float alphaX = 1.0 - smoothstep(-xAA, xAA, dX);

    // 4. Composite Colors (Premultiplied Alpha)
    // Prepare Background Color (Circle)
    float4 bg = float4(BackgroundColor.rgb * BackgroundColor.a * alphaCircle, BackgroundColor.a * alphaCircle);
    
    // Prepare Foreground Color (X)
    float4 fg = float4(XColor.rgb * XColor.a * alphaX, XColor.a * alphaX);
    
    // Blend X over Circle using standard "Source Over" blending:
    // Result = Foreground + Background * (1 - ForegroundAlpha)
    outColor = fg + bg * (1.0 - fg.a);
}