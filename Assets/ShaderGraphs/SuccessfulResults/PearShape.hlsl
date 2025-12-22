#ifndef PI
#define PI 3.14159265359
#endif

// Helper: Smooth Union (Polynomial smin)
// Blends two SDFs smoothly with factor k
float opSmoothUnion(float d1, float d2, float k) {
    float h = clamp(0.5 + 0.5 * (d2 - d1) / max(k, 0.001), 0.0, 1.0);
    return lerp(d2, d1, h) - k * h * (1.0 - h);
}

void PearShape_float(float2 UV, float Size, float Height, float TopScale, float StemSize, float4 BodyColor, float4 StemColor, out float4 outColor) {
    // PLAN:
    // 1) Center and scale UV coordinates. Scale controls overall size.
    // 2) Define Pear Body using two circles (bottom wider, top narrower) and blend them smoothly.
    // 3) Define Stem using a domain-warped capsule (parabolic bend) for a simple curved stem.
    // 4) Compute smooth masks for anti-aliasing.
    // 5) Composite Stem over Body with colors and output.

    // 1. Setup Coordinates
    float2 p = UV - 0.5;
    p /= max(Size, 0.0001); // Avoid division by zero

    // 2. Body Construction
    // Define dimensions
    float rBottom = 0.35;
    float rTop = 0.25 * max(TopScale, 0.01); // Top circle radius scaling
    float distY = 0.2 * max(Height, 0.01);   // Vertical elongation

    // Bottom Circle (The main body)
    float2 cBottom = float2(0.0, -distY);
    float dBottom = length(p - cBottom) - rBottom;

    // Top Circle (The neck)
    // Push it up based on Height
    float2 cTop = float2(0.0, distY * 1.5);
    float dTop = length(p - cTop) - rTop;

    // Smooth Blend to create the pear shape
    float blendFactor = 0.25;
    float dBody = opSmoothUnion(dBottom, dTop, blendFactor);

    // 3. Stem Construction
    // Use domain distortion to bend a vertical capsule
    float2 stemBase = cTop + float2(0.0, rTop * 0.85); // Attach near top
    float2 pStem = p - stemBase;

    // Rotate stem slightly to the right
    float angle = -0.2;
    float s = sin(angle), c = cos(angle);
    pStem = float2(c * pStem.x - s * pStem.y, s * pStem.x + c * pStem.y);

    // Apply parabolic bend: x = x - k*y^2
    float bendAmount = 2.0;
    pStem.x -= bendAmount * pStem.y * pStem.y;

    // Calculate Capsule SDF
    float stemHeight = 0.2 * max(StemSize, 0.001) * 3.0;
    float stemRadius = 0.02 * max(StemSize, 0.001) * 3.0;
    
    // Distance to segment (0,0) -> (0, stemHeight)
    float2 pa = pStem;
    float2 ba = float2(0.0, stemHeight);
    float hStem = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    float dStem = length(pa - ba * hStem) - stemRadius;

    // 4. AA and Masks
    // Use fwidth for screen-space anti-aliasing width
    float aa = fwidth(dBody);
    aa = max(aa, 0.001); // Safety for previews

    float bodyMask = 1.0 - smoothstep(-aa, aa, dBody);
    float stemMask = 1.0 - smoothstep(-aa, aa, dStem);

    // 5. Composition
    // Mix colors: Stem appears ON TOP of the body
    // Logic: If stemMask is 1, show StemColor. Else show BodyColor (if bodyMask is 1).
    float3 finalRGB = lerp(BodyColor.rgb, StemColor.rgb, stemMask);
    
    // Final alpha is the union of both shapes
    float finalAlpha = saturate(max(bodyMask, stemMask));

    // Output straight alpha color (standard for ShaderGraph Unlit nodes)
    outColor = float4(finalRGB, finalAlpha);
}