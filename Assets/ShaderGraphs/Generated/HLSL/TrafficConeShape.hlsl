#ifndef PI
#define PI 3.14159265359
#endif

// --- Helper Functions ---

// Standard Box SDF
float sdBox(float2 p, float2 b) {
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// Helper for Trapezoid SDF (Distance Point to Segment)
float nm_distPointToSegment(float2 p, float2 v0, float2 v1) {
    float2 e = v1 - v0;
    float ee = max(dot(e, e), 1e-12);
    float t = clamp(dot(p - v0, e) / ee, 0.0, 1.0);
    float2 q = v0 + t * e;
    return length(p - q);
}

// Perpendicular vector helper
float2 nm_perpRight(float2 e) {
    return float2(e.y, -e.x);
}

// Signed distance to an origin-centered, axis-aligned isosceles trapezoid
// p: sample point
// widthBottom: full width at bottom
// widthTop: full width at top
// height: full height
float nm_sdTrapezoid(float2 p, float widthBottom, float widthTop, float height) {
    float a = 0.5 * widthTop;
    float b = 0.5 * widthBottom;
    float h = 0.5 * height;

    // CCW vertices: bottom-left, bottom-right, top-right, top-left
    float2 v0 = float2(-b, -h);
    float2 v1 = float2(b, -h);
    float2 v2 = float2(a, h);
    float2 v3 = float2(-a, h);

    // Edges (v0->v1 is bottom, v1->v2 is right side, v2->v3 is top, v3->v0 is left)
    // We only need to check dist to segments and half-spaces.
    // Since it's symmetric isosceles, simpler logic exists, but general polygon logic is robust.
    
    // Outward normals
    float2 n0 = float2(0.0, -1.0);
    float2 n1 = normalize(nm_perpRight(v2 - v1));
    float2 n2 = float2(0.0, 1.0);
    float2 n3 = normalize(nm_perpRight(v0 - v3));

    // Half-space distances
    float d0 = dot(p - v0, n0);
    float d1 = dot(p - v1, n1);
    float d2 = dot(p - v2, n2);
    float d3 = dot(p - v3, n3);

    // Sign: Inside if all d < 0
    float sgn = (max(max(d0, d1), max(d2, d3)) <= 0.0) ? -1.0 : 1.0;

    // Distance to boundary (min dist to any edge)
    float du = min(
        min(nm_distPointToSegment(p, v0, v1), nm_distPointToSegment(p, v1, v2)),
        min(nm_distPointToSegment(p, v2, v3), nm_distPointToSegment(p, v3, v0))
    );

    return du * sgn;
}

// --- Main Function ---
// Generates a traffic cone shape (VLC-style) with adjustable size, proportions, and stripes.
void TrafficConeShape_float(float2 UV, float Size, float Proportions, float StripeScale, float4 ConeColor, float4 StripeColor, out float4 outColor) {
    // PLAN:
    // 1) Center UVs and calculate dimensions based on Size/Proportions.
    // 2) Define cone body using Trapezoid SDF.
    // 3) Define base using Box SDF.
    // 4) Combine using min() for union.
    // 5) Calculate stripe mask based on Y position within the cone height.
    // 6) Composite colors and apply anti-aliasing.

    float2 p = UV - 0.5;
    
    // 1) Dimensions
    // Ensure safe values
    float s = max(Size, 0.01);
    float prop = max(Proportions, 0.1);
    
    float totalH = s * prop;
    float baseH = totalH * 0.15; // Base is 15% of height
    float coneH = totalH * 0.85; // Cone body is 85%
    
    float wBottom = s;           // Width of cone bottom
    float wTop = s * 0.2;        // Width of cone tip (truncated)
    float wBase = s * 1.25;      // Base is wider than cone

    // 2) Positioning
    // We want the whole shape centered. 
    // Total range Y: [-totalH/2, totalH/2]
    // Base Center Y: Bottom (-totalH/2) + half base height
    float baseCy = -totalH * 0.5 + baseH * 0.5;
    // Cone Center Y: Top of base (-totalH/2 + baseH) + half cone height
    float coneCy = -totalH * 0.5 + baseH + coneH * 0.5;

    // 3) SDF Calculations
    // Cone Body
    float dCone = nm_sdTrapezoid(p - float2(0.0, coneCy), wBottom, wTop, coneH);
    // Base
    float dBase = sdBox(p - float2(0.0, baseCy), float2(wBase * 0.5, baseH * 0.5));
    
    // Union of Cone and Base
    float dist = min(dCone, dBase);

    // 4) Anti-Aliasing
    float aa = fwidth(dist);
    float edge = 1.0 - smoothstep(0.0, aa, dist);

    // 5) Coloring & Stripes
    // We apply stripes only to the cone part, not the base.
    // Stripe logic: Use normalized height along the cone part.
    // p.y relative to cone bottom
    float coneBottomY = -totalH * 0.5 + baseH;
    float relY = (p.y - coneBottomY) / coneH;

    // Stripe bands definition (relative to cone height 0..1)
    float stripeWidth = 0.15 * StripeScale;
    float s1_center = 0.35;
    float s2_center = 0.65;
    
    // Create sharp bands with slight smoothing for pixel alignment
    // Use smoothstep for band edges (width approx 0.01 for sharpness)
    float bandSoft = 0.01;
    float mask1 = smoothstep(stripeWidth + bandSoft, stripeWidth, abs(relY - s1_center));
    float mask2 = smoothstep(stripeWidth + bandSoft, stripeWidth, abs(relY - s2_center));
    float stripeMask = saturate(mask1 + mask2);

    // Determine if pixel is effectively "on the base" vs "on the cone"
    // If dBase < dCone, we are closer to the base. 
    // However, for coloring, we just need to know if we are in the stripe vertical range AND inside the shape.
    // To prevent stripes from bleeding onto the base visually, we mask by Y > coneBottomY.
    float isConeBody = step(coneBottomY, p.y);
    
    // Final color mixing
    float4 bodyColor = lerp(ConeColor, StripeColor, stripeMask * isConeBody);
    
    // Output
    outColor = float4(bodyColor.rgb * edge, edge * bodyColor.a);
}