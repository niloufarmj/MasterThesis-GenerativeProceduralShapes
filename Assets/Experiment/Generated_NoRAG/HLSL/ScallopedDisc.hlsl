#ifndef PI
#define PI 3.14159265359
#endif

// User request: a scalloped disc with evenly spaced smooth convex bumps distributed around its circular perimeter, filled by default with dark shade of colors

// Helper: 2D rotation
float2 ScallopedDisc_Rotate(float2 p, float angle)
{
    float c = cos(angle);
    float s = sin(angle);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

void ScallopedDisc_float(
    float2 UV,
    float Radius,
    float BumpCount,
    float BumpHeight,
    float BumpSmoothness,
    float4 FillColor,
    float4 StrokeColor,
    float StrokeWidth,
    out float4 outColor)
{
    // PLAN:
    // 1) Center UV to local coords p.
    // 2) Compute polar angle and radius of the sample point.
    // 3) Modulate the disc radius angularly with cos() to create evenly spaced convex bumps.
    //    Bumps are convex (outward bulges), so the boundary radius = BaseRadius + BumpHeight * (0.5 + 0.5*cos(theta * BumpCount)).
    // 4) SDF = distance of point from center minus the angular boundary radius.
    //    This gives negative inside, positive outside.
    // 5) Anti-alias with smoothstep using fwidth.
    // 6) Composite stroke over fill and output.

    // Step 1: Center coords
    float2 p = UV - float2(0.5, 0.5);

    // Step 2: Polar coordinates
    float dist = length(p);
    float angle = atan2(p.y, p.x);

    // Step 3: Scalloped boundary radius
    // BumpCount controls number of bumps around the perimeter
    // BumpHeight controls how tall each convex bump is
    // cos(angle * BumpCount) goes from -1 to 1, so (0.5 + 0.5*cos) goes 0..1 for smooth convex bumps
    float bumpPhase = cos(angle * BumpCount);
    float bumpProfile = 0.5 + 0.5 * bumpPhase; // 0..1, smooth and convex
    float boundaryRadius = Radius + BumpHeight * bumpProfile;

    // Step 4: SDF (negative inside, positive outside)
    float sdf = dist - boundaryRadius;

    // Step 5: Anti-aliased fill mask
    float aa = max(fwidth(sdf), 0.0001);
    float fillMask = 1.0 - smoothstep(-aa, aa, sdf);

    // Step 6: Stroke mask
    float halfStroke = StrokeWidth * 0.5;
    float strokeSdf = abs(sdf) - halfStroke;
    float strokeAa = max(fwidth(strokeSdf), 0.0001);
    float strokeMask = 1.0 - smoothstep(-strokeAa, strokeAa, strokeSdf);

    // Clamp masks
    fillMask = saturate(fillMask);
    strokeMask = saturate(strokeMask);

    // Composite stroke OVER fill
    float3 compositeRGB = lerp(FillColor.rgb * fillMask, StrokeColor.rgb, strokeMask * StrokeColor.a);
    float compositeA = saturate(fillMask + strokeMask * StrokeColor.a);

    outColor = float4(compositeRGB * compositeA, compositeA);
}