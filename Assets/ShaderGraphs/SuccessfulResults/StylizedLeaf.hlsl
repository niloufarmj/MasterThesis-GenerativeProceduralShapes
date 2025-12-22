#ifndef PI
#define PI 3.14159265359
#endif

// --- Helper Functions ---

// Rotate a 2D vector by an angle (radians)
float2 leaf_rotate(float2 p, float angle) {
    float c = cos(angle);
    float s = sin(angle);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

// Signed Distance to a Vesica (Intersection of two circles)
// r = radius of circles, d = half distance between centers
float leaf_sdVesica(float2 p, float r, float d) {
    p = abs(p);
    float b = sqrt(r*r - d*d);
    return ((p.y-b)*d > p.x*b) ? length(p - float2(0.0, b))
                               : length(p - float2(-d, 0.0)) - r;
}

// Signed Distance to a Line Segment
float leaf_sdSegment(float2 p, float2 a, float2 b) {
    float2 pa = p - a;
    float2 ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}

// Smooth Minimum for organic blending
float leaf_smin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return lerp(b, a, h) - k * h * (1.0 - h);
}

// --- Main Leaf Function ---
void StylizedLeaf_float(float2 UV, float Size, float Width, float Bend, float StemLength, float StemThickness, float2 Center, float Rotation, float4 Color, out float4 outColor) {
    // PLAN:
    // 1) Center and rotate the coordinate system.
    // 2) Apply a domain distortion (bend) to create the curve.
    // 3) Generate the leaf body using a Vesica SDF (almond shape).
    // 4) Generate the stem using a Segment SDF attached to the bottom.
    // 5) Blend them using smooth minimum.
    // 6) Render with anti-aliasing.

    // 1. Normalize Coordinates
    float2 p = UV - Center;
    p = leaf_rotate(p, -Rotation); // Rotate space opposite to desired shape rotation
    
    // Scale: Size acts as the visual radius. 
    // Avoid division by zero.
    p /= max(Size, 0.0001);

    // 2. Domain Distortion (Bending)
    // Apply a quadratic bend to the x-axis based on y-height.
    // This bends the spine of the leaf.
    // We copy p to preserve original y-metrics if needed, but bending p directly ensures stem moves with body.
    float2 pBent = p;
    pBent.x -= Bend * p.y * p.y * 0.5;

    // 3. Leaf Body (Vesica SDF)
    // Define Vesica parameters based on Width input.
    // Fixed radius r=1.0 for the SDF, we control shape via 'd' (offset).
    // Width input (0..2) maps to d.
    float r = 1.0;
    // d = r - width/2. If Width=2.0, d=0 (Circle). If Width=0, d=1 (Line).
    float wVal = clamp(Width, 0.1, 1.8);
    float d = 1.0 - (wVal * 0.5);
    
    // Calculate vertical offset 'b' to center the vesica visually
    float b = sqrt(r*r - d*d);
    // Offset the vesica so its visual center is near (0,0)
    float2 leafCenterOffset = float2(0.0, 0.0);
    
    float distBody = leaf_sdVesica(pBent - leafCenterOffset, r, d);

    // 4. Stem (Segment SDF)
    // Stem starts at the bottom of the vesica: (0, -b)
    // And extends downwards by StemLength
    // Using pBent coordinates ensures the stem follows the leaf's curvature curve
    float2 stemStart = float2(0.0, -b + 0.1); // Slight overlap into body
    float2 stemEnd = float2(0.0, -b - StemLength);
    
    // Segment SDF minus radius gives thickness
    float distStem = leaf_sdSegment(pBent, stemStart, stemEnd) - StemThickness;

    // 5. Combine Shapes
    // Use smooth min to blend the stem connection organically
    float dist = leaf_smin(distBody, distStem, 0.05);

    // 6. Output
    // Anti-aliasing using fwidth for crisp edges independent of zoom
    float aa = fwidth(dist);
    // Ensure minimum AA width to prevent artifacts when fwidth is zero (rare)
    aa = max(aa, 0.001);
    
    float mask = smoothstep(aa, -aa, dist);
    
    // Apply Color (Pre-multiplied alpha or split, here we output straight alpha in .a)
    outColor = float4(Color.rgb * mask, Color.a * mask);
}