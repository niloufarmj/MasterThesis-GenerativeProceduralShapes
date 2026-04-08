#ifndef PI
#define PI 3.14159265359
#endif

// --- Helper Functions ---

// Rotate a 2D vector by an angle in radians
float2 rotate(float2 p, float angle) {
    float c = cos(angle);
    float s = sin(angle);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

// Signed distance to a vertical capsule
float sdVerticalCapsule(float2 p, float h, float r) {
    p.y -= clamp(p.y, -h, h);
    return length(p) - r;
}

// Composite Source Over Destination (Alpha Blending)
float4 compositeOver(float4 src, float4 dst) {
    float a = src.a + dst.a * (1.0 - src.a);
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-6);
    return float4(c, a);
}

// --- Main Function ---
void ProceduralHotDog_float(
    float2 UV,
    float GlobalRotation,
    float BunLength,
    float BunWidth,
    float4 BunColor,
    float InnerBunLength,
    float InnerBunWidth,
    float4 InnerBunColor,
    float SausageLength,
    float SausageWidth,
    float4 SausageColor,
    float MustardLength,
    float MustardWidth,
    float MustardWaveAmplitude,
    float MustardWaveFrequency,
    float4 MustardColor,
    out float4 outColor
) {
    // 1. Center and scale UV coordinates to range [-1, 1]
    float2 p = (UV - 0.5) * 2.0;
    
    // 2. Apply global rotation to tilt the hot dog
    p = rotate(p, GlobalRotation);

    // 3. Compute Distance Fields for each component
    // Outer Bun
    float hBun = max(0.0001, BunLength);
    float dBun = sdVerticalCapsule(p, hBun, BunWidth);

    // Inner Bun (slightly smaller, simulating the inside cut of the bread)
    float hInnerBun = max(0.0001, InnerBunLength);
    float dInnerBun = sdVerticalCapsule(p, hInnerBun, InnerBunWidth);

    // Sausage (longer and narrower)
    float hSausage = max(0.0001, SausageLength);
    float dSausage = sdVerticalCapsule(p, hSausage, SausageWidth);

    // Mustard (wavy domain distortion)
    // Calculate the wave distortion on the X axis using a sine function of the Y axis
    float waveDistortion = sin(p.y * MustardWaveFrequency) * MustardWaveAmplitude;
    float2 pMustard = p - float2(waveDistortion, 0.0);
    float hMustard = max(0.0001, MustardLength);
    float dMustard = sdVerticalCapsule(pMustard, hMustard, MustardWidth);

    // 4. Calculate Anti-Aliasing (AA) width based on derivative
    float aa = fwidth(p.x) * 1.5;
    aa = max(aa, 0.001); // Fallback for stability

    // 5. Generate Alpha Masks from SDFs using smoothstep
    float maskBun = 1.0 - smoothstep(-aa, aa, dBun);
    float maskInnerBun = 1.0 - smoothstep(-aa, aa, dInnerBun);
    float maskSausage = 1.0 - smoothstep(-aa, aa, dSausage);
    float maskMustard = 1.0 - smoothstep(-aa, aa, dMustard);

    // 6. Setup Individual Color Layers
    float4 layerBun = float4(BunColor.rgb, BunColor.a * maskBun);
    float4 layerInnerBun = float4(InnerBunColor.rgb, InnerBunColor.a * maskInnerBun);
    float4 layerSausage = float4(SausageColor.rgb, SausageColor.a * maskSausage);
    float4 layerMustard = float4(MustardColor.rgb, MustardColor.a * maskMustard);

    // 7. Composite Layers from Back to Front
    // Start with a transparent background
    float4 finalRender = float4(0.0, 0.0, 0.0, 0.0);
    
    finalRender = compositeOver(layerBun, finalRender);
    finalRender = compositeOver(layerInnerBun, finalRender);
    finalRender = compositeOver(layerSausage, finalRender);
    finalRender = compositeOver(layerMustard, finalRender);

    // 8. Output Final Color
    outColor = finalRender;
}
