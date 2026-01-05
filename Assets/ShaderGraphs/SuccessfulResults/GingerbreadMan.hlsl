#ifndef PI
#define PI 3.14159265359
#endif

// --- Helper Functions ---

// Signed distance to a circle
float gm_sdCircle(float2 p, float r) {
    return length(p) - r;
}

// Signed distance to a line segment (capsule)
float gm_sdSegment(float2 p, float2 a, float2 b) {
    float2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}

// Smooth minimum for blending shapes (organic/doughy look)
float gm_smin(float a, float b, float k) {
    float h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * 0.25;
}

// Signed distance to a wavy band crossing a segment
// p: sample point, a: segment start, b: segment end
// posT: relative position along segment (0.0 to 1.0) for the band center
// thick: band thickness, amp: wave amplitude, freq: wave frequency
float gm_sdWavyBand(float2 p, float2 a, float2 b, float posT, float thick, float amp, float freq) {
    float2 pa = p - a;
    float2 ba = b - a;
    float len = length(ba);
    float2 dir = ba / len;
    // Perpendicular vector for wave displacement
    float2 perp = float2(-dir.y, dir.x);
    
    // Project p to local coordinates (u along line, v across line)
    float u = dot(pa, dir);
    float v = dot(pa, perp);
    
    // Calculate wave offset based on transverse position v
    float wave = sin(v * freq) * amp;
    
    // Distance to the wavy center line at target u position
    float targetU = len * posT;
    float dist = abs(u - (targetU + wave)) - thick;
    
    return dist;
}

