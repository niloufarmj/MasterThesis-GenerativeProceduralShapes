#ifndef PI
#define PI 3.14159265359
#endif

// Helper: Straight-alpha "src over dst" blending
float4 biscuit_over(float4 src, float4 dst) {
    float a = src.a + dst.a * (1.0 - src.a);
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-8);
    return float4(c, a);
}

// PLAN:
// 1) Transform UV to centered, rotated coordinate space.
// 2) Calculate Body SDF: Circle with polar cosine perturbation (scalloped edge).
//    Apply gradient correction to ensure uniform stroke thickness on wavy lobes.
// 3) Calculate Holes SDF: Single ring radial repetition logic to find closest hole.
// 4) Combine SDFs using CSG Subtraction (max(Body, -Holes)).
// 5) Render solid fill and outline stroke with analytic anti-aliasing (fwidth).

void CartoonBiscuitShape_float(float2 UV, float2 Center, float Rotation, float Radius, float LobeCount, float LobeDepth, float HoleCount, float HoleSize, float HoleDist, float4 FillColor, float4 StrokeColor, float StrokeWidth, out float4 outColor) {
    // 1) Center and Rotate
    float2 p = UV - Center;
    float c = cos(Rotation);
    float s = sin(Rotation);
    p = float2(c * p.x + s * p.y, -s * p.x + c * p.y);
    
    // 2) Body SDF (Scalloped Circle)
    float r = length(p);
    float angle = atan2(p.y, p.x);
    
    // Wavy edge: Radius varies with angle
    // Formula: dist = r - (BaseRadius + Amplitude * cos(Frequency * angle))
    float lobeWave = cos(LobeCount * angle);
    float dBody = r - (Radius + LobeDepth * lobeWave);
    
    // Gradient correction for the wavy field to maintain uniform stroke width
    // The gradient magnitude of the polar function is approx sqrt(1 + (derivative_angular/r)^2)
    float k = (LobeDepth * LobeCount) / max(r, 0.001);
    float sinWave = sin(LobeCount * angle);
    float gradLen = sqrt(1.0 + k * k * sinWave * sinWave);
    dBody /= gradLen;
    
    // 3) Holes SDF (Radial Ring)
    float dHoles = 1e9; // Default to 'far away' if no holes
    if (HoleCount > 0.5) {
        // Calculate angular sector for the closest hole
        float sectorStep = 2.0 * PI / max(HoleCount, 1.0);
        float sectorId = round(angle / sectorStep);
        float holeAngle = sectorId * sectorStep;
        
        // Position of the specific hole center for this sector
        float2 holeCenter = float2(cos(holeAngle), sin(holeAngle)) * HoleDist;
        dHoles = length(p - holeCenter) - HoleSize;
    }
    
    // 4) Combine: Biscuit Body minus Holes
    // SDF Subtraction: Intersection of Body and NOT Hole -> max(dBody, -dHoles)
    float dFinal = max(dBody, -dHoles);
    
    // 5) Rendering / Anti-aliasing
    float aa = fwidth(dFinal);
    aa = max(aa, 0.001); // Safety for previews
    
    // Fill: Inside the shape (dFinal < 0)
    float fillAlpha = 1.0 - smoothstep(-aa * 0.5, aa * 0.5, dFinal);
    float4 fillLayer = float4(FillColor.rgb, saturate(FillColor.a) * fillAlpha);
    
    // Stroke: Centered on the zero-crossing edge
    float halfStroke = max(StrokeWidth, 0.0) * 0.5;
    float dStroke = abs(dFinal) - halfStroke;
    float strokeAlpha = 1.0 - smoothstep(-aa * 0.5, aa * 0.5, dStroke);
    float4 strokeLayer = float4(StrokeColor.rgb, saturate(StrokeColor.a) * strokeAlpha);
    
    // Composite Stroke OVER Fill
    outColor = biscuit_over(strokeLayer, fillLayer);
}