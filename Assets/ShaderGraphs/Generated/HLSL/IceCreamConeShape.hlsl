#ifndef PI
#define PI 3.14159265359
#endif

// --- Helper Functions ---

// Distance from point p to segment ab
inline float distSegment(float2 p, float2 a, float2 b) {
    float2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}

// Signed distance to an origin-centered isosceles trapezoid
// widthBottom: full width at bottom (y = -height/2)
// widthTop: full width at top (y = height/2)
// height: full height
inline float sdTrapezoid(float2 p, float widthBottom, float widthTop, float height) {
    float h = height * 0.5;
    float b = widthBottom * 0.5;
    float a = widthTop * 0.5;
    
    // Vertices in CCW order starting from bottom-left
    float2 v0 = float2(-b, -h);
    float2 v1 = float2(b, -h);
    float2 v2 = float2(a, h);
    float2 v3 = float2(-a, h);
    
    // Normal vectors for the 4 edges (outward)
    // Edge 0: Bottom (v0 -> v1). Normal is (0, -1)
    // Edge 1: Right (v1 -> v2). Normal is perp(v2-v1)
    // Edge 2: Top (v2 -> v3). Normal is (0, 1)
    // Edge 3: Left (v3 -> v0). Normal is perp(v0-v3)
    
    float2 e1 = v2 - v1; float2 n1 = normalize(float2(e1.y, -e1.x));
    float2 e3 = v0 - v3; float2 n3 = normalize(float2(e3.y, -e3.x));
    
    // Dot products for half-space checks
    float d0 = -p.y - h; // Bottom edge (y < -h)
    float d1 = dot(n1, p - v1);
    float d2 = p.y - h;  // Top edge (y > h)
    float d3 = dot(n3, p - v3);
    
    // Inside if all distances <= 0
    float sgn = (max(max(d0, d1), max(d2, d3)) <= 0.0) ? -1.0 : 1.0;
    
    // Distance to closest edge
    float dist = min(min(distSegment(p, v0, v1), distSegment(p, v1, v2)),
                     min(distSegment(p, v2, v3), distSegment(p, v3, v0)));
                     
    return dist * sgn;
}

// Circle SDF
inline float sdCircle(float2 p, float r) {
    return length(p) - r;
}

// Main Function: Ice Cream Cone composed of a triangular cone and 3 circular scoops
void IceCreamConeShape_float(float2 UV, float2 Center, float ConeWidth, float ConeHeight, float4 ConeColor, float ScoopSize, float4 Scoop1Color, float4 Scoop2Color, float4 Scoop3Color, out float4 outColor) {
    // PLAN:
    // 1) Center the UV coordinates.
    // 2) Define geometry positions relative to a common anchor (Cone Top Center).
    // 3) Calculate SDF for the Cone (Trapezoid/Triangle).
    // 4) Calculate SDFs for 3 Scoops (Bottom Left, Bottom Right, Top).
    // 5) Layer them back-to-front: Cone -> Bottom Scoops -> Top Scoop.
    // 6) Use smoothstep for anti-aliasing and accumulation.

    float2 p = UV - Center;
    
    // Anchor: We want the top of the cone (width part) to be near y=0 local space
    // sdTrapezoid is centered at (0,0), so top is at y = +height/2.
    // We shift the cone down by height/2 so its top aligns with y=0.
    float2 p_cone = p - float2(0.0, -ConeHeight * 0.5);
    
    // Cone SDF (widthBottom = 0 make it a triangle pointing down)
    float dCone = sdTrapezoid(p_cone, 0.0, ConeWidth, ConeHeight);
    float alphaCone = smoothstep(0.005, -0.005, dCone);
    
    // Initialize color with transparent black
    float4 col = float4(0.0, 0.0, 0.0, 0.0);
    
    // Layer 1: Cone
    col = lerp(col, float4(ConeColor.rgb, 1.0), alphaCone * ConeColor.a);
    
    // Scoop Positioning
    // ScoopRadius is ScoopSize
    // Bottom scoops are offset left/right. Top scoop is centered and higher.
    // We create a slight overlap with the cone (y slightly < 0) and each other.
    float r = ScoopSize;
    
    // Bottom Left Scoop (Scoop 1)
    // Position: Left by approx 80% radius, Up by 30% radius from cone top
    float2 posS1 = float2(-r * 0.8, r * 0.3);
    float dS1 = sdCircle(p - posS1, r);
    float alphaS1 = smoothstep(0.005, -0.005, dS1);
    
    // Layer 2: Scoop 1 (Bottom Left)
    col = lerp(col, float4(Scoop1Color.rgb, 1.0), alphaS1 * Scoop1Color.a);
    
    // Bottom Right Scoop (Scoop 2)
    float2 posS2 = float2(r * 0.8, r * 0.3);
    float dS2 = sdCircle(p - posS2, r);
    float alphaS2 = smoothstep(0.005, -0.005, dS2);
    
    // Layer 3: Scoop 2 (Bottom Right)
    col = lerp(col, float4(Scoop2Color.rgb, 1.0), alphaS2 * Scoop2Color.a);
    
    // Top Scoop (Scoop 3)
    // Position: Centered X, sitting on top of the other two (triangular packing)
    // Height: approx radius * 1.3 above cone top
    float2 posS3 = float2(0.0, r * 1.3);
    float dS3 = sdCircle(p - posS3, r);
    float alphaS3 = smoothstep(0.005, -0.005, dS3);
    
    // Layer 4: Scoop 3 (Top)
    col = lerp(col, float4(Scoop3Color.rgb, 1.0), alphaS3 * Scoop3Color.a);
    
    // Final Output
    // The alpha channel in col accumulates coverage. 
    // Since we initialized with 0 and lerped towards 1.0 opaque colors, 
    // the alpha is roughly correct for a composite shape.
    // To ensure clean edges on a transparent background, we premultiply if needed,
    // but here we just output the accumulated result.
    outColor = col;
}