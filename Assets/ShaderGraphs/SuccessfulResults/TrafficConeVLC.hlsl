#ifndef PI
#define PI 3.14159265359
#endif

// --- Helper Functions ---

// Distance from point p to line segment ab
float sdSegment(float2 p, float2 a, float2 b) {
    float2 pa = p - a, ba = b - a;
    float h = saturate(dot(pa, ba) / dot(ba, ba));
    return length(pa - ba * h);
}

// SDF for a generic convex quadrilateral (CCW order)
float sdConvexPoly4(float2 p, float2 v0, float2 v1, float2 v2, float2 v3) {
    float2 v[4] = { v0, v1, v2, v3 };
    float d2 = 1e20;
    float s = -1e20;

    [unroll]
    for (int i = 0; i < 4; ++i) {
        float2 a = v[i];
        float2 b = v[(i + 1) % 4];
        
        // Distance to segment
        float sdE = sdSegment(p, a, b);
        d2 = min(d2, sdE * sdE);
        
        // Signed distance to line (using outward normal for CCW)
        float2 e = b - a;
        float2 n = normalize(float2(e.y, -e.x));
        float sEdge = dot(p - a, n);
        s = max(s, sEdge);
    }
    
    return (s > 0.0) ? sqrt(d2) : -sqrt(d2);
}

// Standard Box SDF
float sdBox(float2 p, float2 b) {
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// --- Main Function ---
// Generates a traffic cone shape resembling the VLC icon with stripes, base, and 3D-like curvature.
void TrafficConeVLC_float(float2 UV, float Size, float WidthRatio, float Curvature, float4 ConeColor, float4 StripeColor, float4 BaseColor, out float4 outColor) {
    // PLAN:
    // 1) Center UVs to p in [-1, 1] range relative to Size.
    // 2) Define geometry dimensions (Body Height, Base Height, Top/Bottom Widths).
    // 3) Create Cone Body using sdConvexPoly4 (Trapezoid).
    // 4) Create Base using sdBox.
    // 5) Combine with min() for solid union.
    // 6) Calculate stripe pattern based on Y height + quadratic curvature (parabola).
    // 7) Composite colors: BaseColor for bottom, Cone/Stripe mix for body.
    // 8) Apply analytic anti-aliasing.

    // 1. Setup coordinates
    float2 centered = UV - 0.5;
    // Adjust scale so Size=1 fills screen vertically roughly
    // Size parameter controls the total height
    float totalH = max(Size, 0.01) * 2.0;
    float maxW = totalH * max(WidthRatio, 0.1);
    
    // 2. Geometry Parameters
    // Base is ~15% of height, Body is ~85%
    float hBase = totalH * 0.12;
    float hBody = totalH * 0.88;
    
    // Widths
    float wBase = maxW * 1.1; // Base slightly wider than cone bottom
    float wBottom = maxW;
    float wTop = maxW * 0.15; // Truncated tip
    
    // Vertical Positioning
    // We want the total shape centered. 
    // Total range is [-totalH/2, totalH/2]
    float yBottom = -totalH * 0.5;
    float yBaseCenter = yBottom + hBase * 0.5;
    float yBodyStart = yBottom + hBase;
    float yBodyCenter = yBodyStart + hBody * 0.5;
    
    // 3. Cone Body SDF (Trapezoid)
    // Vertices relative to body center (CCW)
    // Bottom-Left, Bottom-Right, Top-Right, Top-Left
    float2 c = float2(0.0, yBodyCenter);
    float hb = hBody * 0.5;
    float wb = wBottom * 0.5;
    float wt = wTop * 0.5;
    
    float2 v0 = float2(-wb, -hb); // BL
    float2 v1 = float2(wb, -hb);  // BR
    float2 v2 = float2(wt, hb);   // TR
    float2 v3 = float2(-wt, hb);  // TL
    
    float dBody = sdConvexPoly4(centered - c, v0, v1, v2, v3);
    
    // 4. Base SDF (Box)
    float2 baseSize = float2(wBase * 0.5, hBase * 0.5);
    // Add slight rounding to base for better look
    float dBase = sdBox(centered - float2(0.0, yBaseCenter), baseSize) - (min(baseSize.x, baseSize.y) * 0.1);
    
    // 5. Combine (Union)
    // Using smooth min for slight blending or hard min
    float dist = min(dBody, dBase);
    
    // 6. Stripe Logic
    // Calculate normalized height along the cone body [0, 1]
    // Apply curvature: stripes should bow downwards (smile) to look like a cone viewed from above/front
    // Parabolic offset based on X distance from center
    float xRel = (centered.x) / (wBottom * 0.5);
    float curve = xRel * xRel * Curvature * 0.1;
    
    // Map y to 0..1 relative to body
    // (p.y - startY) / height
    float t = (centered.y - yBodyStart) / hBody;
    t = t - curve; // Apply curvature offset

    // Define VLC-style stripes (Orange-White-Orange-White-Orange)
    // White bands at approx 0.3-0.45 and 0.6-0.75
    // Band 1
    float band1 = smoothstep(0.28, 0.30, t) - smoothstep(0.43, 0.45, t);
    // Band 2
    float band2 = smoothstep(0.58, 0.60, t) - smoothstep(0.73, 0.75, t);
    
    float isStripe = saturate(band1 + band2);
    
    // 7. Coloring
    // Determine if pixel belongs to Base or Body
    // Simple heuristic: if dBase < dBody, it's base.
    // Smooth transition for anti-aliasing internal edge
    float isBase = smoothstep(0.0, 0.01, dBody - dBase);
    
    float4 bodyFill = lerp(ConeColor, StripeColor, isStripe);
    float4 shapeColor = lerp(bodyFill, BaseColor, isBase);
    
    // 8. Output with AA
    float aa = fwidth(dist);
    float alpha = 1.0 - smoothstep(-aa, aa, dist);
    
    outColor = float4(shapeColor.rgb * alpha, alpha * shapeColor.a);
}

// ------------------------------------------------------------------------
//  Visual Result (High-level, parameter-invariant description)
// ------------------------------------------------------------------------
//  This function generates a **stylized 2D traffic-cone-like primitive**
//  inspired by a classic media-player cone silhouette, using Signed
//  Distance Functions (SDFs).
//
//  The shape consists of a tapered conical body with a truncated top,
//  a wider rectangular base, and multiple horizontal stripe regions
//  across the body. The overall size, width proportions, curvature,
//  stripe appearance, coloring, and visual style are fully controlled
//  by input parameters and are not fixed by the function itself.
//
//  The output is an anti-aliased RGBA color suitable for icons,
//  warning symbols, media-related graphics, playful UI elements,
//  and expressive procedural 2D visuals.
// ------------------------------------------------------------------------
