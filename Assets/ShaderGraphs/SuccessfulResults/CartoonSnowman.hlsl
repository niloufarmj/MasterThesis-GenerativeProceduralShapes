#ifndef PI
#define PI 3.14159265359
#endif

// --- Helper Functions ---

void sm_layer(inout float4 bg, float4 fg, float mask) {
    float alpha = fg.a * mask;
    float outA = alpha + bg.a * (1.0 - alpha);
    float3 outRGB = (fg.rgb * alpha + bg.rgb * bg.a * (1.0 - alpha)) / max(outA, 1e-6);
    bg = float4(outRGB, outA);
}

float sm_sdCircle(float2 p, float r) {
    return length(p) - r;
}

float sm_sdBox(float2 p, float2 b) {
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

float sm_sdRoundBox(float2 p, float2 b, float r) {
    return sm_sdBox(p, b) - r;
}

float sm_sdSegment(float2 p, float2 a, float2 b) {
    float2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}

float sm_smin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / max(k, 0.0001), 0.0, 1.0);
    return lerp(b, a, h) - k * h * (1.0 - h);
}

// --- Main Function ---
void CartoonSnowman_float(
    float2 UV,
    float Size,
    float OutlineWidth,
    float4 OutlineColor,
    float4 SnowColor,
    float4 ScarfColor,
    float4 HatColor,
    float4 HatBandColor,
    float4 NoseColor,
    float4 ArmColor,
    float4 DetailColor,
    float ScarfStripeCount,
    float ScarfStripeThickness,
    float4 ScarfStripeColor,
    out float4 outColor
) {
    // 1. Coordinate Setup
    float2 p = (UV - 0.5) * 2.0;
    p /= max(Size, 0.001);
    float2 symP = float2(abs(p.x), p.y);

    // 2. Arms SDF (Stick branches)
    float dArmMain = sm_sdSegment(symP, float2(0.18, 0.05), float2(0.55, 0.25));
    float dArmBranch1 = sm_sdSegment(symP, float2(0.35, 0.14), float2(0.45, 0.35));
    float dArmBranch2 = sm_sdSegment(symP, float2(0.45, 0.19), float2(0.6, 0.15));
    float dArms = min(dArmMain, min(dArmBranch1, dArmBranch2)) - 0.015;

    // 3. Body SDF (Three snowballs blended smoothly)
    float dBase = sm_sdCircle(p - float2(0.0, -0.45), 0.35);
    float dTorso = sm_sdCircle(p - float2(0.0, 0.05), 0.25);
    float dHead = sm_sdCircle(p - float2(0.0, 0.45), 0.18);
    float dBody = sm_smin(dBase, dTorso, 0.08);
    dBody = sm_smin(dBody, dHead, 0.06);

    // 4. Scarf SDF (Wrap around neck + hanging tail)
    float dScarfWrap = sm_sdRoundBox(p - float2(0.0, 0.29), float2(0.16, 0.035), 0.03);
    float2 tailP = p - float2(0.12, 0.16);
    float c = cos(0.3), s = sin(0.3);
    tailP = float2(c * tailP.x - s * tailP.y, s * tailP.x + c * tailP.y);
    float dScarfTail = sm_sdRoundBox(tailP, float2(0.025, 0.10), 0.02);
    float dScarf = min(dScarfWrap, dScarfTail);

    // 5. Hat SDF (Top hat with brim and crown)
    float dBrim = sm_sdRoundBox(p - float2(0.0, 0.60), float2(0.24, 0.015), 0.01);
    float dCrown = sm_sdRoundBox(p - float2(0.0, 0.74), float2(0.13, 0.14), 0.02);
    float dHat = min(dBrim, dCrown);
    
    float dBandBox = sm_sdRoundBox(p - float2(0.0, 0.64), float2(0.15, 0.025), 0.01);
    float dBand = max(dBandBox, dCrown); // Intersect band bounds with crown shape

    // 6. Nose SDF (Horizontal carrot cone)
    float h = clamp(p.x / 0.25, 0.0, 1.0);
    float dNose = length(p - float2(h * 0.25, 0.42)) - lerp(0.04, 0.005, h);

    // 7. Details SDF (Eyes and Coal Buttons)
    float dEyes = sm_sdCircle(symP - float2(0.08, 0.48), 0.025);
    float dBtn1 = sm_sdCircle(p - float2(0.0, 0.18), 0.03);
    float dBtn2 = sm_sdCircle(p - float2(0.0, 0.03), 0.03);
    float dBtn3 = sm_sdCircle(p - float2(0.0, -0.12), 0.03);
    float dDetails = min(dEyes, min(dBtn1, min(dBtn2, dBtn3)));

    // --- Rendering Setup ---
    float aa = length(float2(fwidth(p.x), fwidth(p.y))) * 0.7071;
    aa = max(aa, 0.001);
    
    float4 res = float4(0.0, 0.0, 0.0, 0.0);

    // --- Compositing (Painter's Algorithm) ---
    
    // Layer 1: Arms (Behind everything)
    sm_layer(res, OutlineColor, 1.0 - smoothstep(OutlineWidth - aa, OutlineWidth + aa, dArms));
    sm_layer(res, ArmColor,     1.0 - smoothstep(0.0, aa, dArms));
    
    // Layer 2: Main Snow Body
    sm_layer(res, OutlineColor, 1.0 - smoothstep(OutlineWidth - aa, OutlineWidth + aa, dBody));
    sm_layer(res, SnowColor,    1.0 - smoothstep(0.0, aa, dBody));

    // Layer 3: Scarf with Stripes
    float stripePhase = p.y * ScarfStripeCount;
    float dStripe = abs(frac(stripePhase) - 0.5) - (ScarfStripeThickness * 0.5);
    float stripeAA = max(fwidth(stripePhase), 0.001);
    float stripeFactor = 1.0 - smoothstep(0.0, stripeAA, dStripe);
    float4 currentScarfColor = lerp(ScarfColor, ScarfStripeColor, stripeFactor);

    sm_layer(res, OutlineColor, 1.0 - smoothstep(OutlineWidth - aa, OutlineWidth + aa, dScarf));
    sm_layer(res, currentScarfColor,   1.0 - smoothstep(0.0, aa, dScarf));

    // Layer 4: Top Hat
    sm_layer(res, OutlineColor, 1.0 - smoothstep(OutlineWidth - aa, OutlineWidth + aa, dHat));
    sm_layer(res, HatColor,     1.0 - smoothstep(0.0, aa, dHat));
    sm_layer(res, HatBandColor, 1.0 - smoothstep(0.0, aa, dBand));

    // Layer 5: Carrot Nose
    sm_layer(res, OutlineColor, 1.0 - smoothstep(OutlineWidth - aa, OutlineWidth + aa, dNose));
    sm_layer(res, NoseColor,    1.0 - smoothstep(0.0, aa, dNose));

    // Layer 6: Coal Details (Eyes & Buttons)
    sm_layer(res, DetailColor,  1.0 - smoothstep(0.0, aa, dDetails));

    // Final Output
    outColor = res;
}

// ------------------------------------------------------------------------
//  Visual Result (High-level, parameter-invariant description)
// ------------------------------------------------------------------------
//  This function produces a **2D snowman illustration** constructed from analytic SDFs. The resulting shape is composed of:
//
//  - Three vertically stacked circular sections (body) smoothly blended together, creating a playful, rounded form.
//  - Stick-like segments extending from the sides, representing the snowman's arms.
//  - A horizontal, carrot-like cone protruding from the head, serving as the snowman's nose.
//  - A cylindrical top hat with a brim and crown situated on top of the head, featuring a distinct horizontal band.
//  - A scarf wrapping around the neck with additional vertical stripes, adding a pattern to the design.
//  - Small circular elements on the face and torso, depicting coal eyes and buttons.
//
//  These components are combined using smooth blending techniques, resulting in a cohesive, playful winter character.
// ------------------------------------------------------------------------
