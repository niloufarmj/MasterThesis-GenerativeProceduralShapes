#ifndef PI
#define PI 3.14159265359
#endif

// --- Helpers ---

// Squared length
float dot2(float2 v) { return dot(v, v); }

// Rounded Box SDF
// p: position, b: half-dimensions, r: corner radius
float sdRoundBox(float2 p, float2 b, float r) {
    float2 q = abs(p) - b + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

// Quadratic Bezier SDF (by Inigo Quilez)
// pos: pixel position, A: start, B: control, C: end
float sdBezier(float2 pos, float2 A, float2 B, float2 C) {
    float2 a = B - A;
    float2 b = A - 2.0 * B + C;
    float2 c = a * 2.0;
    float2 d = A - pos;
    float kk = 1.0 / dot(b, b);
    float kx = kk * dot(a, b);
    float ky = kk * (2.0 * dot(a, a) + dot(d, b)) / 3.0;
    float kz = kk * dot(d, a);
    float res = 0.0;
    float p = ky - kx * kx;
    float p3 = p * p * p;
    float q = kx * (2.0 * kx * kx - 3.0 * ky) + kz;
    float h = q * q + 4.0 * p3;
    if (h >= 0.0) {
        h = sqrt(h);
        float2 x = (float2(h, -h) - q) / 2.0;
        float2 uv = sign(x) * pow(abs(x), 1.0 / 3.0);
        float t = clamp(uv.x + uv.y - kx, 0.0, 1.0);
        res = length(d + (c + b * t) * t);
    } else {
        float z = sqrt(-p);
        float v = acos(q / (p * z * 2.0)) / 3.0;
        float m = cos(v);
        float n = sin(v) * 1.732050808;
        float3 t = clamp(float3(m + m, -n - m, n - m) * z - kx, 0.0, 1.0);
        res = min(dot2(d + (c + b * t.x) * t.x), dot2(d + (c + b * t.y) * t.y));
        res = min(res, dot2(d + (c + b * t.z) * t.z));
        res = sqrt(res);
    }
    return res;
}

// Smooth Min (Soft Union)
float opSmoothUnion(float d1, float d2, float k) {
    float h = clamp(0.5 + 0.5 * (d2 - d1) / max(k, 0.001), 0.0, 1.0);
    return lerp(d2, d1, h) - k * h * (1.0 - h);
}

// --- Main Function ---
// User Request: A cartoon comb with adjustable spine, teeth, gap, and curved handle.
void CartoonComb_float(float2 UV, float Size, float SpineLen, float SpineHeight, float ToothCount, float ToothLen, float ToothGap, float HandleLen, float HandleCurve, float4 FillColor, float4 OutlineColor, float OutlineWidth, out float4 outColor) {
    // PLAN:
    // 1. Center UVs and scale by Size.
    // 2. Compute SDF for the Spine (Rounded Box).
    // 3. Compute SDF for Teeth using domain repetition (limited to SpineLen).
    // 4. Compute SDF for Handle using a Quadratic Bezier curve.
    // 5. Blend all shapes using smooth union for a cartoon plastic look.
    // 6. Apply outline and fill colors with anti-aliasing.

    // 1. Setup Coordinates
    float2 p = (UV - 0.5) * 2.0;
    p /= max(Size, 0.001);
    
    // 2. Spine SDF
    // Centered at (0,0), extending along X axis
    float2 spineDim = float2(SpineLen * 0.5, SpineHeight * 0.5);
    float dSpine = sdRoundBox(p, spineDim, SpineHeight * 0.25);
    
    // 3. Teeth SDF
    // Calculate spacing
    float tCount = max(1.0, floor(ToothCount));
    float tSpace = SpineLen / tCount;
    float tWidth = (tSpace * (1.0 - clamp(ToothGap, 0.0, 0.9))) * 0.5;
    float tHeight = ToothLen * 0.5;
    
    // Domain Repetition Logic for Teeth
    // Shift X so the row is centered on the spine
    float xShift = p.x + SpineLen * 0.5 - tSpace * 0.5;
    float id = round(xShift / tSpace);
    id = clamp(id, 0.0, tCount - 1.0);
    
    // Calculate center of the specific tooth for this ID
    float centerX = (id * tSpace) - SpineLen * 0.5 + tSpace * 0.5;
    // Teeth attach to bottom of spine (y = -SpineHeight/2)
    float2 toothCenter = float2(centerX, -SpineHeight * 0.5);
    
    // Local tooth coordinates
    float2 pTooth = p - toothCenter;
    // Offset Y so the box hangs downwards from the attachment point
    pTooth.y += tHeight; 
    
    // Tooth shape (Rounded Box with full rounding at bottom)
    float dTeeth = sdRoundBox(pTooth, float2(tWidth, tHeight), tWidth);
    
    // 4. Handle SDF
    // Handle attaches to the right side of the spine (x = SpineLen/2)
    float2 hStart = float2(SpineLen * 0.5, 0.0);
    // Control point extends out to ensure smooth tangency
    float2 hControl = hStart + float2(HandleLen * 0.4, 0.0);
    // End point curves down (or up if negative)
    float2 hEnd = hStart + float2(HandleLen, -HandleCurve);
    
    // Bezier curve distance minus thickness (radius)
    float handleThickness = SpineHeight * 0.45; // Slightly thinner than spine
    float dHandle = sdBezier(p, hStart, hControl, hEnd) - handleThickness;
    
    // 5. Composition
    // Blend Spine and Teeth
    float smoothFactor = 0.02;
    float dShape = opSmoothUnion(dSpine, dTeeth, smoothFactor);
    // Blend Handle
    dShape = opSmoothUnion(dShape, dHandle, smoothFactor);
    
    // 6. Rendering
    float aa = fwidth(dShape);
    // Outline mask
    float outlineDist = abs(dShape) - OutlineWidth;
    float outlineAlpha = 1.0 - smoothstep(-aa, aa, outlineDist);
    
    // Fill mask
    float fillAlpha = 1.0 - smoothstep(-aa, aa, dShape);
    
    // Composite
    // Start with transparent
    float4 result = float4(0,0,0,0);
    
    // Draw Outline
    result = lerp(result, OutlineColor, outlineAlpha);
    
    // Draw Fill over Outline (but keep outline at edges)
    // Actually standard cartoon rendering is Fill inside, Outline on edge
    // Efficient way: lerp OutlineColor to FillColor based on fillAlpha
    // However, since dShape < 0 is fill, we need to be careful with the outline expanding OUTWARDS
    // The outlineDist logic creates a band centered on the edge
    // Let's do strict compositing:
    
    // Base Fill
    float4 fill = float4(FillColor.rgb * fillAlpha, fillAlpha);
    
    // Outline area (stroke)
    float strokeAlpha = outlineAlpha - fillAlpha; 
    // Fix: smoothstep produces gradients, straight subtraction might be messy.
    // Better: Render solid shape with outline color, then render inner shape with fill color.
    
    // Outer Shape (Outline Color)
    float outerEdge = 1.0 - smoothstep(-aa, aa, dShape - OutlineWidth);
    float4 outerLayer = float4(OutlineColor.rgb * outerEdge, outerEdge);
    
    // Inner Shape (Fill Color)
    float innerEdge = 1.0 - smoothstep(-aa, aa, dShape);
    float4 innerLayer = float4(FillColor.rgb * innerEdge, innerEdge);
    
    // Mix: inner over outer
    float3 finalRGB = innerLayer.rgb + outerLayer.rgb * (1.0 - innerLayer.a);
    float finalA = innerLayer.a + outerLayer.a * (1.0 - innerLayer.a);
    
    outColor = float4(finalRGB, finalA);
}

// ------------------------------------------------------------------------
//  Visual Result (High-level, parameter-invariant description)
// ------------------------------------------------------------------------
//  This function generates a **stylized 2D cartoon comb** using
//  Signed Distance Functions (SDFs).
//
//  The visual result is composed of:
//  - A horizontal rounded rectangular spine.
//  - A row of downward-projecting rounded teeth with adjustable count,
//    length, and gap spacing.
//  - A curved handle extending smoothly from one end of the spine.
//
//  The components are blended using a smooth union to create a single,
//  unified silhouette resembling a plastic object. A consistent outline
//  surrounds the entire shape. All dimensions and colors are fully adjustable.
//
//  The output is an anti-aliased RGBA color suitable for grooming icons,
//  bathroom props, and salon themes.
// ------------------------------------------------------------------------