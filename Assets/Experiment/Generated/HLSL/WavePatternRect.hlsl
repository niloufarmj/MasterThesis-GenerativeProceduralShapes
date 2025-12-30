#ifndef PI
#define PI 3.14159265359
#endif

// Helper: Signed Distance Function for a Box
inline float sdBox(float2 p, float2 b) {
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

void WavePatternRect_float(float2 UV, float Width, float Height, float Frequency, float Amplitude, float Density, float Thickness, float4 Color, out float4 outColor) {
    // PLAN:
    // 1) Center UVs to (0,0) for shape alignment.
    // 2) Compute Box SDF to define the masking area (Width x Height).
    // 3) Create a wave coordinate by distorting Y with sin(X).
    // 4) Generate repeating bands using a cosine pattern on the distorted Y.
    // 5) Calculate anti-aliased masks for both the box and the pattern.
    // 6) Combine masks and output final RGBA color.

    // 1. Center Coordinates
    float2 p = UV - 0.5;

    // 2. Box Mask (Container)
    // Calculate box half-extents
    float2 halfSize = float2(max(Width, 0.0), max(Height, 0.0)) * 0.5;
    // Get Box SDF
    float dBox = sdBox(p, halfSize);
    // Analytic AA for box edges
    float boxAA = fwidth(dBox);
    float boxMask = 1.0 - smoothstep(0.0, max(boxAA, 1e-5), dBox);

    // 3. Wave Pattern Calculation
    // Distort the Y coordinate based on X to create the wave shape
    // y_wave = constant implies a sine wave curve in space
    float waveY = p.y + sin(p.x * Frequency) * Amplitude;

    // 4. Repeating Bands
    // Use cosine to create a repeating pattern along the distorted Y axis
    // Density controls vertical repetition, PI * 2 scales to full cycles
    float patternSig = cos(waveY * Density * 2.0 * PI);
    
    // Map [-1, 1] cosine output to [0, 1] for easier thresholding
    float normSig = patternSig * 0.5 + 0.5;

    // 5. Pattern Masking
    // We want the pattern to be visible where value > threshold
    // Thickness (0-1) determines how 'fat' the wave lines are
    float thresh = 1.0 - saturate(Thickness);
    // Analytic AA for the pattern using derivatives
    float patAA = fwidth(normSig);
    // Mask the pattern with smooth edges
    float patternMask = smoothstep(thresh - patAA, thresh + patAA + 1e-5, normSig);

    // 6. Composition
    // Combine the box container mask and the internal wave pattern mask
    float finalAlpha = boxMask * patternMask;
    
    // Output final color (pre-multiplied alpha style or straight alpha depending on blend mode)
    // Here we use straight alpha logic masked by the shape
    outColor = float4(Color.rgb * finalAlpha, saturate(Color.a) * finalAlpha);
}