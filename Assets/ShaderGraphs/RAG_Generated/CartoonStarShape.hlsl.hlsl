/*
  PLAN:
  1. Define helpers for compositing and SDF shapes (Star, Capsule, Arc).
  2. In the main function, calculate the base SDF for the puffy cartoon star.
  3. Use an outer-stroke technique to generate a thick, clean outline.
  4. Calculate SDFs for the facial features (vertical oval eyes, curved U-mouth).
  5. Create a stylized, curved glossy highlight composed of an arc and a detached dot.
  6. Composite all elements chronologically: Outline -> Star Fill -> Face -> Glossy Highlight.
*/

#ifndef PI
#define PI 3.14159265359
#endif

// Alpha blending helper (Src Over Dst)
#ifndef NM_OVER_HELPER
#define NM_OVER_HELPER
inline float4 nm_over(float4 src, float4 dst) {
    float a = src.a + dst.a * (1.0 - src.a);
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-8);
    return float4(c, a);
}
#endif

// Signed distance to a 5-point star
#ifndef SD_STAR5_HELPER
#define SD_STAR5_HELPER
inline float sdStar5(float2 p, float r, float rf) {
    const float2 k1 = float2(0.809016994375, -0.587785252292); // cos/sin 36 deg
    const float2 k2 = float2(-k1.x, k1.y);
    p.x = abs(p.x);
    p -= 2.0 * max(dot(k1, p), 0.0) * k1;
    p -= 2.0 * max(dot(k2, p), 0.0) * k2;
    p.x = abs(p.x);
    p.y -= r;
    float2 ba = rf * float2(-k1.y, k1.x) - float2(0, 1);
    float h = clamp(dot(p, ba) / dot(ba, ba), 0.0, r);
    return length(p - ba * h) * sign(p.y * ba.x - p.x * ba.y);
}
#endif

// Signed distance to a capsule (used for eyes)
#ifndef SD_CAPSULE_HELPER
#define SD_CAPSULE_HELPER
inline float sdCapsule(float2 p, float2 a, float2 b, float r) {
    float2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h) - r;
}
#endif

// Signed distance to an upward arc (used for glossy highlight)
#ifndef SD_ARC_UP_HELPER
#define SD_ARC_UP_HELPER
inline float sdArcUP(float2 p, float aperture, float ra, float rb) {
    p.x = abs(p.x);
    float2 sc = float2(sin(aperture), cos(aperture));
    float d = (sc.y * p.x > sc.x * p.y) ? length(p - ra * sc) : abs(length(p) - ra);
    return d - rb;
}
#endif

// Signed distance to a downward arc (used for U-shaped mouth)
#ifndef SD_ARC_DOWN_HELPER
#define SD_ARC_DOWN_HELPER
inline float sdArcDOWN(float2 p, float aperture, float ra, float rb) {
    p.y = -p.y; // invert Y to point down
    p.x = abs(p.x);
    float2 sc = float2(sin(aperture), cos(aperture));
    float d = (sc.y * p.x > sc.x * p.y) ? length(p - ra * sc) : abs(length(p) - ra);
    return d - rb;
}
#endif

void CartoonStarShape_float(
    float2 UV,
    float BodyRadius,
    float BodyInnerRadius,
    float BodyRoundness,
    float StarRotation,
    float4 StarColor,
    float OutlineWidth,
    float4 OutlineColor,
    float4 FaceColor,
    float EyeSpread,
    float2 EyeOffset,
    float2 EyeSize,
    float2 MouthOffset,
    float MouthRadius,
    float MouthThickness,
    float MouthAperture,
    float2 GlossyPos,
    float GlossyRadius,
    float GlossyAngle,
    float GlossyAperture,
    float GlossyThickness,
    float GlossyDotOffset,
    float4 GlossyColor,
    out float4 outColor
) {
    // Center UVs to (0,0)
    float2 p = UV - 0.5;
    
    // Screen-space analytic anti-aliasing width
    float aa = length(fwidth(p));
    aa = max(aa, 0.001);

    // --- 1. Base Star & Outline ---
    float c_star = cos(StarRotation);
    float s_star = sin(StarRotation);
    float2 p_star = float2(c_star * p.x + s_star * p.y, -s_star * p.x + c_star * p.y);
    
    // Generate sharp star and apply inflation for a puffy, rounded appearance
    float d_star_base = sdStar5(p_star, max(BodyRadius, 0.001), max(BodyInnerRadius, 0.0));
    float d_star = d_star_base - BodyRoundness;
    
    float fillMask = 1.0 - smoothstep(-aa, aa, d_star);
    // Outline extends outwards from the star boundary
    float outlineMask = 1.0 - smoothstep(-aa, aa, d_star - OutlineWidth);
    
    // --- 2. Kawaii Face (Eyes & Mouth) ---
    // Symmetric capsule eyes
    float2 p_eyes = p - EyeOffset;
    p_eyes.x = abs(p_eyes.x) - EyeSpread;
    float d_eyes = sdCapsule(p_eyes, float2(0.0, -EyeSize.y), float2(0.0, EyeSize.y), EyeSize.x);
    
    // U-shaped curved mouth
    float2 p_mouth = p - MouthOffset;
    float d_mouth = sdArcDOWN(p_mouth, MouthAperture, MouthRadius, MouthThickness);
    
    float faceMask = 1.0 - smoothstep(-aa, aa, min(d_eyes, d_mouth));
    
    // --- 3. Glossy Highlight (Arc + Detached Dot) ---
    float2 p_gl = p - GlossyPos;
    float c_gl = cos(GlossyAngle);
    float s_gl = sin(GlossyAngle);
    p_gl = float2(c_gl * p_gl.x + s_gl * p_gl.y, -s_gl * p_gl.x + c_gl * p_gl.y);
    
    // Main curved stripe
    float d_gl_arc = sdArcUP(p_gl, GlossyAperture, GlossyRadius, GlossyThickness);
    
    // Tiny detached dot positioned slightly below the left end of the arc
    float dot_angle = GlossyAperture + GlossyDotOffset;
    float2 dot_pos = float2(-sin(dot_angle) * GlossyRadius, cos(dot_angle) * GlossyRadius);
    float d_gl_dot = length(p_gl - dot_pos) - GlossyThickness;
    
    float d_glossy = min(d_gl_arc, d_gl_dot);
    float glossyAlpha = 1.0 - smoothstep(-aa, aa, d_glossy);
    // Soft clip highlight to remain strictly inside the star body
    glossyAlpha *= fillMask; 
    
    // --- 4. Composition (Painter's Algorithm) ---
    float4 col = float4(0.0, 0.0, 0.0, 0.0);
    
    float4 layerOutline = float4(OutlineColor.rgb, OutlineColor.a * outlineMask);
    col = nm_over(layerOutline, col);
    
    float4 layerFill = float4(StarColor.rgb, StarColor.a * fillMask);
    col = nm_over(layerFill, col);
    
    float4 layerFace = float4(FaceColor.rgb, FaceColor.a * faceMask);
    col = nm_over(layerFace, col);
    
    float4 layerGlossy = float4(GlossyColor.rgb, GlossyColor.a * glossyAlpha);
    col = nm_over(layerGlossy, col);
    
    outColor = col;
}
