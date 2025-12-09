#ifndef PI
#define PI 3.14159265359
#endif

// --- Helpers --------------------------------------------------------------

// Robust modulo that returns a positive result for positive divisor y
// (Unlike HLSL fmod which returns negative results for negative x)
#ifndef NM_MOD_HELPER
#define NM_MOD_HELPER
inline float nm_mod(float x, float y) {
    return x - y * floor(x / y);
}
#endif

// Guarded straight-alpha "src over dst" blending
#ifndef NM_OVER_HELPER
#define NM_OVER_HELPER
inline float4 nm_over(float4 src, float4 dst)
{
    float a = src.a + dst.a * (1.0 - src.a);
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-8);
    return float4(c, a);
}
#endif

// Signed distance to an N-pointed star centered at origin
// p: point in local space
// r: outer radius (distance to tips)
// rIn: inner radius (distance to valleys)
// n: number of points (clamped to >= 3)
inline float nm_sdStar(float2 p, float r, float rIn, float n)
{
    // Clamp points safely
    n = max(n, 3.0);
    
    // Angle per sector (half of the repeating unit)
    float an = PI / n;
    float sectorSpan = 2.0 * an;
    
    // Angle of p relative to +Y axis (0 at +Y)
    // We align the star Peak to the +Y axis in local space.
    float angle = atan2(p.x, p.y);
    
    // Map angle to the canonical sector [-an, an] centered on a Peak.
    // nm_mod(angle + an, ...) ensures we wrap correctly around 0.
    float bn = nm_mod(angle + an, sectorSpan) - an;
    
    // Rotate p into this canonical sector frame
    // In this frame, the bisector is the Y axis (angle 0).
    p = length(p) * float2(sin(bn), cos(bn));
    
    // Exploiting bilateral symmetry of the spike: x > 0
    p.x = abs(p.x);
    
    // Define the star edge segment in the first sector
    // It runs from the Peak (0, r) to the Valley (rIn*sin(an), rIn*cos(an))
    float2 p1 = float2(0.0, r);
    float2 p2 = float2(rIn * sin(an), rIn * cos(an));
    
    // Standard point-line distance with clamp (segment distance)
    float2 k = p2 - p1;
    float2 w = p - p1;
    float h = clamp(dot(w, k) / dot(k, k), 0.0, 1.0);
    float dist = length(w - k * h);
    
    // Sign determination via 2D cross product
    // k points from Peak to Valley (down-right).
    // We check if p is on the "inside" side of the vector k.
    // For the star center (0,0), crossVal is positive. Since center is inside,
    // positive cross implies inside. Inside SDF must be negative.
    float crossVal = w.x * k.y - w.y * k.x;
    
    return -dist * sign(crossVal);
}

// --- Main Function --------------------------------------------------------
// PLAN:
// 1) Center the UV coordinates (0.5, 0.5) -> (0,0).
// 2) Rotate the sampling point by -angle so the star appears rotated by +angle.
// 3) Calculate the Signed Distance Field (SDF) for the N-pointed star.
// 4) Compute analytic anti-aliasing width using fwidth().
// 5) Generate Fill mask and Stroke mask.
// 6) Composite Stroke over Fill for final output.

void StarColorOutlineCenteredRotated_float(
    float2 UV,
    float Points,
    float OuterRadius,
    float InnerRadius,
    float2 Center,
    float Rotation,
    float4 FillColor,
    float4 StrokeColor,
    float StrokeWidth,
    out float4 outColor)
{
    // 1) Recenter UV space
    float2 p = UV - Center;

    // 2) Rotate sampling point by -Rotation (CCW rotation of shape)
    float c = cos(Rotation);
    float s = sin(Rotation);
    float2 pr = float2(c * p.x + s * p.y,
                       -s * p.x + c * p.y);

    // 3) Compute Signed Distance Field
    float d = nm_sdStar(pr, max(OuterRadius, 0.0), max(InnerRadius, 0.0), Points);

    // 4) Analytic Anti-Aliasing
    // Ensure aa is never exactly 0 to avoid NaN in smoothstep
    float aa = fwidth(d);
    aa = max(aa, 1e-4);

    // 5) Fill Coverage (Inside the star)
    // smoothstep from 0 to aa creates a smooth transition at the edge
    float fillMask = 1.0 - smoothstep(0.0, aa, d);
    float4 fillOut = float4(FillColor.rgb, saturate(FillColor.a) * fillMask);

    // 6) Stroke Coverage (Band around the edge)
    float halfW = 0.5 * max(StrokeWidth, 0.0);
    float edgeDist = abs(d) - halfW;
    float strokeMask = 1.0 - smoothstep(0.0, aa, edgeDist);
    float4 strokeOut = float4(StrokeColor.rgb, saturate(StrokeColor.a) * strokeMask);

    // 7) Composite: Stroke OVER Fill
    outColor = nm_over(strokeOut, fillOut);
}