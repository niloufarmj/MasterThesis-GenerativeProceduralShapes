#ifndef PI
#define PI 3.14159265359
#endif

// --- Helpers ---

// Straight-alpha blending (Source Over Destination)
float4 ghost_over(float4 src, float4 dst) {
    float a = src.a + dst.a * (1.0 - src.a);
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-8);
    return float4(c, a);
}

// Signed Distance to an Ellipse (Approximation)
// p: point relative to center, ab: half-width and half-height
float sdGhostEllipse(float2 p, float2 ab) {
    float a = max(ab.x, 1e-8);
    float b = max(ab.y, 1e-8);
    float aa = a * a;
    float bb = b * b;
    float F = (p.x * p.x) / aa + (p.y * p.y) / bb - 1.0;
    float gradLen = 2.0 * sqrt((p.x * p.x) / (aa * aa) + (p.y * p.y) / (bb * bb));
    return (gradLen > 1e-8) ? (F / gradLen) : -min(a, b);
}

// Signed Distance to a Box with varying corner radii
// p: point, b: half-extents
// r: float4(TopRight, BottomRight, TopLeft, BottomLeft) radii
float sdGhostRoundedBox(float2 p, float2 b, float4 r) {
    r.xy = (p.x > 0.0) ? r.xy : r.zw;
    r.x  = (p.y > 0.0) ? r.x  : r.y;
    float2 q = abs(p) - b + r.x;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r.x;
}

// --- Main Function ---
// Generates a cartoon ghost with rounded head, wavy hem, eyes, and folds.
void CartoonGhostShape_float(
    float2 UV,
    float Width,
    float Height,
    float TopRoundness,
    float WaveFreq,
    float WaveAmp,
    float2 EyeSize,
    float EyeSpacing,
    float EyeVPos,
    float FoldLength,
    float StrokeThickness,
    float4 BodyColor,
    float4 EyeColor,
    float4 StrokeColor,
    out float4 outColor)
{
    // PLAN:
    // 1. Center UV coordinates to (0,0).
    // 2. Define Body SDF: A box with rounded top corners, cut at the bottom by a sine wave.
    // 3. Define Eye SDF: Two symmetrical ellipses on the face.
    // 4. Calculate Fold Mask: Vertical shadows starting from the wave valleys.
    // 5. Composite layers: Body Fill (with folds) -> Eyes -> Stroke -> Output.

    float2 p = UV - 0.5;
    float aa = fwidth(length(p)); // Pixel-based anti-aliasing width

    // --- 1. Body SDF ---
    // Box dimensions: We extend the box height downwards slightly (by WaveAmp)
    // to ensure the wave function cleanly cuts the bottom edge.
    float2 boxSize = float2(Width * 0.5, Height * 0.5 + WaveAmp * 1.5);
    
    // Top rounding: Clamped so it doesn't exceed half-width (to avoid artifacts)
    float rTop = clamp(TopRoundness, 0.0, boxSize.x);
    // Radii vector: Top-Right, Bottom-Right (0), Top-Left, Bottom-Left (0)
    float4 radii = float4(rTop, 0.0, rTop, 0.0);
    
    // Base Rounded Box SDF
    float d_box = sdGhostRoundedBox(p, boxSize, radii);
    
    // Wavy Bottom Cut
    // The bottom edge is defined by: y = -Height/2 + sin(x * freq) * amp
    // Inside the ghost is y > bottom_edge.
    // SDF for the cut plane (negative inside): -(p.y - bottom_edge)
    float waveVal = sin(p.x * WaveFreq) * WaveAmp;
    float bottomEdgeY = -Height * 0.5 + waveVal;
    float d_cut = -(p.y - bottomEdgeY);
    
    // Intersection: Max of Box SDF and Cut Plane SDF
    float d_body = max(d_box, d_cut);

    // --- 2. Eye SDF ---
    float2 p_eyes = p;
    p_eyes.x = abs(p_eyes.x); // Symmetry for left/right eyes
    // Position eyes relative to center. EyeVPos is offset upwards/downwards.
    p_eyes -= float2(EyeSpacing * 0.5, EyeVPos);
    float d_eyes = sdGhostEllipse(p_eyes, EyeSize);

    // --- 3. Folds (Shading Detail) ---
    // Folds appear at wave valleys (sin = -1). Map sin(-1..1) to intensity 1..0.
    // smoothstep creates a soft mask focusing on the valleys.
    float foldBase = smoothstep(0.0, -1.0, sin(p.x * WaveFreq));
    // Fade the folds as they go up the body
    float distFromBottom = p.y - bottomEdgeY;
    float foldFade = 1.0 - smoothstep(0.0, max(FoldLength, 1e-4), distFromBottom);
    float foldMask = foldBase * foldFade;

    // --- 4. Composition ---
    
    // Body Fill Layer
    float alphaBody = 1.0 - smoothstep(0.0, aa, d_body);
    // Apply folds as a darken multiply effect on the body color
    float3 bodyRGB = BodyColor.rgb * (1.0 - foldMask * 0.3);
    float4 layerBody = float4(bodyRGB, alphaBody * BodyColor.a);
    
    // Eye Layer
    float alphaEyes = 1.0 - smoothstep(0.0, aa, d_eyes);
    // Clip eyes to the body shape so they wrap/cut nicely if they touch the edge
    alphaEyes *= alphaBody; 
    float4 layerEyes = float4(EyeColor.rgb, alphaEyes * EyeColor.a);
    
    // Composite Eyes OVER Body
    float4 compositeBody = ghost_over(layerEyes, layerBody);
    
    // Stroke Layer
    // Stroke is centered on the body edge. 
    float halfStroke = StrokeThickness * 0.5;
    float d_stroke = abs(d_body) - halfStroke;
    float alphaStroke = 1.0 - smoothstep(0.0, aa, d_stroke);
    float4 layerStroke = float4(StrokeColor.rgb, alphaStroke * StrokeColor.a);
    
    // Composite Stroke OVER (Eyes + Body)
    outColor = ghost_over(layerStroke, compositeBody);
}

// ------------------------------------------------------------------------
//  Visual Result
// ------------------------------------------------------------------------
//  This function generates a **stylized cartoon ghost** using 
//  Signed Distance Functions (SDFs).
//
//  The visual result is composed of:
//  - A main body formed by a rounded box, featuring a smooth, semi-circular
//    head and straight vertical sides.
//  - A distinctive ruffled bottom edge ("hem") created by subtracting a 
//    sine wave from the body's base.
//  - Two symmetrical, elliptical eyes positioned on the upper face.
//  - Soft vertical shading (folds) that extends upwards from the wave valleys
//    to simulate draped cloth.
//
//  The shape features adjustable parameters for the wave frequency and amplitude
//  (controlling the "ruffle"), eye placement, and the length of the cloth folds.
//
//  A uniform, high-contrast stroke surrounds the body silhouette.
//  The rendering includes anti-aliased edges and alpha blending, making it
//  ideal for Halloween-themed icons, 2D arcade enemies, or spooky UI sprites.
// ------------------------------------------------------------------------