#ifndef PI
#define PI 3.14159265359
#endif

// Signed distance function for a rounded box centered at origin
float sdRoundBox_U(float2 p, float2 b, float r)
{
    float2 q = abs(p) - b + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

// Signed distance function for an axis-aligned box centered at origin
float sdBox_U(float2 p, float2 b)
{
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

void UShapeThickArc_float(
    float2 UV,
    float2 Center,
    float OuterRadius,
    float InnerRadius,
    float ArmHeight,
    float4 FillColor,
    out float4 outColor
)
{
    // PLAN:
    // 1) Translate UV relative to Center.
    // 2) Build the outer rounded rectangle (large stadium-like shape, vertical).
    // 3) Build the inner rounded rectangle (cutout hole, smaller).
    // 4) Subtract inner from outer to get a hollow O-ring / track.
    // 5) Build a rectangular mask covering the top portion (to open the U at the top).
    // 6) Subtract the top mask from the hollow shape to get the U.
    // 7) Apply fill color with anti-aliasing.

    // 1) Recenter
    float2 p = UV - Center;

    // Clamp inputs to safe ranges
    float outerR = max(OuterRadius, 0.01);
    float innerR = clamp(InnerRadius, 0.01, outerR - 0.01);
    float armH = max(ArmHeight, 0.01);

    // The U shape:
    // - Two vertical arms extend upward from a rounded bottom.
    // - The overall shape is like a rounded rectangle but hollow inside,
    //   with the top open.
    //
    // We model it as:
    //   outer rounded box MINUS inner rounded box MINUS top-open rectangle mask.
    //
    // The outer rounded box: half-extents (outerR, armH + outerR), corner radius = outerR
    //   This makes the bottom fully rounded.
    // The inner rounded box: half-extents (innerR, armH + innerR), corner radius = innerR
    //   Subtracted from outer to create the hollow track.
    // Top mask: a box that covers from y = 0 upward (to open the top).

    // 2) Outer shape: rounded rectangle
    // Center the shape so the bottom arc is at y = 0, arms go upward.
    // Shift p down so center of shape is at arms midpoint.
    // The outer rounded rect half-size: width = outerR, height = armH + outerR
    // Its center is at y = armH/2 + outerR/2 ... let's think more carefully.
    //
    // For a U: the bottom semicircle has radius outerR.
    // The arms go straight up from the semicircle endpoints.
    // Center the rounded rect at (0, armH/2) so bottom is at y = -armH/2 - outerR
    // and top is at y = armH/2 + outerR.
    // We'll shift our query point accordingly.

    // Shape center offset: move down so the U opening is at the top of UV space
    // We keep the SDF center at p=(0,0) but shift the shape downward
    // so the U arms extend upward and the bottom arc is below center.

    // Outer rounded rect: half-extents in x = outerR, half-extents in y = armH * 0.5
    // with corner rounding = outerR. This gives a shape that has:
    //   - flat top and bottom? No - with corner rounding = outerR and half-extent x = outerR,
    //     it becomes fully rounded at top and bottom (like a stadium).
    // We want only the bottom to be rounded. So we use a trick:
    //   Use a large half-extent in y so the top corners are at the arm tops,
    //   and rounding only affects the bottom.

    // Actually the cleanest approach:
    // sdRoundBox with half-size b = (armWidth*0.5, armHeight*0.5 + bottomRadius*0.5)
    // and corner radius = bottomRadius ... but that rounds all corners equally.
    //
    // Better approach: use the capsule/stadium SDF concept.
    // A stadium = two circles connected by a rectangle.
    // The outer stadium has two circles of radius outerR connected over height armH.
    // The inner stadium has two circles of radius innerR connected over height armH.
    // Hollow = outer - inner. Then cut off the top.

    // Stadium SDF: segment from (0, -armH*0.5) to (0, armH*0.5), expanded by radius
    // This creates a vertical stadium (capsule).

    // For the U, we want the opening at the TOP, so the bottom is the rounded cap.
    // The stadium is symmetric, so we'll use it as-is and then cut the top open.

    // Outer stadium
    float2 pOuter = p;
    float halfH = armH * 0.5;
    // Clamp y to segment range
    float2 pOuterSeg = pOuter;
    pOuterSeg.y -= clamp(pOuterSeg.y, -halfH, halfH);
    float dOuter = length(pOuterSeg) - outerR;

    // Inner stadium (cutout)
    float2 pInner = p;
    float2 pInnerSeg = pInner;
    pInnerSeg.y -= clamp(pInnerSeg.y, -halfH, halfH);
    float dInner = length(pInnerSeg) - innerR;

    // Hollow shape: outer AND NOT inner
    // = intersection of outer with NOT inner
    // = max(dOuter, -dInner)
    float dHollow = max(dOuter, -dInner);

    // Top mask: cut off the top open part.
    // We want to remove everything above y = 0 (the horizontal midline).
    // The top mask is a box covering [everything, y > 0].
    // SDF of half-plane y > cutY: p.y - cutY (negative below, positive above)
    // To subtract the top portion, we do:
    //   dU = max(dHollow, -(top half-plane))
    // i.e., keep only where dHollow is the U shape AND we're NOT in the top half-plane.
    // Wait, subtraction of region R from shape S:
    //   result = max(dS, -dR)
    // where dR < 0 means inside R.
    // Top half-plane: dTop = -(p.y - 0) = -p.y ... negative means above y=0.
    // Hmm, let's be precise:
    // Half-plane above y=0: SDF = -(p.y - 0) if we define inside = above.
    //   Actually half-plane 'y > 0' as SDF: d = -p.y (inside when p.y > 0, so d < 0)
    //   No: d = -p.y means d < 0 when p.y > 0. Yes that's correct.
    // Subtract top half-plane from hollow:
    //   dU = max(dHollow, -(-p.y)) = max(dHollow, p.y)
    // This removes the part where p.y > 0... but we want to keep the arms.
    // The arms are the vertical portions. We want to remove the top cap BETWEEN the arms.
    // So we should only cut the inner top part.
    //
    // Actually for a U shape: we want to remove the TOP opening.
    // The stadium is symmetric top-bottom. To make a U (open top):
    // We just need to cut out the upper portion of the INNER space.
    // Actually we want to keep the two arms fully but remove the top arc.
    //
    // Think of it this way: the hollow stadium looks like an 'O'.
    // To make it a 'U', we cut away the top half of the O.
    // Cut with the half-plane y > 0:
    //   dU = max(dHollow, -(p.y)) ... no
    //   We want the region BELOW y=0 of the hollow O.
    //   Intersection of hollow with (y < 0 half-plane):
    //   half-plane y < 0: SDF d = p.y (inside when p.y < 0, d < 0)
    //   Intersection: max(dHollow, p.y)
    // But this cuts the arms at y=0, making a D-shape, not a U.
    //
    // For a proper U: the arms should extend ABOVE y=0.
    // The bottom arc should be at the bottom.
    // Let's reposition: place the bottom of the stadium at y = -armH/2 - outerR
    // and the top at y = armH/2 + outerR.
    // Cut at y = armH/2 (just where the top arc begins, keeping the arms full).
    // The cut removes the top arc: everything above y = halfH.
    // Inner space above y=halfH gets opened.
    //
    // Cut line: y = halfH
    // Keep region y < halfH: half-plane SDF = p.y - halfH (inside = below = negative when p.y < halfH)
    // Intersection: max(dHollow, p.y - halfH)
    //
    // This removes the top arc of the O shape, leaving U arms.

    float cutY = halfH;
    float dU = max(dHollow, p.y - cutY);

    // 7) Anti-aliasing and color
    float aa = fwidth(dU);
    float alpha = 1.0 - smoothstep(-aa * 0.5, aa * 0.5, dU);

    float4 col = FillColor;
    outColor = float4(col.rgb, col.a * alpha);
}
