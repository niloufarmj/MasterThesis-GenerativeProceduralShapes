#ifndef PI
#define PI 3.14159265359
#endif

// --- Helper Functions ---

// 1. Signed Distance to a Box
// b: half-extents
float sdBox(float2 p, float2 b) {
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// 2. Signed Distance to a Box with independent corner radii
// r: float4(top-right, bottom-right, top-left, bottom-left)
float sdRoundedBox4(float2 p, float2 b, float4 r) {
    r.xy = (p.x > 0.0) ? r.xy : r.zw;
    r.x  = (p.y > 0.0) ? r.x  : r.y;
    float2 q = abs(p) - b + r.x;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r.x;
}

// 3. Signed Distance to an Oriented Box (for the leg)
// a: start point, b: end point, th: thickness
float sdOrientedBox(float2 p, float2 a, float2 b, float th) {
    float l = length(b - a);
    float2 d = (b - a) / l;
    float2 q = (p - (a + b) * 0.5);
    q = float2(d.x * q.x + d.y * q.y, -d.y * q.x + d.x * q.y);
    q = abs(q) - float2(l, th) * 0.5;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
}

// 4. Composite Color (Source Over Destination)
float4 composite(float4 src, float4 dst) {
    float a = src.a + dst.a * (1.0 - src.a);
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-8);
    return float4(c, a);
}

// --- Main Function ---
// Draws a capital letter 'R' with adjustable loop, leg, thickness, and style.
void LetterRShape_float(
    float2 UV,
    float Width,
    float Height,
    float Thickness,
    float LoopBulge,    // 0..1, how far the loop extends right
    float LegAngle,     // radians, 0 is down, positive is right
    float CornerRound,  // corner radius
    float4 FillColor,
    float4 OutlineColor,
    float OutlineWidth,
    out float4 outColor
) {
    // Center UVs and handle sizing
    float2 p = UV - 0.5;
    
    // Half dimensions for calculations
    float hw = Width * 0.5;
    float hh = Height * 0.5;
    float th = Thickness;
    
    // Clamp corner radius to avoid artifacts
    float r = clamp(CornerRound, 0.0, min(th, min(Width, Height)) * 0.5);
    
    // --- 1. Spine (Vertical bar on the left) ---
    // Center x: Left edge (-hw) + half thickness
    float spineX = -hw + th * 0.5;
    float2 spinePos = float2(spineX, 0.0);
    // To support rounding, we shrink the box by r and subtract r from distance
    float2 spineSize = float2(th * 0.5, hh) - r;
    float dSpine = sdBox(p - spinePos, spineSize) - r;

    // --- 2. Loop (Top loop of the R) ---
    // The loop sits in the top half: y goes from 0 to hh
    // It connects to the spine. 
    // Outer loop box:
    float loopH = hh * 0.5; // Half-height of the loop part (total loop height is hh)
    float loopY = hh * 0.5; // Center Y of the loop area (midpoint of 0 and hh)
    float loopW = (Width * LoopBulge); // Total width of loop from spine left edge
    
    // Determine loop center and size
    // It starts at spine left (-hw) and goes to (-hw + loopW)
    float loopCenterX = -hw + loopW * 0.5;
    float2 loopCenter = float2(loopCenterX, loopY);
    float2 loopHalfSize = float2(loopW * 0.5, loopH) - r;
    
    // Use different rounding for the loop to make it D-shaped
    // Left corners match spine rounding, Right corners are fully rounded (or user defined)
    // For a classic R, the loop is often circular on the right.
    // We'll use the user's CornerRound, but allow the loop to be rounder if width allows.
    // To make a "D", top-right and bottom-right radii should be large.
    // Let's use a dynamic radius for the right side: blended between cornerRadius and full loop height.
    float rightRad = max(r, min(loopHalfSize.x, loopHalfSize.y));
    float4 loopRadii = float4(rightRad, rightRad, r, r);
    
    // Calculate SDFs for Loop
    // We shrink the box size by the radii in the sdRoundedBox4 function logic manually if needed,
    // but here we use the helper which handles corners. 
    // Note: Our helper `sdRoundedBox4` expects `b` to be the bounding box. 
    // It effectively subtracts radii from dimensions. 
    // To maintain exact size, we pass the full half-size and the radii.
    // Re-adjust loopHalfSize to be FULL size for the helper call:
    loopHalfSize = float2(loopW * 0.5, loopH);
    
    float dLoopOuter = sdRoundedBox4(p - loopCenter, loopHalfSize, loopRadii);
    
    // Inner hole
    // Smaller box inside. 
    float2 innerHalfSize = loopHalfSize - float2(th, th);
    float4 innerRadii = max(loopRadii - th, 0.0);
    float dLoopInner = sdRoundedBox4(p - loopCenter, innerHalfSize, innerRadii);
    
    // Loop is Outer minus Inner
    float dLoop = max(dLoopOuter, -dLoopInner);

    // --- 3. Leg (Angled leg) ---
    // Starts from the intersection of Spine and Loop bottom.
    // Start point: Spine right edge, Loop bottom y.
    float legStartX = -hw + th * 0.5; // Center of spine horizontally
    float legStartY = 0.0;            // Vertical center of the character (loop bottom)
    float2 legStart = float2(legStartX, legStartY);
    
    // Direction based on angle (0 = down, + = right)
    float2 legDir = float2(sin(LegAngle), -cos(LegAngle));
    
    // Calculate length to hit the baseline (y = -hh)
    // Ray: Start.y + t * Dir.y = -hh  =>  t = (-hh - Start.y) / Dir.y
    // Avoid divide by zero
    float t = (abs(legDir.y) > 0.001) ? (-hh - legStartY) / legDir.y : hh;
    // Clamp length to be reasonable
    float legLen = max(t, 0.0);
    float2 legEnd = legStart + legDir * legLen;
    
    // Create Leg SDF (Oriented Box)
    // We subtract r for rounding
    float dLeg = sdOrientedBox(p, legStart, legEnd, th - 2.0*r) - r;

    // --- 4. Combine Shapes ---
    // Union of Spine, Loop, Leg
    float dShape = min(dSpine, min(dLoop, dLeg));

    // --- 5. Rendering ---
    float aa = fwidth(dShape);
    
    // Fill Alpha
    float fillAlpha = 1.0 - smoothstep(-aa, aa, dShape);
    float4 fill = float4(FillColor.rgb * fillAlpha, FillColor.a * fillAlpha);
    
    // Outline Alpha (centered on edge)
    float halfOutline = OutlineWidth * 0.5;
    float dOutline = abs(dShape) - halfOutline;
    float outlineAlpha = 1.0 - smoothstep(-aa, aa, dOutline);
    float4 stroke = float4(OutlineColor.rgb * outlineAlpha, OutlineColor.a * outlineAlpha);
    
    // Composite Stroke OVER Fill
    outColor = composite(stroke, fill);
}