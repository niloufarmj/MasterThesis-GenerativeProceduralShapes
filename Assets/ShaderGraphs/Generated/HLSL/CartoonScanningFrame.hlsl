#ifndef PI
#define PI 3.14159265359
#endif

// SDF Helper for Box
float sdBox_CSF(float2 p, float2 b) {
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// SDF Helper for Rounded Box
float sdRoundedBox_CSF(float2 p, float2 b, float r) {
    return sdBox_CSF(p, b - r) - r;
}

void CartoonScanningFrame_float(float2 UV, float Width, float Height, float ArmLength, float ArmThickness, float CornerRoundness, float4 BracketColor, float4 StrokeColor, float StrokeWidth, float ScanLineY, float ScanLineWidth, float4 ScanLineColor, out float4 outColor) {
    // PLAN:
    // 1. Center coordinates and define frame dimensions.
    // 2. Compute SDF for the Brackets:
    //    - Create a hollow rounded frame (Outer Rounded Box minus Inner Box).
    //    - Create "Gap" SDFs to cut the frame sides and leave only corners.
    //    - Combine to get dBrackets.
    // 3. Render Brackets with a centered stroke/outline using smoothstep AA.
    // 4. Compute SDF for the Scan Line (horizontal bar).
    // 5. Composite Scan Line behind Brackets for final output.

    // 1. Coordinates
    float2 p = UV - 0.5;
    float2 frameSize = float2(max(Width, 0.0), max(Height, 0.0));
    float aa = length(fwidth(p)); // Anti-aliasing factor

    // 2. Bracket SDF
    // Outer Frame (Rounded)
    float dOuter = sdRoundedBox_CSF(p, frameSize * 0.5, CornerRoundness);
    
    // Inner Frame (Subtract sharp box to make hollow)
    float dInner = sdBox_CSF(p, frameSize * 0.5 - ArmThickness);
    float dHollow = max(dOuter, -dInner);

    // Gaps to cut the sides
    // Horizontal Gap cuts the top/bottom bars in the middle
    // Vertical Gap cuts the side bars in the middle
    // SDF is negative inside the gap region
    float gapH = abs(p.x) - (frameSize.x * 0.5 - ArmLength);
    float gapV = abs(p.y) - (frameSize.y * 0.5 - ArmLength);
    
    // Union of gaps (min of negative SDFs)
    float dGaps = min(gapH, gapV);
    
    // Final Bracket Shape: Hollow Frame minus Gaps
    // max(Hollow, -Gaps) works because Gaps are negative inside, so -Gaps is positive (outside)
    float dBrackets = max(dHollow, -dGaps);

    // 3. Render Brackets
    // Create a centered stroke around the bracket shape
    // Outer boundary of stroke
    float alphaOuter = 1.0 - smoothstep(-aa, aa, dBrackets - StrokeWidth * 0.5);
    // Inner boundary of stroke (Fill region)
    float alphaInner = 1.0 - smoothstep(-aa, aa, dBrackets + StrokeWidth * 0.5);
    
    // Mix Stroke and Fill colors
    // Result is FillColor inside, StrokeColor at edge
    float4 bracketRender = lerp(StrokeColor, BracketColor, alphaInner);
    bracketRender.a *= alphaOuter; // Apply shape coverage

    // 4. Scan Line SDF
    // Map 0..1 Y to frame range
    float lineY = lerp(-frameSize.y * 0.5, frameSize.y * 0.5, ScanLineY);
    float dLine = abs(p.y - lineY) - ScanLineWidth * 0.5;
    // Clip line to frame width
    float dLineClip = max(dLine, abs(p.x) - frameSize.x * 0.5);
    
    float lineAlpha = 1.0 - smoothstep(-aa, aa, dLineClip);
    float4 lineRender = float4(ScanLineColor.rgb, lineAlpha * ScanLineColor.a);

    // 5. Composite
    // Draw Brackets OVER Scan Line
    // Standard Alpha Blending: Out = Src + Dst * (1 - Src.a)
    float3 finalRGB = bracketRender.rgb * bracketRender.a + lineRender.rgb * lineRender.a * (1.0 - bracketRender.a);
    float finalA = bracketRender.a + lineRender.a * (1.0 - bracketRender.a);
    
    // Un-premultiply for straight alpha output
    if (finalA > 1e-6) {
        finalRGB /= finalA;
    }

    outColor = float4(finalRGB, finalA);
}