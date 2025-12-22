#ifndef PI
#define PI 3.14159265359
#endif

// --- Helper Functions ---

// Helper: Perpendicular vector (right-hand)
float2 nm_perpRight(float2 e) { return float2(e.y, -e.x); }

// Helper: Distance from point p to segment v0-v1
float nm_distPointToSegment(float2 p, float2 v0, float2 v1) {
    float2 e = v1 - v0;
    float ee = max(dot(e, e), 1e-12);
    float t = clamp(dot(p - v0, e) / ee, 0.0, 1.0);
    return length(p - (v0 + t * e));
}

// Helper: Signed Distance to an Isosceles Trapezoid
// widthBottom: width at the bottom, widthTop: width at the top, height: full height
float nm_sdTrapezoid(float2 p, float widthBottom, float widthTop, float height) {
    float a = 0.5 * widthTop;
    float b = 0.5 * widthBottom;
    float h = 0.5 * height;
    float2 v0 = float2(-b, -h);
    float2 v1 = float2(b, -h);
    float2 v2 = float2(a, h);
    float2 v3 = float2(-a, h);
    
    // Edges and normals
    float2 E0 = v1 - v0; float2 n0 = normalize(nm_perpRight(E0));
    float2 E1 = v2 - v1; float2 n1 = normalize(nm_perpRight(E1));
    float2 E2 = v3 - v2; float2 n2 = normalize(nm_perpRight(E2));
    float2 E3 = v0 - v3; float2 n3 = normalize(nm_perpRight(E3));
    
    // Distance to lines
    float d0 = dot(n0, p - v0);
    float d1 = dot(n1, p - v1);
    float d2 = dot(n2, p - v2);
    float d3 = dot(n3, p - v3);
    
    // Inside test (all half-spaces negative)
    float sgn = (max(max(d0, d1), max(d2, d3)) <= 0.0) ? -1.0 : 1.0;
    
    // Distance to segments
    float du = min(min(nm_distPointToSegment(p, v0, v1), nm_distPointToSegment(p, v1, v2)),
                   min(nm_distPointToSegment(p, v2, v3), nm_distPointToSegment(p, v3, v0)));
                   
    return du * sgn;
}

// Helper: Circle SDF
float sdCircle(float2 p, float r) {
    return length(p) - r;
}

// Helper: Smooth Union (k = smoothness factor)
float opSmoothUnion(float d1, float d2, float k) {
    float h = clamp(0.5 + 0.5 * (d2 - d1) / max(k, 1e-6), 0.0, 1.0);
    return lerp(d2, d1, h) - k * h * (1.0 - h);
}

// Helper: Layer Composition (Source Over Destination)
float4 nm_over(float4 src, float4 dst) {
    float a = src.a + dst.a * (1.0 - src.a);
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-8);
    return float4(c, a);
}

// --- Main Function ---
// User Request: Cartoon bell shape with smooth body, separately sizing clapper, distinct colors, and outline.
void CartoonBellShape_float(float2 UV, float Size, float4 BellColor, float4 ClapperColor, float ClapperSize, float OutlineThickness, float4 OutlineColor, out float4 outColor) {
    // PLAN:
    // 1. Center UVs at (0.5, 0.5) and scale by 'Size' to allow resizing.
    // 2. Define the Bell Body as a smooth union of a top Circle and a bottom flaring Trapezoid.
    // 3. Define the Clapper as a Circle positioned at the bottom of the bell.
    // 4. Compute AA masks for both shapes (Fill and Stroke).
    // 5. Composite the layers: Clapper first, then Bell Body on top (to hide the upper part of the clapper).
    
    // 1. Setup Coordinates
    float2 p = (UV - 0.5);
    // Scale such that Size=1 fits in -0.5..0.5 space. Factor 2.0 normalizes range.
    p = p * 2.0 / max(Size, 0.001);

    // 2. Bell Body Construction
    // Top Dome: Circle shifted up
    float2 topPos = float2(0.0, 0.25);
    float topRadius = 0.35;
    float dTop = sdCircle(p - topPos, topRadius);

    // Bottom Flare: Trapezoid shifted down
    float2 trapPos = float2(0.0, -0.2);
    float wTop = 0.55; // Slightly narrower than circle diam (0.7) for a smooth shoulder blend
    float wBot = 0.9;  // Wide flare at the bottom
    float hTrap = 0.5; // Tall enough to connect top to bottom
    float dBot = nm_sdTrapezoid(p - trapPos, wBot, wTop, hTrap);

    // Combine Dome and Flare smoothly
    float dBell = opSmoothUnion(dTop, dBot, 0.15);

    // 3. Clapper Construction
    // Positioned at the bottom opening of the bell
    float2 clapPos = float2(0.0, -0.5);
    float dClapper = sdCircle(p - clapPos, ClapperSize);

    // 4. Rendering & Masking
    float aa = fwidth(dBell);
    float halfStroke = max(OutlineThickness, 0.0) * 0.5;

    // -- Clapper Layer --
    float clapFillMask = 1.0 - smoothstep(0.0, aa, dClapper);
    float clapStrokeMask = 1.0 - smoothstep(0.0, aa, abs(dClapper) - halfStroke);
    // Clapper Colors
    float4 clapFill = float4(ClapperColor.rgb, ClapperColor.a * clapFillMask);
    float4 clapStroke = float4(OutlineColor.rgb, OutlineColor.a * clapStrokeMask);
    // Composite Clapper (Stroke over Fill)
    float4 clapperLayer = nm_over(clapStroke, clapFill);

    // -- Bell Body Layer --
    float bellFillMask = 1.0 - smoothstep(0.0, aa, dBell);
    float bellStrokeMask = 1.0 - smoothstep(0.0, aa, abs(dBell) - halfStroke);
    // Bell Colors
    float4 bellFill = float4(BellColor.rgb, BellColor.a * bellFillMask);
    float4 bellStroke = float4(OutlineColor.rgb, OutlineColor.a * bellStrokeMask);
    // Composite Bell (Stroke over Fill)
    float4 bellLayer = nm_over(bellStroke, bellFill);

    // 5. Final Composition
    // Draw Bell Body OVER Clapper (standard painter's algorithm for "inside" object)
    // This ensures the part of the clapper inside the bell is hidden/covered by the bell body.
    outColor = nm_over(bellLayer, clapperLayer);
}