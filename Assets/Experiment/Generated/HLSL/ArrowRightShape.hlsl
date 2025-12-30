#ifndef PI
#define PI 3.14159265359
#endif

// SDF for an axis-aligned box
// p: sample position, b: half-extents
float sdBox(float2 p, float2 b) {
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// SDF for an isosceles triangle pointing right
// Tip at (0,0), Base at x = -len, Half-width = width
float sdArrowHead(float2 p, float len, float width) {
    // Symmetry in Y
    p.y = abs(p.y);
    
    // Vertices relative to tip (0,0)
    float2 tip = float2(0.0, 0.0);
    float2 backTop = float2(-len, width);
    float2 backBottom = float2(-len, 0.0);
    
    // 1. Distance to slant edge (Tip -> BackTop)
    float2 pa = p - tip;
    float2 ba = backTop - tip;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    float dSlant = length(pa - ba * h);
    
    // 2. Distance to back vertical edge (BackTop -> BackBottom)
    float2 pb = p - backBottom;
    float2 bb = backTop - backBottom;
    float k = clamp(dot(pb, bb) / dot(bb, bb), 0.0, 1.0);
    float dBack = length(pb - bb * k);
    
    // Minimum distance to boundary
    float d = min(dSlant, dBack);
    
    // Sign determination (negative inside)
    // Inside if x > -len AND dot(p, normalSlant) < 0
    // Normal of slant edge is (width, len) pointing outwards
    bool inside = (p.x > -len) && ((p.x * width + p.y * len) < 0.0);
    
    return inside ? -d : d;
}

void ArrowRightShape_float(float2 UV, float Length, float Thickness, float HeadSize, float4 Color, out float4 outColor) {
    // PLAN:
    // 1) Center UVs at (0.5, 0.5).
    // 2) Validate dimensions (Shaft Length vs Head Size).
    // 3) Calculate SDF for the Shaft (Rectangle).
    // 4) Calculate SDF for the Head (Triangle) attached to the shaft.
    // 5) Combine using Union (min).
    // 6) Apply Anti-aliasing and Color.

    float2 p = UV - 0.5;
    
    // Clamp dimensions to safe values
    float L = max(Length, 0.001); // Total length
    float H = min(max(HeadSize, 0.001), L); // Head length (clamped to total)
    float T = max(Thickness, 0.001); // Shaft thickness
    
    // --- SHAFT SDF ---
    // The arrow is centered along X. Total bounds: [-L/2, L/2]
    // Shaft goes from left (-L/2) to the base of the head (L/2 - H)
    // Shaft Length = L - H
    // Shaft Center X = (-L/2 + (L/2 - H)) / 2 = -H/2
    float shaftLen = L - H;
    float2 shaftCenter = float2(-H * 0.5, 0.0);
    float2 shaftHalfSize = float2(shaftLen * 0.5, T * 0.5);
    
    // Ensure non-negative box size (if HeadSize >= Length)
    shaftHalfSize = max(shaftHalfSize, 0.0);
    float dShaft = sdBox(p - shaftCenter, shaftHalfSize);
    
    // --- HEAD SDF ---
    // Head is a triangle with Tip at x = L/2
    // Base of head is at x = L/2 - H
    // Shift p relative to the tip for the SDF function
    float2 pHead = p - float2(L * 0.5, 0.0);
    
    // Define head width proportional to its size (can be tweaked)
    // Here we use 0.8 * HeadSize for the half-width
    float headHalfWidth = H * 0.8;
    float dHead = sdArrowHead(pHead, H, headHalfWidth);
    
    // --- COMBINE ---
    // Union of Shaft and Head
    float dist = min(dShaft, dHead);
    
    // --- OUTPUT ---
    // Analytic Anti-aliasing
    float aa = fwidth(dist);
    float edge = smoothstep(aa, -aa, dist);
    
    outColor = float4(Color.rgb * edge, Color.a * edge);
}