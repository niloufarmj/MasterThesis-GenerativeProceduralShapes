#ifndef PI
#define PI 3.14159265359
#endif

// --- Helpers ---

// Rotate a 2D vector by an angle in radians
float2 rotate(float2 p, float angle) {
    float c = cos(angle);
    float s = sin(angle);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

// Signed distance to a box
float sdBox(float2 p, float2 b) {
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// Signed distance to a circle
float sdCircle(float2 p, float r) {
    return length(p) - r;
}

// Smooth min for organic joining of shapes
float smin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return lerp(b, a, h) - k * h * (1.0 - h);
}

// Approximate signed distance to an ellipse
// Using gradient-based approximation for better constant-width strokes
float sdEllipse(float2 p, float2 r) {
    float k0 = length(p / r);
    float k1 = length(p / (r * r));
    return (k0 - 1.0) * k0 / k1;
}

// --- Main Function ---
// Plan:
// 1. Center and rotate UV coordinates.
// 2. Define Meat SDF (ellipse).
// 3. Define Bone SDF (box shaft + circle joints) attached to the bottom of the meat.
// 4. Combine Meat and Bone with a smooth union for the outline, but keep IDs for coloring.
// 5. Define Highlight SDF inside the meat.
// 6. Compute fill colors and apply outlines using smoothstep.

void ChickenLegShape_float(float2 UV, float2 Center, float Rotation, float2 MeatSize, float4 MeatColor, float BoneLength, float JointProminence, float4 BoneColor, float HighlightSize, float StrokeWidth, float4 StrokeColor, out float4 outColor) {
    // 1. Coordinate Setup
    float2 p = UV - Center;
    p = rotate(p, Rotation);
    
    // 2. Meat Section (Ellipse)
    // Shift meat slightly up so the whole leg feels centered
    float2 meatPos = p - float2(0.0, BoneLength * 0.2);
    // Ensure safe dimensions
    float2 safeMeatSize = max(MeatSize, 0.001);
    float dMeat = sdEllipse(meatPos, safeMeatSize);
    
    // 3. Bone Handle
    // Bone attaches to bottom of meat. 
    // Meat bottom is roughly at -safeMeatSize.y relative to meatPos.
    // Let's position the bone shaft sticking down from there.
    float shaftWidth = max(0.01, JointProminence * 0.4);
    float shaftLen = max(0.0, BoneLength);
    
    // Shaft box position (center of box)
    // It starts slightly inside the meat (-0.2 inset) and goes down
    float2 shaftCenter = float2(0.0, -safeMeatSize.y + BoneLength * 0.2 - shaftLen * 0.5);
    // Add relative to meatPos shift
    shaftCenter += float2(0.0, BoneLength * 0.2); 
    
    float dShaft = sdBox(p - shaftCenter, float2(shaftWidth, shaftLen * 0.5));
    
    // Joint (Condyles) at the bottom of the shaft
    float2 jointBase = shaftCenter - float2(0.0, shaftLen * 0.5);
    float jointR = max(0.01, JointProminence);
    float dJointL = sdCircle(p - (jointBase + float2(-jointR * 0.8, 0.0)), jointR);
    float dJointR = sdCircle(p - (jointBase + float2(jointR * 0.8, 0.0)), jointR);
    float dJoints = smin(dJointL, dJointR, 0.01);
    
    // Combine Shaft and Joints smoothly
    float dBone = smin(dShaft, dJoints, 0.02);
    
    // 4. Highlight (Reflection)
    // Positioned top-left on the meat
    float2 highOffset = float2(-safeMeatSize.x * 0.5, safeMeatSize.y * 0.5);
    float highRad = min(safeMeatSize.x, safeMeatSize.y) * HighlightSize;
    float dHighlight = sdEllipse(meatPos - highOffset, float2(highRad, highRad * 0.6));
    
    // 5. Composition & Rendering
    // Combine meat and bone for the global silhouette/outline
    // We use min() here because we want a distinct boundary, or smin for cartoon glue
    // Standard cartoon usually has distinct parts, but let's smooth slightly
    float dTotal = min(dMeat, dBone);
    
    // Anti-aliasing width
    float aa = fwidth(dTotal) * 1.5;
    // Fallback for preview windows
    if (aa < 0.0001) aa = 0.001;

    // Fill Mask (Main Shape)
    float fillMask = 1.0 - smoothstep(0.0, aa, dTotal);
    
    // Outline Mask (Band around the edge)
    // Stroke is drawn centered on the SDF zero-crossing or outside
    // Here we draw it centered on the edge
    float strokeMask = 1.0 - smoothstep(0.0, aa, abs(dTotal) - StrokeWidth * 0.5);
    
    // Determine Fill Color (Meat vs Bone)
    // We check which SDF is closer. If Meat is closer (or overlapping), it wins.
    // Bias dMeat slightly negative to ensure it draws 'over' the bone where they intersect.
    float4 fillColor = (dMeat < dBone + 0.001) ? MeatColor : BoneColor;
    
    // Apply Highlight (Only on Meat)
    if (dMeat < dBone + 0.001) {
        float highMask = 1.0 - smoothstep(0.0, aa, dHighlight);
        // Highlight is usually white with some transparency
        float4 highColor = float4(1.0, 1.0, 1.0, 0.8);
        // Composite highlight over fill
        fillColor.rgb = lerp(fillColor.rgb, highColor.rgb, highMask * highColor.a);
    }
    
    // Composite Outline over Fill
    // Standard source-over blending: Outline is on top
    float4 finalColor = fillColor;
    finalColor.rgb = lerp(finalColor.rgb, StrokeColor.rgb, strokeMask * StrokeColor.a);
    // Alpha is Union of fill and stroke (approximate for simple SDF)
    // Actually, max(fillMask, strokeMask) covers the shape area
    float shapeAlpha = max(fillMask, strokeMask);
    
    // Final Output
    outColor = float4(finalColor.rgb * shapeAlpha, shapeAlpha);
}