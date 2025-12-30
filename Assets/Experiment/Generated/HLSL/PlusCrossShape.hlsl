#ifndef PI
#define PI 3.14159265359
#endif

// Axis-aligned box SDF centered at origin with half extents b
float sdBox(float2 p, float2 b)
{
    float2 d = abs(p) - b;
    float2 dMax = max(d, 0.0);
    float outsideDist = length(dMax);
    float insideDist = min(max(d.x, d.y), 0.0);
    return outsideDist + insideDist;
}

// Union of two SDFs (keep interior of either)
float opUnion(float d1, float d2)
{
    return min(d1, d2);
}

void FunctionName_float(float2 UV, float ArmLength, float ArmThickness, float4 Color, out float4 outColor)
{
    // USER REQUEST: A plus-shaped cross made from two rectangles. The arm length and arm thickness should be adjustable. The shape should stay centered and symmetric. Single fill color.

    // PLAN:
    // 1) Center UV to [-0.5,0.5] space around (0.5,0.5).
    // 2) Build vertical arm as a box SDF using ArmThickness (width) and ArmLength (height).
    // 3) Build horizontal arm as a box SDF using ArmLength (width) and ArmThickness (height).
    // 4) Combine both with union (min) to form the plus cross.
    // 5) Apply smoothstep-based AA and output Color * mask with alpha = mask.

    // 1) Center UV
    float2 centered = UV - 0.5;

    // Ensure non-negative, reasonably clamped size values
    float lenVal = max(ArmLength, 0.0);
    float thickVal = max(ArmThickness, 0.0);

    // 2) Vertical arm SDF (height = lenVal, width = thickVal)
    float2 halfSizeVertical = 0.5 * float2(thickVal, lenVal);
    float dVertical = sdBox(centered, halfSizeVertical);

    // 3) Horizontal arm SDF (width = lenVal, height = thickVal)
    float2 halfSizeHorizontal = 0.5 * float2(lenVal, thickVal);
    float dHorizontal = sdBox(centered, halfSizeHorizontal);

    // 4) Union to form the plus-shaped cross
    float dist = opUnion(dVertical, dHorizontal);

    // 5) Anti-aliased edge and final color
    float edge = smoothstep(0.01, -0.01, dist);
    float mask = edge;
    outColor = float4(Color.rgb * mask, mask);
}
