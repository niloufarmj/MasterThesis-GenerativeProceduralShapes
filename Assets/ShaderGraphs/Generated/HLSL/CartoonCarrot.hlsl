/* 
  Cartoon Carrot with adjustable size, body taper, tip curvature, 
  leaf cluster, surface notches, and consistent outline.
*/

#ifndef PI
#define PI 3.14159265359
#endif

// --- Helper Functions ---

// Rotate a 2D vector by an angle (radians)
float2 rotate(float2 p, float a) {
    float c = cos(a);
    float s = sin(a);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

// Signed Distance to an Uneven Capsule (Tapered rounded cylinder)
// p: sampling point (relative to base)
// r1: radius at bottom (y=0)
// r2: radius at top (y=h)
// h: height of the vertical segment
float sdUnevenCapsule(float2 p, float r1, float r2, float h) {
    p.x = abs(p.x);
    float b = (r1 - r2) / h;
    float a = sqrt(1.0 - b * b);
    float k = dot(p, float2(-b, a));
    if (k < 0.0) return length(p) - r1;
    if (k > a * h) return length(p - float2(0.0, h)) - r2;
    return dot(p, float2(a, b)) - r1;
}

// Signed Distance to a Vesica (Lens/Leaf shape)
// w: total width
// l: total length
// Shape is centered at (0,0) and oriented vertically.
float sdVesica(float2 p, float w, float l) {
    // Ensure safe values
    w = max(w, 0.001);
    l = max(l, 0.001);
    
    // Calculate radius and offset for the intersecting circles
    float r = (l * l + w * w) / (4.0 * w);
    float d = r - w * 0.5;
    
    p = abs(p);
    float b = sqrt(max(r * r - d * d, 0.0)); // half length
    
    // SDF Logic
    return ((p.y - b) * d > p.x * b) ? length(p - float2(0.0, b))
                                     : length(p - float2(-d, 0.0)) - r;
}

// --- Main Shader Function ---
void CartoonCarrot_float(float2 UV, float Size, float BodyLength, float BodyTopWidth, float BodyTipRadius, float LeafCount, float LeafLength, float LeafWidth, float LeafSpread, float NotchSpacing, float NotchThickness, float OutlineWidth, float4 BodyColor, float4 LeafColor, float4 StrokeColor, out float4 outColor) {
    // PLAN:
    // 1) Remap UV to centered coordinates and scale.
    // 2) Construct Body SDF (Uneven Capsule) oriented vertically.
    // 3) Construct Leaf Cluster SDF by rotating Vesica shapes from the body top.
    // 4) Combine Body and Leaves into a single union SDF for the outline.
    // 5) Generate Notch markings mask using sine pattern on body Y coords.
    // 6) Resolve colors: Determine if pixel is Body or Leaf, apply notches, then add outline.
    
    // 1. Center and Scale
    // Center UV at (0.5, 0.5) and apply inverse scale
    float2 p = (UV - 0.5) * (2.0 / max(Size, 0.001));
    
    // 2. Body SDF construction
    // The body is an uneven capsule defined from y=0 (Tip) to y=Height (Top).
    // We visually center the carrot by offsetting p.
    float h = max(BodyLength, 0.01);
    float rTop = max(BodyTopWidth, 0.0);
    float rTip = max(BodyTipRadius, 0.0);
    
    // Map screen space to SDF space: 
    // Shift y so that the visual center of the carrot aligns with screen center.
    // Placing the Tip at local y=0 means shifting p up by h/2 roughly.
    float2 pBody = p;
    pBody.y += h * 0.5;
    
    float dBody = sdUnevenCapsule(pBody, rTip, rTop, h);
    
    // 3. Leaf Cluster SDF construction
    // Leaves grow from the top of the body (y = h in pBody space).
    float2 leafOrigin = pBody - float2(0.0, h);
    float dLeaves = 1000.0;
    int count = max(1, (int)LeafCount);
    float spread = LeafSpread * 0.5;
    
    // Loop to create fan of leaves
    for (int i = 0; i < count; i++) {
        // Calculate angle for this leaf
        float t = (count > 1) ? (float(i) / float(count - 1)) : 0.5;
        float ang = lerp(-spread, spread, t);
        
        // Rotate position relative to leaf origin
        float2 pL = rotate(leafOrigin, ang);
        
        // Offset y so the leaf base sits at the origin
        // The vesica function centers the shape, so we shift by half length.
        pL.y -= LeafLength * 0.5;
        
        float dL = sdVesica(pL, LeafWidth, LeafLength);
        dLeaves = min(dLeaves, dL);
    }
    
    // 4. Combine Shapes
    // Smooth union could be used, but standard union is cleaner for cartoon style.
    float dUnion = min(dBody, dLeaves);
    
    // Anti-aliasing factor
    float aa = fwidth(dUnion);
    
    // 5. Notch Markings
    // Create horizontal bands along the body height
    // Frequency is inverse of spacing
    float notchFreq = 1.0 / max(NotchSpacing, 0.01);
    float notchPattern = abs(frac(pBody.y * notchFreq) - 0.5);
    // Threshold for notch thickness (dark bands)
    // We use smoothstep for soft edges on the markings
    float isNotch = 1.0 - smoothstep(NotchThickness, NotchThickness + 0.05, notchPattern);
    
    // 6. Color Composition
    // Determine base fill color (Body vs Leaf)
    // If body SDF is closer than leaf SDF, render body color.
    float bodyMask = step(dBody, dLeaves);
    
    // Apply notch color to body (darken body color)
    // Markings are only visible on the body
    float4 modifiedBodyColor = lerp(BodyColor, BodyColor * 0.7, isNotch);
    
    float4 fillColor = lerp(LeafColor, modifiedBodyColor, bodyMask);
    
    // Calculate Shape Alpha (Opacity)
    float alpha = 1.0 - smoothstep(-aa, aa, dUnion);
    
    // Calculate Outline
    // Outline appears where distance is within OutlineWidth
    float outlineAlpha = 1.0 - smoothstep(OutlineWidth - aa, OutlineWidth + aa, abs(dUnion));
    
    // Composite Outline over Fill
    float4 finalRGB = lerp(fillColor, StrokeColor, outlineAlpha);
    
    // Final Output with transparency
    outColor = float4(finalRGB.rgb * alpha, alpha);
}