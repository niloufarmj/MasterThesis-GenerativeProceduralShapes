#ifndef PI
#define PI 3.14159265359
#endif

// Cartoon Picture Frame with Scalloped Edges and Clockwise Reveal
void CartoonPictureFrame_float(float2 UV, float2 FrameSize, float2 FrameMargins, float CornerRadius, float BumpCount, float BumpAmp, float BumpSmoothness, float OutlineWidth, float FillAmount, float4 BodyColor, float4 OutlineColor, out float4 outColor) {
    // Center UVs to (0,0)
    float2 p = UV - 0.5;

    // 1. Dimensions Setup
    float2 halfSize = FrameSize * 0.5;
    
    // 2. Outer Scalloped Shape SDF
    // Calculate base Rounded Box
    float2 d1 = abs(p) - halfSize + CornerRadius;
    float baseBox = length(max(d1, 0.0)) + min(max(d1.x, d1.y), 0.0) - CornerRadius;
    
    // Calculate Scallop Waves (Bumps)
    // Frequency N means N*2PI radians over the length. To fit 'Count' bumps:
    float2 freq = (max(BumpCount, 1.0) * 2.0 * PI) / max(FrameSize, 0.001);
    
    // Generate waves using Cosine, shaped by Smoothness power
    // 0.5+0.5*cos normalizes to 0..1 range before powering
    float wx = pow(0.5 + 0.5 * cos(p.x * freq.x), max(BumpSmoothness, 0.1));
    float wy = pow(0.5 + 0.5 * cos(p.y * freq.y), max(BumpSmoothness, 0.1));
    
    // Perturbation: subtract positive value to push surface outward
    // We combine x and y waves for continuous bubble effect around corners
    float perturb = BumpAmp * (wx + wy);
    float dOuter = baseBox - perturb;
    
    // 3. Inner Cutout SDF
    // Subtract margins for inner opening
    float2 halfSizeIn = max(halfSize - FrameMargins, 0.0);
    // Adjust inner radius to keep corners parallel (concentric)
    float radIn = max(0.0, CornerRadius - min(FrameMargins.x, FrameMargins.y));
    
    float2 d2 = abs(p) - halfSizeIn + radIn;
    float dInner = length(max(d2, 0.0)) + min(max(d2.x, d2.y), 0.0) - radIn;
    
    // 4. Composite Frame Body
    // Frame exists where: Inside Outer AND Outside Inner
    // SDF Boolean Subtraction: max(A, -B)
    float dFrame = max(dOuter, -dInner);
    
    // 5. Outline SDF
    // Outline is a shell around the frame body
    // Defined by distance to surface < OutlineWidth
    float dStroke = abs(dFrame) - OutlineWidth;
    
    // 6. Fill Animation (Clockwise from Top-Left)
    // Rotate coordinate system so Top-Left aligns with +Y (Top)
    // Top-Left is (-1, 1). Rotate +45 deg CW (or coords -45) to get (0, 1.414)
    // Rotation Matrix for -45 deg: cos=0.707, sin=-0.707
    float C = 0.7071067;
    float2 pRot = float2(p.x * C + p.y * C, -p.x * C + p.y * C);
    
    // Calculate angular progress (0 at Top, increasing Clockwise)
    // atan2(x, y) returns angle from Y-axis in range -PI to PI
    float angle = atan2(pRot.x, pRot.y);
    // Normalize -PI..PI to 0..1
    float t = frac(angle / (2.0 * PI));
    
    // Mask based on fill amount
    float fillMask = step(t, saturate(FillAmount));
    
    // 7. Rendering with Anti-Aliasing
    float aa = fwidth(dFrame);
    
    // Body and Stroke Alpha
    float alphaBody = 1.0 - smoothstep(-aa, aa, dFrame);
    float alphaStroke = 1.0 - smoothstep(-aa, aa, dStroke);
    
    // Composite Colors (Stroke on top of Body)
    // lerp Body to Outline based on stroke alpha
    float4 finalCol = lerp(BodyColor, OutlineColor, alphaStroke);
    
    // Final Shape Alpha (Union of Body and Stroke)
    float finalAlpha = max(alphaBody, alphaStroke);
    
    // Apply Wipe Animation
    finalAlpha *= fillMask;
    
    // Output premultiplied or straight alpha as requested (using straight here)
    outColor = float4(finalCol.rgb * finalAlpha, finalAlpha);
}