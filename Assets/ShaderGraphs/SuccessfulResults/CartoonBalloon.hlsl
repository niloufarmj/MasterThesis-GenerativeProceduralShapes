#ifndef PI
#define PI 3.14159265359
#endif

// --- Helpers ---

// Signed pseudo-distance to an axis-aligned ellipse
// Adapted from reference EllipseColorOutlineCenteredRotated.hlsl
float sdEllipseApprox(float2 p, float2 halfAxes)
{
    float a = max(halfAxes.x, 1e-8);
    float b = max(halfAxes.y, 1e-8);
    float aa = a * a;
    float bb = b * b;
    float x = p.x, y = p.y;
    float F = (x * x) / aa + (y * y) / bb - 1.0;
    float gradLen = 2.0 * sqrt((x * x) / (aa * aa) + (y * y) / (bb * bb));
    return (gradLen > 1e-8) ? (F / gradLen) : -min(a, b);
}

// Distance to a line segment
float sdSegment(float2 p, float2 a, float2 b)
{
    float2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}

// Distance to a trapezoid (used for the knot)
// p: relative to top center. w1: top half-width, w2: bottom half-width, h: height
float sdTrapezoid(float2 p, float w1, float w2, float h)
{
    // Symmetry
    p.x = abs(p.x);
    
    // Vertices of the right edge
    float2 a = float2(w1, 0.0);
    float2 b = float2(w2, -h);
    
    // Distance to the slanted edge
    float dEdge = sdSegment(p, a, b);
    
    // Cap top and bottom (approximate intersection for simple shape)
    // If above top, dist is vertical to top. If below bottom, dist is vertical to bottom.
    if (p.y > 0.0) return length(max(p - float2(w1, 0.0), 0.0)) + (p.y);
    if (p.y < -h) return length(max(p - float2(w2, -h), 0.0)) + (-p.y - h);
    
    // Inside vertical bounds, just use edge distance with sign logic
    // Simple signed logic: cross product to determine side
    float2 edge = b - a;
    float2 pt = p - a;
    float crossZ = edge.x * pt.y - edge.y * pt.x;
    // If crossZ > 0 (to the right of edge), positive. Else negative (inside).
    // This assumes w1, w2 > 0 and h > 0
    return (crossZ > 0.0) ? dEdge : -dEdge;
}

// Smooth union for organic blending
float opSmoothUnion(float d1, float d2, float k)
{
    float h = clamp(0.5 + 0.5 * (d2 - d1) / k, 0.0, 1.0);
    return lerp(d2, d1, h) - k * h * (1.0 - h);
}

// --- Main Function ---
// User Request: A cartoon balloon with adjustable oval/round shape, knot, and wavy string.
void CartoonBalloon_float(
    float2 UV,
    float2 Center,
    float2 BalloonSize,     // (Width, Height)
    float4 BalloonColor,
    float2 KnotSize,        // (Width, Height)
    float StringLength,
    float StringThickness,
    float4 StringColor,
    float2 StringWave,      // (Amplitude, Frequency)
    out float4 outColor)
{
    // 1) Center UVs
    float2 p = UV - Center;

    // 2) Balloon Body SDF (Ellipse)
    // BalloonSize represents full width/height, so halfAxes = Size * 0.5
    float2 halfAxes = max(BalloonSize * 0.5, 0.001);
    float dBody = sdEllipseApprox(p, halfAxes);

    // 3) Knot SDF (Trapezoid)
    // Positioned at the bottom of the balloon (y = -halfAxes.y)
    float2 pKnot = p - float2(0.0, -halfAxes.y + 0.01); // slight overlap upwards
    // Knot width tapers: Top is narrow (tied), Bottom is wider (flared)
    float knotTopW = KnotSize.x * 0.5 * 0.6;
    float knotBotW = KnotSize.x * 0.5;
    float dKnot = sdTrapezoid(pKnot, knotTopW, knotBotW, KnotSize.y);

    // 4) Union Balloon Body and Knot
    // Use smooth union to make it look like a single rubber object
    float dBalloon = opSmoothUnion(dBody, dKnot, 0.01);

    // 5) String SDF
    // Starts from bottom of knot
    float2 pString = pKnot - float2(0.0, -KnotSize.y);
    // Add waviness to X based on Y distance
    // We only distort X for the distance calculation to simulate a curve
    float wave = sin(pString.y * StringWave.y) * StringWave.x * smoothstep(0.0, -0.1, pString.y);
    float2 pStringWavy = float2(pString.x - wave, pString.y);
    
    // String is a vertical segment from (0,0) to (0, -len) in distorted space
    float dString = sdSegment(pStringWavy, float2(0.0, 0.0), float2(0.0, -StringLength));

    // 6) Anti-aliasing / Masking
    // Use fwidth for pixel-perfect AA or fixed small value
    float aa = fwidth(p.y) * 1.5 + 0.001;
    
    // String Mask (Background)
    float maskString = 1.0 - smoothstep(StringThickness * 0.5, StringThickness * 0.5 + aa, dString);
    
    // Balloon Mask (Foreground)
    float maskBalloon = 1.0 - smoothstep(0.0, aa, dBalloon);

    // 7) Composite Colors
    // Premultiplied Alpha Blending: Result = Foreground + Background * (1 - Foreground.Alpha)
    float4 colStr = float4(StringColor.rgb, 1.0) * (StringColor.a * maskString);
    float4 colBal = float4(BalloonColor.rgb, 1.0) * (BalloonColor.a * maskBalloon);

    // Blend Balloon Over String
    // out = Balloon + String * (1 - BalloonAlpha)
    // Note: colBal.a is the alpha coverage * color alpha. 
    // We need the coverage-weighted alpha for blending: colBal.a is effectively 'src alpha'
    outColor = colBal + colStr * (1.0 - colBal.a);
}

// ------------------------------------------------------------------------
//  Visual Result (High-level, parameter-invariant description)
// ------------------------------------------------------------------------
//  This function produces a **2D cartoon balloon** constructed from
//  analytic Signed Distance Functions (SDFs).
//
//  The resulting shape is composed of:
//  - An inflated elliptical body segment
//  - A small trapezoidal knot segment at the bottom, smoothly blended into the body
//  - A thin, wavy string segment extending downward from the knot
//
//  The geometry features a soft, organic connection between the balloon and
//  the knot to simulate rubber material. The string includes adjustable sine-wave
//  distortion to simulate slack. The final appearance (inflation, knot size,
//  string waviness, and colors) is fully controlled by input parameters.
//
//  The output is an anti-aliased RGBA color suitable for procedural UI,
//  party icons, and 2D game assets.
// ------------------------------------------------------------------------