// --- Main Function ---
// Description: A customizable 2D gingerbread man with adjustable proportions, buttons, wavy icing, and outline.
void GingerbreadMan_float(
    float2 UV,
    float Size,
    float HeadSize,
    float BodyWidth,
    float BodyHeight,
    float LimbLength,
    float LimbThickness,
    float ButtonCount,
    float ButtonSize,
    float IcingThickness,
    float IcingWaviness,
    float StrokeThickness,
    float4 BodyColor,
    float4 ButtonColor,
    float4 IcingColor,
    float4 StrokeColor,
    out float4 outColor)
{
    // 1. Setup Coordinates
    // Center UVs at (0.5, 0.5) and scale by Size parameter
    float2 center = float2(0.5, 0.5);
    float2 p = (UV - center) / max(Size, 0.001);
    
    // Use symmetry for left/right side (x-axis reflection)
    float2 symP = float2(abs(p.x), p.y);
    
    // 2. Define Skeleton Points
    float hBody = BodyHeight * 0.5;
    float wBody = BodyWidth * 0.5;
    
    // Head position (stacked on top of body)
    float2 headPos = float2(0.0, hBody + HeadSize * 0.8);
    
    // Torso Segment (spine)
    float2 torsoTop = float2(0.0, hBody - wBody);
    float2 torsoBot = float2(0.0, -hBody + wBody);
    // Clamp to ensure segment is valid even if width > height
    torsoTop.y = max(torsoTop.y, torsoBot.y);
    
    // Arm positions (attached to upper torso)
    float2 shoulder = float2(wBody * 0.8, hBody * 0.3);
    float2 armDir = normalize(float2(1.0, -0.3)); // Arms angled slightly down
    float2 hand = shoulder + armDir * LimbLength;
    
    // Leg positions (attached to lower torso)
    float2 hip = float2(wBody * 0.5, -hBody * 0.5);
    float2 legDir = normalize(float2(0.5, -1.0)); // Legs angled out
    float2 foot = hip + legDir * LimbLength;
    
    // 3. Body SDF Construction
    float dHead = gm_sdCircle(p - headPos, HeadSize);
    float dTorso = gm_sdSegment(p, torsoTop, torsoBot) - wBody;
    float dArm = gm_sdSegment(symP, shoulder, hand) - LimbThickness;
    float dLeg = gm_sdSegment(symP, hip, foot) - LimbThickness;
    
    // Smoothly blend parts to create 'baked dough' look
    float k = 0.06; // Blending factor
    float dBody = gm_smin(dHead, dTorso, k);
    dBody = gm_smin(dBody, dArm, k);
    dBody = gm_smin(dBody, dLeg, k);
    
    // 4. Decorations SDF
    
    // Buttons: Vertical row along the torso
    float dButtons = 100.0;
    float nBtns = floor(max(ButtonCount, 0.0));
    float btnStartY = hBody * 0.3;
    float btnEndY = -hBody * 0.3;
    
    // Loop for buttons (max 10 safe limit, usually 2-4)
    if (nBtns > 0.5) {
        for (float i = 0.0; i < nBtns; i += 1.0) {
            float t = (nBtns > 1.5) ? (i / (nBtns - 1.0)) : 0.5;
            float yPos = lerp(btnStartY, btnEndY, t);
            float dOneBtn = gm_sdCircle(p - float2(0.0, yPos), ButtonSize);
            dButtons = min(dButtons, dOneBtn);
        }
    }
    
    // Icing: Wavy bands on wrists and ankles
    float waveFreq = 15.0 + IcingWaviness * 20.0;
    float waveAmp = 0.01 + IcingWaviness * 0.04;
    float icingPosT = 0.85; // Position along limb (near end)
    
    float dArmIcing = gm_sdWavyBand(symP, shoulder, hand, icingPosT, IcingThickness, waveAmp, waveFreq);
    float dLegIcing = gm_sdWavyBand(symP, hip, foot, icingPosT, IcingThickness, waveAmp, waveFreq);
    float dIcing = min(dArmIcing, dLegIcing);
    
    // 5. Rendering & Compositing
    
    // Calculate AA width
    float aa = fwidth(dBody);
    aa = max(aa, 0.001); // Safety for previews
    
    // Stroke Logic: Centered on the SDF zero-crossing or Outer?
    // We'll use a centered stroke approach where the total silhouette includes the stroke.
    // dBody < 0 is the nominal shape.
    float halfStroke = StrokeThickness * 0.5;
    
    // Masks
    // 1. Silhouette (Overall shape including stroke)
    float dSilhouette = dBody - halfStroke;
    float maskSilhouette = 1.0 - smoothstep(0.0, aa, dSilhouette);
    
    // 2. Inner Body (Shape minus stroke)
    float dInner = dBody + halfStroke;
    float maskInner = 1.0 - smoothstep(0.0, aa, dInner);
    
    // 3. Decorations (Layered on top of Inner Body)
    // Clip icing to the inner body so it doesn't spill onto the stroke
    float dIcingClipped = max(dIcing, dInner);
    float maskIcing = 1.0 - smoothstep(0.0, aa, dIcingClipped);
    
    float maskButton = 1.0 - smoothstep(0.0, aa, dButtons);
    
    // Composition (Painter's Algorithm)
    // Start with Stroke
    float3 finalRGB = StrokeColor.rgb;
    
    // Blend Body Fill over Stroke
    // If maskInner is 1, we see Body. If 0, we see Stroke (if inside silhouette).
    finalRGB = lerp(finalRGB, BodyColor.rgb, maskInner);
    
    // Blend Icing over Body
    finalRGB = lerp(finalRGB, IcingColor.rgb, maskIcing);
    
    // Blend Buttons over everything
    finalRGB = lerp(finalRGB, ButtonColor.rgb, maskButton);
    
    // Final Alpha is determined by the silhouette
    float finalAlpha = maskSilhouette;
    
    // Output premultiplied alpha or standard straight alpha with mask in A
    outColor = float4(finalRGB * finalAlpha, finalAlpha);
}

// ------------------------------------------------------------------------
//  Visual Result
// ------------------------------------------------------------------------
//  This function generates a **stylized cartoon gingerbread man** using 
//  Signed Distance Functions (SDFs).
//
//  The visual result is composed of:
//  - A main **body** formed by the smooth union of a circular head, a capsule 
//    torso, and rounded capsule limbs (arms and legs), creating an organic, 
//    "baked dough" silhouette.
//  - A vertical row of circular **buttons** distributed along the chest.
//  - Decorative **wavy icing bands** wrapped around the wrists and ankles.
//
//  The shape features adjustable parameters for body proportions, limb length 
//  and thickness, button count, and the amplitude/frequency of the icing waves.
//
//  The output renders with a thick, cohesive outline. The internal decorations 
//  (icing and buttons) are layered on top of the body fill but clipped to 
//  remain strictly inside the border stroke.
// ------------------------------------------------------------------------