#ifndef PI
#define PI 3.14159265359
#endif

// Helper: Signed Distance to a Line Segment
float sdSegment_Share(float2 p, float2 a, float2 b) {
    float2 pa = p - a;
    float2 ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}

void ShareIconShape_float(float2 UV, float Size, float Spacing, float DotRadius, float LineThickness, float Rotation, float2 Center, float4 Color, out float4 outColor) {
    // PLAN:
    // 1) Center UVs and apply rotation around the pivot.
    // 2) Scale coordinates by Size to normalize the drawing space.
    // 3) Define the three key points of a share icon (Root, TopLeft, BotLeft).
    // 4) Compute SDFs for the three circles (dots).
    // 5) Compute SDFs for the two connecting lines.
    // 6) Combine all shapes using union (min).
    // 7) Apply smoothstep for clean anti-aliasing.

    // 1: Center and Rotate
    float2 p = UV - Center;
    float c = cos(Rotation);
    float s = sin(Rotation);
    p = float2(p.x * c - p.y * s, p.x * s + p.y * c);

    // 2: Scale
    // Guard against division by zero
    float scale = max(Size, 0.0001);
    p /= scale;

    // 3: Define Points
    // A share icon typically has one node on the right connected to two on the left
    float spread = max(Spacing, 0.0);
    float2 root = float2(spread, 0.0);
    float2 topLeft = float2(-spread, spread);
    float2 botLeft = float2(-spread, -spread);

    // 4: Dots SDF
    float r = max(DotRadius, 0.0);
    float dDots = length(p - root) - r;
    dDots = min(dDots, length(p - topLeft) - r);
    dDots = min(dDots, length(p - botLeft) - r);

    // 5: Lines SDF
    // Calculate distance to segments and subtract half-thickness
    float halfThick = max(LineThickness, 0.0) * 0.5;
    float dLines = sdSegment_Share(p, root, topLeft) - halfThick;
    dLines = min(dLines, sdSegment_Share(p, root, botLeft) - halfThick);

    // 6: Combine (Union of dots and lines)
    float d = min(dDots, dLines);

    // 7: Output with Anti-Aliasing
    // fwidth ensures consistent edge softness regardless of scale
    float aa = fwidth(d);
    float mask = 1.0 - smoothstep(-aa, aa, d);

    outColor = float4(Color.rgb * mask, Color.a * mask);
}