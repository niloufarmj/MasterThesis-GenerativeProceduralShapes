// PLAN:
// 1) Define SDF helpers: sdEllipse (exact), sdTriangle, opSmoothUnion, sdCircle.
// 2) Center and scale UVs to [-1, 1].
// 3) Apply curvature bending to the coordinate space.
// 4) Define Body using sdEllipse.
// 5) Define Tail using a forked triangle (Triangle minus Circle).
// 6) Define Dorsal and Ventral fins using Triangles attached to the body.
// 7) Combine Body, Tail, and Fins into a single shape SDF (dShape) with smooth union.
// 8) Define Eye and Gill line SDFs separately.
// 9) Compute alpha masks for fills and strokes using smoothstep.
// 10) Composite layers: Outline -> Body Fill -> Gill Stroke -> Eye Fill -> Eye Outline.

#ifndef PI
#define PI 3.14159265359
#endif

// --- Helper Functions ---

// Exact signed distance to an ellipse
float sdEllipse(float2 p, float2 ab) {
    p = abs(p);
    if (p.x > p.y) { p = p.yx; ab = ab.yx; }
    float l = ab.y*ab.y - ab.x*ab.x;
    float m = ab.x*p.x/l;
    float m2 = m*m;
    float n = ab.y*p.y/l;
    float n2 = n*n;
    float c = (m2+n2-1.0)/3.0;
    float c3 = c*c*c;
    float q = c3 + m2*n2*2.0;
    float d = c3 + m2*n2;
    float g = m + m*n2;
    float co;
    if (d < 0.0) {
        float h = acos(q/c3)/3.0;
        float s = cos(h);
        float t = sin(h)*sqrt(3.0);
        float rx = sqrt(-c*(s + t + 2.0) + m2);
        float ry = sqrt(-c*(s - t + 2.0) + m2);
        co = (ry + sign(l)*rx + abs(g)/(rx*ry) - m)/2.0;
    } else {
        float h = 2.0*m*n*sqrt(d);
        float s = sign(q+h)*pow(abs(q+h), 1.0/3.0);
        float u = sign(q-h)*pow(abs(q-h), 1.0/3.0);
        float rx = -s - u - c*4.0 + 2.0*m2;
        float ry = (s - u)*sqrt(3.0);
        float rm = sqrt(rx*rx + ry*ry);
        co = (ry/sqrt(rm-rx) + 2.0*g/rm - m)/2.0;
    }
    float2 r = ab * float2(co, sqrt(1.0-co*co));
    return length(r-p) * sign(p.y-r.y);
}

// Signed distance to a generic triangle
float sdTriangle(float2 p, float2 p0, float2 p1, float2 p2) {
    float2 e0 = p1 - p0; float2 e1 = p2 - p1; float2 e2 = p0 - p2;
    float2 v0 = p - p0; float2 v1 = p - p1; float2 v2 = p - p2;
    float2 pq0 = v0 - e0*clamp(dot(v0,e0)/dot(e0,e0), 0.0, 1.0);
    float2 pq1 = v1 - e1*clamp(dot(v1,e1)/dot(e1,e1), 0.0, 1.0);
    float2 pq2 = v2 - e2*clamp(dot(v2,e2)/dot(e2,e2), 0.0, 1.0);
    float s = sign(e0.x*e2.y - e0.y*e2.x);
    float2 d = min(min(float2(dot(pq0,pq0), s*(v0.x*e0.y-v0.y*e0.x)),
                       float2(dot(pq1,pq1), s*(v1.x*e1.y-v1.y*e1.x))),
                       float2(dot(pq2,pq2), s*(v2.x*e2.y-v2.y*e2.x)));
    return -sqrt(d.x)*sign(d.y);
}

// Smooth union of two SDFs
float opSmoothUnion(float d1, float d2, float k) {
    float h = clamp(0.5 + 0.5*(d2-d1)/max(k, 0.001), 0.0, 1.0);
    return lerp(d2, d1, h) - k*h*(1.0-h);
}

// 2D Rotation helper
float2 rotate(float2 p, float a) {
    float c = cos(a), s = sin(a);
    return float2(c*p.x - s*p.y, s*p.x + c*p.y);
}

