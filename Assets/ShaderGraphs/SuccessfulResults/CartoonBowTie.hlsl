#ifndef PI
#define PI 3.14159265359
#endif

// --- Helper Functions ---

// Signed distance to a line segment AB
float sdSegment(float2 p, float2 a, float2 b) {
    float2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}

// Signed distance to a convex polygon (4 vertices, CCW)
// Returns negative inside, positive outside
float sdConvexPoly4(float2 p, float2 v0, float2 v1, float2 v2, float2 v3) {
    float2 v[4] = { v0, v1, v2, v3 };
    float d2 = 1e20;
    float s = -1e20;
    
    [unroll]
    for (int i = 0; i < 4; ++i) {
        float2 a = v[i];
        float2 b = v[(i + 1) & 3];
        
        // Distance to edge segment
        float eDist = sdSegment(p, a, b);
        d2 = min(d2, eDist * eDist);
        
        // Edge normal check for sign (outward normal)
        float2 e = b - a;
        float2 n = normalize(float2(e.y, -e.x));
        s = max(s, dot(p - a, n));
    }
    
    return (s > 0.0) ? sqrt(d2) : -sqrt(d2);
}

// Signed distance to a box
float sdBox(float2 p, float2 b) {
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// Alpha blending helper (Src Over Dst)
float4 blendOver(float4 src, float4 dst) {
    float a = src.a + dst.a * (1.0 - src.a);
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-8);
    return float4(c, a);
}

// --- Main Function ---
// User Request: Cartoon bow tie with symmetric triangular loops, central knot, adjustable sizes/roundness/curvature.
void CartoonBowTie_float(float2 UV, float Size, float WingWidth, float WingHeight, float KnotWidth, float KnotHeight, float Roundness, float Curvature, float4 Color, float4 OutlineColor, float OutlineWidth, out float4 outColor) {
    // 1. Setup Center and Scale
    float2 p = (UV - 0.5) * 2.0; // Map to -1..1 range roughly
    p /= max(Size, 0.001);       // Apply global size

    // 2. Apply Curvature (Global Bend)
    // Bends the Y coordinate parabolically based on X to give a 'droopy' or 'perky' look
    p.y -= Curvature * p.x * p.x;

    // 3. Symmetry for Wings
    // We model the right wing, then mirror across X
    float2 q = float2(abs(p.x), p.y);

    // 4. Define Shapes
    // -- Wing Shape (Rounded Trapezoid) --
    // Defined by 4 vertices in the symmetry space
    // Starts at x=0 (center) to ensure overlap behind the knot
    float wH_outer = WingHeight * 0.5;
    float wH_inner = KnotHeight * 0.35; // Slightly pinched at the knot connection
    float wW = WingWidth;
    
    // Vertices (CCW order): Bottom-Left, Bottom-Right, Top-Right, Top-Left
    float2 v0 = float2(0.0, -wH_inner);
    float2 v1 = float2(wW, -wH_outer);
    float2 v2 = float2(wW, wH_outer);
    float2 v3 = float2(0.0, wH_inner);

    float dWings = sdConvexPoly4(q, v0, v1, v2, v3);
    dWings -= Roundness; // Apply rounded corners

    // -- Knot Shape (Rounded Box) --
    // The knot is drawn in the original p space (centered)
    float2 knotBounds = float2(KnotWidth * 0.5, KnotHeight * 0.5);
    float dKnot = sdBox(p, knotBounds) - Roundness;

    // 5. Render Layers (Painter's Algorithm)
    float aa = fwidth(p.x);
    aa = max(aa, 0.001);

    // Layer 1: Wings
    // Fill
    float wingFillAlpha = 1.0 - smoothstep(0.0, aa, dWings);
    float4 layerWings = float4(Color.rgb, Color.a * wingFillAlpha);
    
    // Outline
    float wingOutlineDist = abs(dWings) - OutlineWidth * 0.5;
    float wingOutlineAlpha = 1.0 - smoothstep(0.0, aa, wingOutlineDist);
    // Composite Outline over Fill for Wings
    float4 wingStrokeColor = float4(OutlineColor.rgb, OutlineColor.a * wingOutlineAlpha);
    float4 wingsFinal = blendOver(wingStrokeColor, layerWings);

    // Layer 2: Knot (Drawn ON TOP of wings)
    // Fill
    float knotFillAlpha = 1.0 - smoothstep(0.0, aa, dKnot);
    float4 layerKnot = float4(Color.rgb, Color.a * knotFillAlpha);
    
    // Outline
    float knotOutlineDist = abs(dKnot) - OutlineWidth * 0.5;
    float knotOutlineAlpha = 1.0 - smoothstep(0.0, aa, knotOutlineDist);
    // Composite Outline over Fill for Knot
    float4 knotStrokeColor = float4(OutlineColor.rgb, OutlineColor.a * knotOutlineAlpha);
    float4 knotFinal = blendOver(knotStrokeColor, layerKnot);

    // 6. Final Composite: Knot over Wings
    outColor = blendOver(knotFinal, wingsFinal);
}

// ------------------------------------------------------------------------
//  Visual Result (High-level, parameter-invariant description)
// ------------------------------------------------------------------------
//  This function generates a **stylized 2D cartoon bow tie**
//  using Signed Distance Functions (SDFs).
//
//  The visual result is composed of:
//  - Two symmetric wing segments (loops) shaped as rounded trapezoids.
//  - A central knot segment shaped as a rounded box.
//  - A global curvature deformation that bends the tie (droopy or perky).
//
//  The rendering applies a "Painter's Algorithm" style, drawing the central
//  knot outline *over* the wings to create depth. The overall proportions,
//  roundness, bending, and colors are fully controlled by input parameters.
//
//  The output is an anti-aliased RGBA color suitable for clothing icons,
//  character accessories, and decorative 2D graphics.
// ------------------------------------------------------------------------