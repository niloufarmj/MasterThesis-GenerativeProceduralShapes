/*
  User Request: A repeating wave-like shape masked into a fixed area.
  Features: Adjustable frequency, amplitude, density, thickness. Centered pattern.
*/

#ifndef PI
#define PI 3.14159265359
#endif

// SDF for an axis-aligned box centered at origin
// p: sample point, b: half-extents (width/2, height/2)
float sdBox(float2 p, float2 b) {
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

void WaveMaskedPattern_float(float2 UV, float2 AreaSize, float WaveFrequency, float WaveAmplitude, float Density, float Thickness, float4 Color, out float4 outColor) {
    // PLAN:
    // 1. Center UV coordinates to (0,0) range [-0.5, 0.5]
    // 2. Calculate Box SDF for the masking area
    // 3. Calculate a distorted domain field for the waves: y + A*sin(x)
    // 4. Create repeating bands using frac() on the field
    // 5. Apply thickness and anti-aliasing to bands
    // 6. Combine Box Mask and Wave Pattern and output color

    // 1. Center UVs
    float2 p = UV - 0.5;

    // 2. Mask SDF (Box)
    // AreaSize is total width/height, so half-extents are AreaSize * 0.5
    float boxDist = sdBox(p, AreaSize * 0.5);
    // Soft AA for the box edges
    float boxAA = fwidth(boxDist);
    float maskAlpha = 1.0 - smoothstep(-boxAA, boxAA, boxDist);

    // 3. Wave Field Calculation
    // We want horizontal waves, so we distort the Y coordinate based on X
    // Formula: field = y + Amplitude * sin(x * Frequency * 2PI)
    // This creates a coordinate system that "waves" up and down
    float waveOffset = WaveAmplitude * sin(p.x * WaveFrequency * 2.0 * PI);
    float field = p.y + waveOffset;

    // 4. Repeating Bands Logic
    // Scale the field by density to create repetition
    // Add 0.5 to phase shift so a line is centered at (0,0)
    float cell = field * Density + 0.5;
    
    // Calculate distance to the center of the nearest band in "cell space"
    // frac(cell) is 0..1, -0.5 is -0.5..0.5, abs is 0..0.5
    // 0 = center of band, 0.5 = edge of band
    float distToLineCenter = abs(frac(cell) - 0.5);

    // 5. Shaping and Anti-aliasing
    // To keep line width consistent despite the wave slope, we technically need the gradient.
    // Gradient magnitude correction (optional but good for uniform thickness):
    // d(field)/dx = Amp * Freq * 2PI * cos(...)
    // d(field)/dy = 1
    float dFdx = WaveAmplitude * WaveFrequency * 2.0 * PI * cos(p.x * WaveFrequency * 2.0 * PI);
    float gradLen = sqrt(dFdx * dFdx + 1.0);
    
    // Adjust AA width based on the gradient and density
    // The field changes by 'Density * gradLen' per unit screen space approx
    // Ideally we use fwidth on the cell value directly for robust AA
    float patternAA = fwidth(cell);
    
    // Thickness defines the ratio of filled space (0..1)
    // Our distToLineCenter goes 0..0.5. 
    // We want to fill when dist < Thickness * 0.5
    float threshold = Thickness * 0.5;
    
    // Smoothstep for the pattern stripes
    float patternAlpha = smoothstep(threshold + patternAA, threshold - patternAA, distToLineCenter);

    // 6. Combine and Output
    float finalAlpha = maskAlpha * patternAlpha;
    
    // Apply Color with calculated alpha
    // Using premultiplied alpha style for safety or standard transparency
    outColor = float4(Color.rgb * finalAlpha, finalAlpha);
}