// --- Main Function ---
void CartoonFishShape_float(
    float2 UV,
    float2 BodySize,      // x = half-length, y = half-width
    float BodyCurvature,  // Bends the fish
    float TailSize,       // Scale of the tail
    float TailSpread,     // Width/Spread of the tail fork
    float2 DorsalFin,     // x = Size, y = Position offset
    float2 VentralFin,    // x = Size, y = Position offset
    float GillCurve,      // Curvature of gill line
    float EyeSize,        // Radius of eye
    float StrokeWidth,    // Thickness of outlines
    float4 BodyColor,
    float4 OutlineColor,
    float4 EyeColor,
    out float4 outColor
) {
    // 1. Setup coordinates (Center 0,0)
    float2 p = (UV - 0.5) * 2.0;
    
    // 2. Apply Body Curvature (Bend the space)
    // This deforms the coordinate system so straight shapes appear curved
    float2 pBend = p;
    pBend.y -= BodyCurvature * pBend.x * pBend.x;

    // 3. Body SDF (Ellipse)
    // Ensure dimensions are positive to avoid artifacts
    float2 bodyDims = max(BodySize, 0.001);
    float dBody = sdEllipse(pBend, bodyDims);

    // 4. Tail Fin SDF
    // Attached at the posterior (-BodyLength). 
    // Modeled as a triangle pointing left, with a circular bite taken out to make it forked.
    float2 tailPos = float2(-bodyDims.x, 0.0);
    float2 pTail = pBend - tailPos;
    
    // Vertices for the tail triangle
    float2 t0 = float2(0.0, 0.0); // Attachment point
    float2 t1 = float2(-TailSize, TailSpread); // Top tip
    float2 t2 = float2(-TailSize, -TailSpread); // Bottom tip
    float dTailTri = sdTriangle(pTail, t0, t1, t2);
    
    // Subtract a circle to fork the tail
    float dFork = length(pTail - float2(-TailSize * 1.2, 0.0)) - (TailSize * 0.6);
    float dTail = max(dTailTri, -dFork);

    // 5. Dorsal Fin (Top)
    // Triangle on the top edge of the body
    // Calculate approximate surface Y at the fin position for placement
    float2 pDorsal = pBend - float2(DorsalFin.y, bodyDims.y * 0.8);
    float dFinTop = sdTriangle(pDorsal, float2(-DorsalFin.x * 0.5, 0.0), float2(DorsalFin.x * 0.2, DorsalFin.x), float2(DorsalFin.x * 0.8, 0.0));

    // 6. Ventral Fin (Bottom)
    float2 pVentral = pBend - float2(VentralFin.y, -bodyDims.y * 0.8);
    float dFinBot = sdTriangle(pVentral, float2(-VentralFin.x * 0.5, 0.0), float2(VentralFin.x * 0.2, -VentralFin.x), float2(VentralFin.x * 0.8, 0.0));

    // 7. Combine Shape (Union)
    float dShape = opSmoothUnion(dBody, dTail, 0.05);
    dShape = opSmoothUnion(dShape, dFinTop, 0.05);
    dShape = opSmoothUnion(dShape, dFinBot, 0.05);

    // 8. Eye SDF
    // Placed towards the front (+X)
    float2 eyePos = float2(bodyDims.x * 0.6, bodyDims.y * 0.2);
    float dEye = length(pBend - eyePos) - EyeSize;

    // 9. Gill Line SDF
    // A curved arc separating head from body
    // Modeled as distance to a circle segment, clipped by x coordinate
    float2 gillCenter = float2(bodyDims.x * 0.6 - bodyDims.y * 1.5, 0.0);
    float gillRadius = bodyDims.y * 1.5;
    // Adjust radius based on curve parameter slightly
    float2 pGill = pBend - float2(0.0, 0.0); // Relative to body center
    // Distance to a vertical-ish arc: dist to circle centered far left/right
    // Simple approximation: Offset circle
    float dGillCircle = length(pBend - float2(bodyDims.x * 0.2 - GillCurve, 0.0)) - max(bodyDims.y, 0.01) * 1.1;
    float dGill = abs(dGillCircle) - StrokeWidth * 0.5;
    // Clip the gill line to be within the body and within a specific x-range
    float gillMaskVal = max(dGill, dBody); // Must be inside body
    // Only show gill line if it's within a vertical band
    float gillBand = max(gillMaskVal, abs(pBend.x - bodyDims.x * 0.2) - 0.2);
    
    // 10. Rendering / Compositing
    float aa = 0.01; // Softness for anti-aliasing
    
    // Base Shape Masks
    float alphaShape = smoothstep(aa, -aa, dShape);
    float alphaOutline = smoothstep(aa, -aa, abs(dShape) - StrokeWidth);
    float alphaEye = smoothstep(aa, -aa, dEye);
    float alphaEyeOutline = smoothstep(aa, -aa, abs(dEye) - StrokeWidth * 0.5);
    
    // Gill Mask (stroke only, cropped to body)
    // We use a slightly sharper AA for lines inside the shape
    float alphaGill = smoothstep(aa, -aa, dGill);
    // Crop gill to body
    alphaGill *= smoothstep(0.0, -aa, dBody + StrokeWidth); 
    // Simple spatial crop for gill to ensure it doesn't circle the whole fish
    alphaGill *= smoothstep(bodyDims.x * 0.4, bodyDims.x * 0.1, pBend.x);

    // Composition Layering (Painter's Algorithm)
    float4 col = float4(0,0,0,0);

    // Layer 1: Global Outline
    // We draw the outline color everywhere the thick shape exists
    float shapeDistWithOutline = dShape - StrokeWidth * 0.5;
    float outlineMask = smoothstep(aa, -aa, shapeDistWithOutline);
    col = lerp(col, OutlineColor, outlineMask);

    // Layer 2: Body Fill
    // Draw body color strictly inside the shape
    float fillMask = smoothstep(aa, -aa, dShape + StrokeWidth * 0.5);
    col = lerp(col, BodyColor, fillMask);

    // Layer 3: Gill Line
    col = lerp(col, OutlineColor, alphaGill);

    // Layer 4: Eye Fill
    col = lerp(col, EyeColor, alphaEye);

    // Layer 5: Eye Outline
    col = lerp(col, OutlineColor, alphaEyeOutline * (1.0 - alphaEye));

    // Final Output
    outColor = col;
    // Ensure alpha is correct for transparency
    outColor.a = clamp(outlineMask + alphaShape, 0.0, 1.0);
}

// ------------------------------------------------------------------------
//  Visual Result (High-level, parameter-invariant description)
// ------------------------------------------------------------------------
//  This function generates a **stylized 2D cartoon fish** using
//  Signed Distance Functions (SDFs).
//
//  The visual result is composed of:
//  - A streamlined oval body that bends organically using domain distortion.
//  - A forked tail fin attached to the posterior.
//  - Triangular dorsal (top) and ventral (bottom) fins.
//  - A circular eye and a curved gill line detail on the head.
//
//  The rendering blends the body and fins into a single continuous silhouette
//  with a consistent outline. The eye and gill are layered on top.
//  All dimensions, curvature, and colors are fully adjustable.
//
//  The output is an anti-aliased RGBA color suitable for aquatic themes,
//  animal icons, and underwater scenery.
// ------------------------------------------------------------------------