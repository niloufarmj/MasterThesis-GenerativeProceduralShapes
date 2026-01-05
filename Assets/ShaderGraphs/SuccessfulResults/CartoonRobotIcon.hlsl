/* 
  PLAN:
  1. Define SDF helpers: Circle, Segment (Capsule), RoundedBoxVarying (individual corner radii).
  2. Normalize UV coordinates to centered local space [-1, 1], scaled by Size.
  3. Define shapes using symmetry (abs(p.x)):
     - Body: Box with rounded bottom corners.
     - Head: Semi-circle positioned above body with a gap.
     - Eyes: Circles inside the head.
     - Antennas: Angled segments on top of head.
     - Limbs: Vertical segments for arms (sides) and legs (bottom).
  4. Combine all structural parts (Body, Head, Limbs, Antennas) into a single SDF `dTotal` using min().
  5. Keep Eyes SDF separate.
  6. Compute masks for Outline (dTotal < width), Fill (dTotal < 0), and Eyes.
  7. Composite colors: Outline -> Body Fill -> Eyes.
*/

#ifndef PI
#define PI 3.14159265359
#endif

// --- Helpers defined inline ---

// Standard Circle SDF
float sdCircle(float2 p, float r) {
    return length(p) - r;
}

// Segment (Capsule) SDF
float sdSegment(float2 p, float2 a, float2 b) {
    float2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}

// Box with varying corner radii
// radii components: (top-right, bottom-right, top-left, bottom-left)
float sdRoundedBoxVarying(float2 p, float2 b, float4 radii) {
    radii.xy = (p.x > 0.0) ? radii.xy : radii.zw;
    radii.x  = (p.y > 0.0) ? radii.x  : radii.y;
    float2 q = abs(p) - b + radii.x;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - radii.x;
}

// Main Function
void CartoonRobotIcon_float(float2 UV, float Size, float LimbLength, float LimbThickness, float OutlineWidth, float4 MainColor, float4 OutlineColor, float4 EyeColor, out float4 outColor) {
    // 1. Setup Coordinate Space
    // Map UV (0..1) to (-1..1) then scale by Size
    float2 p = (UV - 0.5) * 2.0;
    p /= max(Size, 0.001); // Avoid divide by zero

    // Create symmetric coordinate for X-axis reflection
    float2 symP = float2(abs(p.x), p.y);

    // --- Shape Definitions ---
    
    // Constants for proportions
    float bodyW = 0.35;
    float bodyH = 0.30;
    float headR = 0.35;
    float gap = 0.05;
    
    // 2. Body: Rectangle with rounded bottom corners
    // Center body slightly down to make room for head
    float2 bodyPos = float2(0.0, -0.15);
    float2 pBody = p - bodyPos;
    // Radii: Top-Right(0.02), Bottom-Right(0.15), Top-Left(0.02), Bottom-Left(0.15)
    float4 bodyRadii = float4(0.02, 0.15, 0.02, 0.15);
    float dBody = sdRoundedBoxVarying(pBody, float2(bodyW, bodyH), bodyRadii);

    // 3. Head: Semi-circle
    // Positioned above body
    float2 headPos = bodyPos + float2(0.0, bodyH + gap);
    float2 pHead = p - headPos;
    // Intersection of Circle and Plane (y > 0)
    // We want the semi-circle to sit flat on the gap line
    float dHeadCircle = length(pHead) - headR;
    float dHeadClip = -pHead.y; // Positive below the line
    float dHead = max(dHeadCircle, dHeadClip);

    // 4. Eyes
    float2 eyePos = headPos + float2(0.12, 0.12);
    float dEyes = sdCircle(symP - eyePos, 0.06);

    // 5. Antennas
    // Angled lines from top of head
    float2 antStart = headPos + float2(0.15, headR * 0.9);
    float2 antEnd = antStart + float2(0.1, 0.25);
    float dAnt = sdSegment(symP, antStart, antEnd) - 0.02;

    // 6. Limbs
    // Arms: Hanging at sides
    float2 armStart = bodyPos + float2(bodyW + 0.02, bodyH * 0.6);
    float2 armEnd = armStart - float2(0.0, LimbLength);
    float dArms = sdSegment(symP, armStart, armEnd) - LimbThickness;

    // Legs: Extending from bottom
    float2 legStart = bodyPos + float2(bodyW * 0.5, -bodyH + 0.05);
    float2 legEnd = legStart - float2(0.0, LimbLength);
    float dLegs = sdSegment(symP, legStart, legEnd) - LimbThickness;

    // --- Composition ---
    
    // Combine all solid parts for the main silhouette
    float dTotal = dBody;
    dTotal = min(dTotal, dHead);
    dTotal = min(dTotal, dAnt);
    dTotal = min(dTotal, dArms);
    dTotal = min(dTotal, dLegs);

    // --- Rendering ---
    
    // Antialiasing factor based on screen-space derivatives
    float aa = fwidth(dTotal);
    aa = max(aa, 0.001);

    // Masks
    // Outline: Shape dilated by OutlineWidth
    float maskOutline = 1.0 - smoothstep(OutlineWidth, OutlineWidth + aa, dTotal);
    
    // Fill: Original shape interior
    float maskFill = 1.0 - smoothstep(0.0, aa, dTotal);
    
    // Eyes: Separate fill
    float maskEyes = 1.0 - smoothstep(0.0, aa, dEyes);

    // Layer Mixing
    // Start with background (transparent)
    float4 col = float4(0.0, 0.0, 0.0, 0.0);
    
    // Layer 1: Outline (Draws the full silhouette in OutlineColor)
    // We use the outline mask. Alpha is set by outline coverage.
    col = float4(OutlineColor.rgb * maskOutline, maskOutline * OutlineColor.a);
    
    // Layer 2: Main Body Fill (Draws over the outline, leaving the rim)
    // We blend MainColor over the current buffer using alpha blending equation
    // However, since we are outputting premultiplied-like alpha or standard, let's mix RGB.
    // A simple approach for solid colors:
    float3 bodyRGB = lerp(col.rgb, MainColor.rgb, maskFill);
    col = float4(bodyRGB, max(col.a, maskFill * MainColor.a));
    
    // Layer 3: Eyes (Draws over Body)
    float3 finalRGB = lerp(col.rgb, EyeColor.rgb, maskEyes);
    float finalAlpha = max(col.a, maskEyes * EyeColor.a);

    outColor = float4(finalRGB, finalAlpha);
}

// ------------------------------------------------------------------------
//  Visual Result
// ------------------------------------------------------------------------
//  This function generates a **stylized cartoon robot icon** (resembling the
//  classic "bugdroid" mascot) using Signed Distance Functions (SDFs).
//
//  The visual result is composed of:
//  - A semi-circular **head** containing two circular eyes and topped with 
//    two angled, antenna-like sensors.
//  - A rounded rectangular **body** with a flat top and deeply rounded bottom corners.
//  - Symmetrical **limbs**, including floating capsule arms on the sides and 
//    short stubby legs at the base.
//  - A distinct horizontal gap separating the head from the body.
//
//  The shape features adjustable parameters for the limb length and thickness,
//  overall size, and outline width. The main body, outline, and eyes can be
//  colored independently.
//
//  The output is a clean, flat-shaded graphic with a thick contiguous outline,
//  ideal for operating system logos, technology avatars, or sci-fi UI elements.
// ------------------------------------------------------------------------