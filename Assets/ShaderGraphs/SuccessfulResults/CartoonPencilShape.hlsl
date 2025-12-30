#ifndef PI
#define PI 3.14159265359
#endif

// --- Helper Functions ---

// 2D Rotation
float2 rotatePencil(float2 p, float angle) {
    float c = cos(angle);
    float s = sin(angle);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

// SDF Box (Axis aligned)
float sdBox(float2 p, float2 b) {
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// SDF Rounded Box
float sdRoundedBox(float2 p, float2 b, float r) {
    float2 q = abs(p) - b + r;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

// SDF Isosceles Triangle (Pointing down)
// Base width: w*2, Height: h
float sdTriangleDown(float2 p, float w, float h) {
    p.x = abs(p.x);
    float2 a = float2(w, 0.0);
    float2 b = float2(0.0, -h);
    
    float2 pa = p - a;
    float2 ba = b - a;
    
    // Clamp for the segment
    float t = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    float2 d = pa - ba * t;
    
    // Signed distance (basic)
    // Correct sign logic for inside/outside
    float dist = length(d);
    
    // Determine sign using cross product z-component
    float crossZ = (p.x - b.x) * (a.y - b.y) - (p.y - b.y) * (a.x - b.x);
    // Also check if above base (y > 0)
    if (p.y > 0.0) dist = length(p - float2(clamp(p.x, 0.0, w), 0.0));
    else if (crossZ < 0.0) dist = -dist;
    
    return dist;
}

// Main Shape Function
// User Request: A cartoon pencil with adjustable body, eraser, ferrule, tip, stripes, rotation, and colors.
void CartoonPencilShape_float(float2 UV, float Size, float Rotation, 
                              float BodyWidth, float BodyLength, float4 BodyColor, 
                              float EraserLength, float4 EraserColor, 
                              float FerruleLength, float4 FerruleColor, 
                              float TipLength, float4 WoodColor, float4 LeadColor,
                              float StripeCount, float4 StripeColor,
                              float OutlineWidth, float4 OutlineColor,
                              out float4 outColor) 
{
    // 1. Setup Coordinates
    float2 center = float2(0.5, 0.5);
    float2 p = (UV - center) * 2.0; // Map to -1..1
    p /= max(Size, 0.001);          // Scale
    p = rotatePencil(p, Rotation);  // Rotate

    // Anti-aliasing factor based on derivative
    float aa = fwidth(p.x) * 1.5;
    // Fallback if fwidth is zero (e.g. non-fragment shader context)
    if (aa == 0.0) aa = 0.01;

    // 2. Define Part Dimensions
    float w = BodyWidth * 0.5;      // Half-width
    float h = BodyLength * 0.5;     // Half-height of body
    
    // 3. Compute SDFs for each part
    
    // -- Body (Centered Rectangle) --
    float dBody = sdBox(p, float2(w, h));

    // -- Ferrule (Metal Band above body) --
    // Positioned at y = h + ferruleH/2
    float yFerrule = h + FerruleLength * 0.5;
    float dFerrule = sdBox(p - float2(0.0, yFerrule), float2(w * 1.05, FerruleLength * 0.5));

    // -- Eraser (Rounded top above ferrule) --
    // Positioned at y = h + FerruleLength + EraserLength/2
    float yEraser = h + FerruleLength + EraserLength * 0.5;
    // Use rounded box, roundness = half width for semi-circle top look
    float dEraser = sdRoundedBox(p - float2(0.0, yEraser), float2(w * 0.9, EraserLength * 0.5), w * 0.4);

    // -- Tip (Cone/Triangle below body) --
    // Positioned at y = -h
    // We shift p up by h so the triangle base is at 0 (relative to tip start)
    float2 pTip = p - float2(0.0, -h);
    float dTip = sdTriangleDown(pTip, w, TipLength);

    // 4. Combine Shapes
    // Union of all parts
    float dShape = min(min(dBody, dFerrule), min(dEraser, dTip));
    
    // 5. Compute Fill Colors
    float4 fillColor = float4(0,0,0,0);

    // Priority mixing based on SDFs
    // We check which part we are inside. 
    // Since parts are mostly disjoint, we can check d < aa.
    // We use smooth blending for edges between colors.

    // Base Body Fill with Stripes
    float bodyMask = smoothstep(aa, -aa, dBody);
    
    // Stripe Pattern (Vertical stripes on body)
    // Map x from -w to w -> 0 to 1
    float xNorm = (p.x + w) / (w * 2.0);
    // Sine wave stripes
    float stripes = smoothstep(0.4, 0.6, 0.5 + 0.5 * sin(xNorm * PI * StripeCount * 2.0));
    float4 bodyFinal = lerp(BodyColor, StripeColor, stripes * 0.5); // 0.5 intensity
    
    fillColor = lerp(fillColor, bodyFinal, bodyMask);

    // Ferrule Fill
    float ferruleMask = smoothstep(aa, -aa, dFerrule);
    fillColor = lerp(fillColor, FerruleColor, ferruleMask);

    // Eraser Fill
    float eraserMask = smoothstep(aa, -aa, dEraser);
    fillColor = lerp(fillColor, EraserColor, eraserMask);

    // Tip Fill (Wood + Lead)
    float tipMask = smoothstep(aa, -aa, dTip);
    // Determine Lead vs Wood area based on Y coordinate in Tip space
    // Lead is the bottom 25% of the tip
    float leadThreshold = -TipLength * 0.75;
    float leadMask = smoothstep(leadThreshold + aa, leadThreshold - aa, pTip.y);
    float4 tipFinal = lerp(WoodColor, LeadColor, leadMask);
    
    fillColor = lerp(fillColor, tipFinal, tipMask);

    // 6. Compute Outline
    // Outline is drawn on the boundary of the combined shape
    float outlineEdge = smoothstep(OutlineWidth + aa, OutlineWidth - aa, abs(dShape));
    // We want the outline to cover the edge, so we mix it over the fill
    // But strictly speaking, standard cartoon outline is often outside or centered.
    // Here we composite: Fill is strictly inside, Outline is the border.
    
    // Recalculate masks for proper composition
    float shapeAlpha = smoothstep(aa, -aa, dShape);
    float borderAlpha = smoothstep(OutlineWidth, OutlineWidth - aa, abs(dShape));
    
    // Final Composition
    // Start with transparent
    float4 result = float4(0,0,0,0);
    
    // Apply Outline
    result = lerp(result, OutlineColor, borderAlpha);
    
    // Apply Fill (Inside the outline)
    // To ensure clean rendering, fill is applied where dShape < 0
    // We can just layer Fill over the background, then Outline on top of the edge.
    
    // A solid shape mask (including outline width)
    float fullShapeMask = smoothstep(OutlineWidth + aa, OutlineWidth - aa, dShape);
    // The fill mask (excluding outline width if we want inner stroke, but standard is center stroke)
    // Let's assume OutlineWidth is 'centered' on the zero-crossing.
    
    // Better logic: 
    // If distance < 0 (inside), use fill color.
    // If abs(distance) < OutlineWidth, use outline color.
    
    float isOutline = step(abs(dShape), OutlineWidth);
    float isInside = step(dShape, 0.0);
    
    // Smooth version
    float outlineFactor = smoothstep(OutlineWidth + aa, OutlineWidth - aa, abs(dShape));
    float insideFactor = smoothstep(aa, -aa, dShape);

    // Mix Fill and Outline
    // Place fill
    float4 combinedColor = fillColor;
    // Overlay outline
    combinedColor = lerp(combinedColor, OutlineColor, outlineFactor);
    
    // Output alpha is determined by the total shape coverage
    float totalAlpha = smoothstep(OutlineWidth + aa, OutlineWidth - aa, dShape);
    
    outColor = float4(combinedColor.rgb * totalAlpha, totalAlpha);
}