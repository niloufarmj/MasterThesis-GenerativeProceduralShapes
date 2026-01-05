#ifndef PI
#define PI 3.14159265359
#endif

// Helper: Signed Distance to a Quadratic Bezier Curve
// P0: Start, P1: Control, P2: End
float sdBezier(float2 pos, float2 P0, float2 P1, float2 P2)
{
    float2 a = P1 - P0;
    float2 b = P0 - 2.0 * P1 + P2;
    float2 c = a * 2.0;
    float2 d = P0 - pos;

    float kk = 1.0 / dot(b, b);
    float kx = kk * dot(a, b);
    float ky = kk * (2.0 * dot(a, a) + dot(d, b)) / 3.0;
    float kz = kk * dot(d, a);

    float res = 0.0;

    float p = ky - kx * kx;
    float p3 = p * p * p;
    float q = kx * (2.0 * kx * kx - 3.0 * ky) + kz;
    float h = q * q + 4.0 * p3;

    if (h >= 0.0)
    {
        h = sqrt(h);
        float2 x = (float2(h, -h) - q) / 2.0;
        float2 uv = sign(x) * pow(abs(x), 1.0 / 3.0);
        float t = clamp(uv.x + uv.y - kx, 0.0, 1.0);
        float2 qVec = d + (c + b * t) * t;
        res = dot(qVec, qVec);
    }
    else
    {
        float z = sqrt(-p);
        float v = acos(clamp(q / (p * z * 2.0), -1.0, 1.0)) / 3.0;
        float m = cos(v);
        float n = sin(v) * 1.732050808;
        float3 t = clamp(float3(m + m, -n - m, n - m) * z - kx, 0.0, 1.0);
        float2 qx = d + (c + b * t.x) * t.x;
        float dx = dot(qx, qx);
        float2 qy = d + (c + b * t.y) * t.y;
        float dy = dot(qy, qy);
        res = min(dx, dy);
    }
    return sqrt(res);
}

// Helper: Simple Circle SDF
float sdCircle(float2 p, float r)
{
    return length(p) - r;
}

// Main Function: Share Icon made of 3 dots and 2 curved lines
void ShareIconCurved_float(float2 UV, float Size, float Spacing, float DotRadius, float LineWidth, float CurveAmount, float2 Center, float4 Color, out float4 outColor)
{
    // PLAN:
    // 1) Center and normalize UV coordinates based on Size.
    // 2) Define positions for Left, TopRight, and BottomRight dots based on Spacing.
    // 3) Calculate control points for the Bezier curves to add curvature.
    // 4) Compute SDF for the 3 dots (Union).
    // 5) Compute SDF for the 2 connecting lines (Union).
    // 6) Combine all shapes and apply anti-aliasing.

    // 1) Transform UVs
    float2 p = UV - Center;
    float s = max(Size, 0.0001); // Prevent division by zero
    p /= s;

    // 2) Define Point Locations
    // Spacing controls the spread relative to the center
    float sp = max(Spacing, 0.001);
    
    // Left dot (Source)
    float2 pLeft = float2(-sp * 0.75, 0.0);
    // Right Top dot (Destination 1)
    float2 pRightTop = float2(sp * 0.75, sp * 0.6);
    // Right Bottom dot (Destination 2)
    float2 pRightBot = float2(sp * 0.75, -sp * 0.6);

    // 3) Calculate Curves Control Points
    // We create a control point offset perpendicular to the line connecting the dots
    // Top Line Curve
    float2 dirTop = normalize(pRightTop - pLeft);
    float2 perpTop = float2(-dirTop.y, dirTop.x); // Perpendicular vector (Up/Left)
    float2 midTop = (pLeft + pRightTop) * 0.5;
    float2 cTop = midTop + perpTop * CurveAmount;

    // Bottom Line Curve (Symmetric)
    float2 cBot = float2(cTop.x, -cTop.y);

    // 4) Dots SDF
    float dDots = sdCircle(p - pLeft, DotRadius);
    dDots = min(dDots, sdCircle(p - pRightTop, DotRadius));
    dDots = min(dDots, sdCircle(p - pRightBot, DotRadius));

    // 5) Lines SDF
    // Subtract LineWidth from the bezier distance to create a stroke
    float dLineTop = sdBezier(p, pLeft, cTop, pRightTop) - LineWidth;
    float dLineBot = sdBezier(p, pLeft, cBot, pRightBot) - LineWidth;
    float dLines = min(dLineTop, dLineBot);

    // Combine dots and lines
    float d = min(dDots, dLines);

    // 6) Anti-aliasing and Color Output
    float aa = fwidth(d);
    // If fwidth is too small (e.g. constant UV), fallback to constant
    aa = max(aa, 0.001);
    
    float alpha = smoothstep(aa, -aa, d);
    
    outColor = float4(Color.rgb * alpha, Color.a * alpha);
}

// ------------------------------------------------------------------------
//  Visual Result (High-level, parameter-invariant description)
// ------------------------------------------------------------------------
//  This function generates a **stylized curved share icon** using
//  Signed Distance Functions (SDFs).
//
//  The visual result is composed of:
//  - Three **circular nodes** arranged in a branching formation (one source on the left,
//    two destinations on the right).
//  - Two **curved connecting lines** (Bezier strokes) linking the source node
//    to the destination nodes.
//
//  The geometry features adjustable **node spacing**, **curvature**, and 
//  **line thickness**, allowing the shape to range from rigid mechanical 
//  linkages to organic, flowy network graphs.
//
//  The output is an anti-aliased RGBA color suitable for social media buttons,
//  UI sharing actions, and network node visualizations.
// ------------------------------------------------------------------------