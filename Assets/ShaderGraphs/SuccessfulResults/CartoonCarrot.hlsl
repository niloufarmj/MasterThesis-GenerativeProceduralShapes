// PLAN:
// 1. Define Helper SDFs: sdRoundCone (vertical) and rotation helper.
// 2. Center UVs: Compute vector p relative to Center.
// 3. Carrot Root (Body):
//    - Apply parabolic curvature to p.x based on p.y (anchored at top y=0).
//    - Use sdRoundCone inverted (y flipped) to draw body from 0 to -Length.
// 4. Leaves:
//    - Loop through LeafCount.
//    - Rotate p around (0,0) for each leaf based on Spread.
//    - Use sdRoundCone upright from 0 to LeafSize.
//    - Combine leaves with min().
// 5. Combination:
//    - Smooth Union of Body and Leaves SDFs.
// 6. Notch Pattern:
//    - Sine wave on the curved body Y coordinate.
//    - Mask to only appear on the body surface.
// 7. Coloring:
//    - Mix Leaf/Body color based on SDF proximity.
//    - Apply notch color bands.
//    - Apply Stroke outline.
// 8. Output final color with AA.

#ifndef PI
#define PI 3.14159265359
#endif

// Helper: Rotate vector p by angle a
float2 rotate(float2 p, float a) {
    float c = cos(a);
    float s = sin(a);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

// Helper: Signed Distance to a Round Cone (Vertical)
// Starts at (0,0) with radius r1, ends at (0,h) with radius r2
float sdRoundCone(float2 p, float r1, float r2, float h) {
    float2 q = float2(length(p.x), p.y);
    // Prevent div by zero
    h = max(h, 0.001);
    float b = (r1 - r2) / h;
    float a = sqrt(1.0 - b * b);
    float k = dot(q, float2(-b, a));
    if (k < 0.0) return length(q) - r1;
    if (k > a * h) return length(q - float2(0.0, h)) - r2;
    return dot(q, float2(a, b)) - r1;
}

void CartoonCarrot_float(float2 UV, float2 Center, float Length, float TopWidth, float Curvature, float LeafCount, float LeafSize, float LeafSpread, float NotchSpacing, float NotchThickness, float4 BodyColor, float4 LeafColor, float4 StrokeColor, float StrokeWidth, out float4 outColor) {
    // 1. Setup Coordinates
    // Translate so (0,0) is at the 'Center' parameter
    // This point will be the pivot where leaves meet the root
    float2 p = UV - Center;
    
    // 2. Carrot Body (Root)
    // Bending: Anchor at y=0. Bend x as y goes down (negative).
    // Formula: x' = x - k * y^2
    float2 pBody = p;
    pBody.x -= Curvature * p.y * p.y * 2.0;
    
    // Root Dimensions
    float rTop = max(TopWidth * 0.5, 0.01);
    float rTip = 0.01; // Taper to a point
    float bodyLen = max(Length, 0.01);
    
    // Draw Cone: We want it to go from (0,0) down to (0, -bodyLen).
    // sdRoundCone goes (0,0) -> (0,h). So we pass -pBody.y as the height axis.
    float dBody = sdRoundCone(float2(pBody.x, -pBody.y), rTop, rTip, bodyLen);
    
    // 3. Leaves
    float dLeaves = 1000.0;
    int count = clamp((int)LeafCount, 0, 12);
    float lSize = max(LeafSize, 0.01);
    float lBase = lSize * 0.15; // Width of leaf base
    
    for(int i = 0; i < count; i++) {
        // Calculate angle: map i to [-Spread/2, Spread/2]
        float t = (count > 1) ? (float(i) / float(count - 1)) - 0.5 : 0.0;
        float ang = t * LeafSpread;
        
        // Rotate leaf space around pivot (0,0)
        float2 pLeaf = rotate(p, -ang);
        
        // Leaf SDF: Upright cone from (0,0) to (0, lSize)
        float dL = sdRoundCone(pLeaf, lBase, 0.0, lSize);
        dLeaves = min(dLeaves, dL);
    }
    
    // 4. Combine Shapes
    // Use smooth min to blend the connection slightly
    float blendK = 0.01;
    float hBlend = clamp(0.5 + 0.5 * (dLeaves - dBody) / blendK, 0.0, 1.0);
    float dShape = lerp(dLeaves, dBody, hBlend) - blendK * hBlend * (1.0 - hBlend);
    
    // 5. Notch Pattern
    // Use bent Y coordinate so notches follow the curve
    // Only show notches on the body (y < 0 basically, masked by dBody)
    float notchSignal = sin(pBody.y * NotchSpacing);
    // Create sharp bands
    float notchMask = smoothstep(1.0 - NotchThickness, 1.0, abs(notchSignal));
    // Restrict to inside the body, slightly inset from edge
    float bodyInset = smoothstep(-0.01, -0.04, dBody);
    // Exclude top area near leaves
    float topMask = smoothstep(-0.05, -0.15, pBody.y); // Fade out near top
    float notchVis = notchMask * bodyInset * topMask;
    
    // 6. Coloring & Anti-Aliasing
    float aa = fwidth(dShape);
    
    // Determine fill color (Body vs Leaf)
    // Soft transition based on which SDF is closer
    float bodyFactor = smoothstep(-0.01, 0.01, dLeaves - dBody);
    float4 fillColor = lerp(LeafColor, BodyColor, bodyFactor);
    
    // Apply notches (darken body color towards stroke color)
    float4 notchCol = lerp(fillColor, StrokeColor, 0.7);
    fillColor = lerp(fillColor, notchCol, notchVis * bodyFactor);
    
    // Calculate masks
    // Stroke mask: 1.0 at edge, 0.0 elsewhere
    float strokeAlpha = 1.0 - smoothstep(StrokeWidth, StrokeWidth + aa, abs(dShape));
    // Fill mask: 1.0 inside, 0.0 outside
    float fillAlpha = 1.0 - smoothstep(0.0, aa, dShape);
    
    // Composite: Stroke over Fill
    // If we are in the stroke band, use StrokeColor. Else use FillColor.
    // Since strokeAlpha sits on top of the edge, we blend it over the fill.
    
    // Visual composition:
    // inside shape (d < 0): fill
    // near edge (abs(d) < w): stroke
    // We want stroke to fully cover the edge. 
    
    // Mix fill and stroke
    float3 finalRGB = lerp(fillColor.rgb, StrokeColor.rgb, strokeAlpha);
    float finalA = max(fillAlpha, strokeAlpha);
    
    outColor = float4(finalRGB * finalA, finalA);
}