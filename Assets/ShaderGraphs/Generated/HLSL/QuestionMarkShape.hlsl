/*
PLAN:
1. Define helpers: sdSegment (line) and sdArc (for the hook).
2. Center UVs at (0.5, 0.5).
3. Define the Question Mark parts:
   - Dot: Circle at bottom.
   - Stem: Vertical segment connecting hook to gap above dot.
   - Hook: Circular arc sweeping from the stem connection around to the left.
4. Combine SDFs using min().
5. Apply smoothstep for AA and output color.
*/

#ifndef PI
#define PI 3.14159265359
#endif

// Helper: Signed Distance to a Line Segment
float sdSegment_QM(float2 p, float2 a, float2 b) {
    float2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}

// Helper: Signed Distance to an Arc (Symmetric about Y axis)
// p: point, sc: sin/cos of aperture, ra: radius, rb: thickness
float sdArc_QM(float2 p, float2 sc, float ra, float rb) {
    p.x = abs(p.x);
    return ((sc.y * p.x > sc.x * p.y) ? length(p - sc * ra) : 
           abs(length(p) - ra)) - rb;
}

void QuestionMarkShape_float(float2 UV, float Size, float Thickness, float4 Color, out float4 outColor) {
    // 1. Setup Coordinates
    float2 centered = UV - 0.5;
    // Scale geometry by Size (avoid divide by zero)
    float2 p = centered / max(Size, 0.0001);
    
    // Clamp thickness to be reasonable
    float t = max(Thickness, 0.001);
    
    // 2. Define Shape Geometry
    // The shape is constructed in local space roughly [-0.5, 0.5]
    
    // Part A: The Dot
    // Positioned at y = -0.35
    float dDot = length(p - float2(0.0, -0.35)) - t;
    
    // Part B: The Stem
    // Vertical line connecting the hook (y=0.02) downwards towards the dot
    // We stop at y=-0.15 to leave a gap for the dot
    float dStem = sdSegment_QM(p, float2(0.0, 0.02), float2(0.0, -0.15)) - t;
    
    // Part C: The Hook (Arc)
    // Arc Center: (0, 0.2)
    // Radius: 0.18 (so bottom connects at 0.2 - 0.18 = 0.02)
    // Range: We want the hook to sweep from -90 deg (bottom connection) 
    //        Counter-Clockwise to approx 150 deg (top-left curl).
    //        Total Span: 240 degrees. Midpoint: 30 degrees.
    //        Half-Aperture: 120 degrees.
    
    float2 arcCenter = float2(0.0, 0.2);
    float radius = 0.18;
    float2 pArc = p - arcCenter;
    
    // Rotate local space so the midpoint (30 deg) aligns with Up (90 deg)
    // Rotation needed: +60 degrees (CCW)
    float ang = radians(60.0);
    float s = sin(ang);
    float c = cos(ang);
    float2 pRot = float2(pArc.x * c - pArc.y * s, pArc.x * s + pArc.y * c);
    
    // Aperture setup (120 degrees)
    float ap = radians(120.0);
    float2 sc = float2(sin(ap), cos(ap));
    
    float dArc = sdArc_QM(pRot, sc, radius, t);
    
    // 3. Combine Parts (Union)
    float dist = min(dDot, min(dStem, dArc));
    
    // 4. Output with Anti-Aliasing
    float edge = smoothstep(0.01, -0.01, dist);
    outColor = float4(Color.rgb * edge, edge);
}