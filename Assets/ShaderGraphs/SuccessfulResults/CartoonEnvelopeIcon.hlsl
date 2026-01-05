#ifndef PI
#define PI 3.14159265359
#endif

// SDF for a box with rounded corners
// p: point, b: half-extents, r: radius
float sdRoundedBox_Env(float2 p, float2 b, float r) {
    float2 q = abs(p) - b + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

// SDF for a line segment
// p: point, a: start, b: end
float sdSegment_Env(float2 p, float2 a, float2 b) {
    float2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}

// SDF for a triangle
float sdTriangle_Env(float2 p, float2 p0, float2 p1, float2 p2) {
    float2 e0 = p1 - p0, e1 = p2 - p1, e2 = p0 - p2;
    float2 v0 = p - p0, v1 = p - p1, v2 = p - p2;
    float2 pq0 = v0 - e0 * clamp(dot(v0, e0) / dot(e0, e0), 0.0, 1.0);
    float2 pq1 = v1 - e1 * clamp(dot(v1, e1) / dot(e1, e1), 0.0, 1.0);
    float2 pq2 = v2 - e2 * clamp(dot(v2, e2) / dot(e2, e2), 0.0, 1.0);
    float s = sign(e0.x * e2.y - e0.y * e2.x);
    float2 d = min(min(float2(dot(pq0, pq0), s * (v0.x * e0.y - v0.y * e0.x)),
                       float2(dot(pq1, pq1), s * (v1.x * e1.y - v1.y * e1.x))),
                       float2(dot(pq2, pq2), s * (v2.x * e2.y - v2.y * e2.x)));
    return -sqrt(d.x) * sign(d.y);
}

// Compositing helper: blends src over dst (Standard Premultiplied Alpha Blending)
// dst: current canvas color (premultiplied)
// src: new layer color (premultiplied)
float4 composite_Env(float4 dst, float4 src) {
    return src + dst * (1.0 - src.a);
}

void CartoonEnvelopeIcon_float(float2 UV, float Width, float Height, float CornerRadius, float FlapHeight, float StrokeThickness, float4 FillColor, float4 StrokeColor, out float4 outColor) {
    // PLAN:
    // 1. Setup centered coordinates and dimensions.
    // 2. Compute SDFs for Body (rounded box), Pocket Creases (segments), and Top Flap (triangle).
    // 3. Compute alpha masks for fills and strokes using smoothstep.
    // 4. Composite layers back-to-front: Body Fill -> Creases -> Body Stroke -> Flap Fill -> Flap Stroke.
    // 5. Output final accumulated color.

    float2 p = UV - 0.5;
    float2 b = float2(Width, Height) * 0.5;
    float r = clamp(CornerRadius, 0.0, min(b.x, b.y));
    float sw = max(StrokeThickness, 0.0001);
    float halfSw = sw * 0.5;

    // AA Calculation
    float aa = length(fwidth(p));
    if (aa < 0.0001) aa = 0.002; // Fallback if fwidth fails

    // --- 1. Envelope Body ---
    float dBody = sdRoundedBox_Env(p, b, r);
    // Fill Mask (d < 0)
    float maskBodyFill = 1.0 - smoothstep(-aa, aa, dBody);
    // Stroke Mask (abs(d) < thickness/2)
    float maskBodyStroke = 1.0 - smoothstep(halfSw - aa, halfSw + aa, abs(dBody));

    // --- 2. Pocket Creases ---
    // Lines from bottom corners to center. 
    // Note: The pocket forms the "V" shape at the bottom.
    float2 vBL = float2(-b.x, -b.y);
    float2 vBR = float2(b.x, -b.y);
    float2 vCenter = float2(0.0, 0.0);
    
    float dCrease = min(sdSegment_Env(p, vBL, vCenter), sdSegment_Env(p, vBR, vCenter));
    // Clip creases to be inside the body fill area
    float maskCreases = (1.0 - smoothstep(halfSw - aa, halfSw + aa, dCrease)) * maskBodyFill;

    // --- 3. Top Flap ---
    // Triangle folding down from top edge. Vertices: Top-Left, Top-Right, Tip.
    float2 vTL = float2(-b.x, b.y);
    float2 vTR = float2(b.x, b.y);
    float2 vTip = float2(0.0, b.y - FlapHeight);
    
    float dFlap = sdTriangle_Env(p, vTL, vTR, vTip);
    float maskFlapFill = 1.0 - smoothstep(-aa, aa, dFlap);
    float maskFlapStroke = 1.0 - smoothstep(halfSw - aa, halfSw + aa, abs(dFlap));

    // --- 4. Composition ---
    // Initialize canvas (premultiplied alpha)
    float4 col = float4(0, 0, 0, 0);

    // Layer 1: Body Fill
    float4 layerBodyFill = float4(FillColor.rgb * FillColor.a, FillColor.a) * maskBodyFill;
    col = composite_Env(col, layerBodyFill);

    // Layer 2: Pocket Creases (Stroke Color)
    float4 layerCreases = float4(StrokeColor.rgb * StrokeColor.a, StrokeColor.a) * maskCreases;
    col = composite_Env(col, layerCreases);

    // Layer 3: Body Outline (Stroke Color)
    float4 layerBodyStroke = float4(StrokeColor.rgb * StrokeColor.a, StrokeColor.a) * maskBodyStroke;
    col = composite_Env(col, layerBodyStroke);

    // Layer 4: Flap Fill (Fill Color)
    float4 layerFlapFill = float4(FillColor.rgb * FillColor.a, FillColor.a) * maskFlapFill;
    col = composite_Env(col, layerFlapFill);

    // Layer 5: Flap Outline (Stroke Color)
    float4 layerFlapStroke = float4(StrokeColor.rgb * StrokeColor.a, StrokeColor.a) * maskFlapStroke;
    col = composite_Env(col, layerFlapStroke);

    outColor = col;
}

// ------------------------------------------------------------------------
//  Visual Result (High-level, parameter-invariant description)
// ------------------------------------------------------------------------
//  This function generates a **stylized 2D cartoon envelope icon**
//  using Signed Distance Functions (SDFs).
//
//  The visual result is composed of:
//  - A rectangular body with rounded corners representing the envelope packet.
//  - A triangular flap folding down from the top edge, with adjustable height.
//  - Two diagonal crease lines extending from the bottom corners to the center,
//    forming the pocket detail.
//
//  The rendering layers these elements (Body Fill -> Creases -> Outlines -> Flap)
//  to create a clean vector-like icon. All dimensions, corner roundness,
//  flap size, and colors are fully adjustable.
//
//  The output is an anti-aliased RGBA color suitable for mail icons,
//  notification badges, and contact forms.
// ------------------------------------------------------------------------