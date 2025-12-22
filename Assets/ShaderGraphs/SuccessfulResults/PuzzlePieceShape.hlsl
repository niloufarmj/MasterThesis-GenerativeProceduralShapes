#ifndef PI
#define PI 3.14159265359
#endif

// SDF for a box
float pp_sdBox(float2 p, float2 b) {
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// Smooth Minimum (Polynomial)
float pp_smin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / max(k, 0.0001), 0.0, 1.0);
    return lerp(b, a, h) - k * h * (1.0 - h);
}

// Smooth Maximum (Polynomial) - used for subtraction
float pp_smax(float a, float b, float k) {
    return -pp_smin(-a, -b, k);
}

// Customizable Puzzle Piece Shape with adjustable bumps
void PuzzlePieceShape_float(float2 UV, float Size, float BumpRadius, float BumpRoundness,
                            float TopType, float TopOffset,
                            float RightType, float RightOffset,
                            float BottomType, float BottomOffset,
                            float LeftType, float LeftOffset,
                            float4 Color,
                            out float4 outColor)
{
    // PLAN:
    // 1. Center UV coordinates at (0.5, 0.5).
    // 2. Define a base square (Box SDF).
    // 3. For each side (Top, Right, Bottom, Left):
    //    - Determine if there is a bump (Type != 0).
    //    - Calculate position of the bump (Circle SDF) based on Offset and In/Out type.
    //    - If Type > 0 (Outer), use Smooth Union (smin).
    //    - If Type < 0 (Inner), use Smooth Subtraction (smax).
    // 4. Apply anti-aliasing and output color.

    float2 p = UV - 0.5;
    float halfSize = max(Size, 0.001);
    float r = max(BumpRadius, 0.001);
    float k = max(BumpRoundness, 0.001);

    // Base Shape: Square
    float d = pp_sdBox(p, float2(halfSize, halfSize));

    // Shift determines how much the bump circle overlaps the edge
    // Positive shift moves center outwards (for Tabs), Negative implies inwards logic
    // We position the circle center such that it connects with a 'neck'.
    float shift = r * 0.7;

    // --- TOP EDGE ---
    // Normal (0, 1), Edge at y = halfSize
    int tTop = (int)round(TopType);
    if (tTop != 0) {
        // If Outer (1), move circle UP (+shift). If Inner (-1), move circle DOWN (-shift) relative to edge?
        // Actually, for Inner (Slot), we want to subtract a shape that mirrors the Outer (Tab).
        // So the shape to subtract is also positioned 'outside' the inner volume relative to the cut, 
        // effectively diving in. Wait, to cut a hole, the circle must be INSIDE.
        // Correct logic: 
        // Outer: Center outside box. Union.
        // Inner: Center inside box. Subtract.
        float s = (tTop > 0) ? shift : -shift;
        float2 c = float2(TopOffset * halfSize, halfSize + s);
        float dC = length(p - c) - r;
        
        if (tTop > 0) d = pp_smin(d, dC, k);
        else d = pp_smax(d, -dC, k);
    }

    // --- RIGHT EDGE ---
    // Normal (1, 0), Edge at x = halfSize
    int tRight = (int)round(RightType);
    if (tRight != 0) {
        float s = (tRight > 0) ? shift : -shift;
        float2 c = float2(halfSize + s, RightOffset * halfSize);
        float dC = length(p - c) - r;
        
        if (tRight > 0) d = pp_smin(d, dC, k);
        else d = pp_smax(d, -dC, k);
    }

    // --- BOTTOM EDGE ---
    // Normal (0, -1), Edge at y = -halfSize
    int tBot = (int)round(BottomType);
    if (tBot != 0) {
        float s = (tBot > 0) ? shift : -shift;
        float2 c = float2(BottomOffset * halfSize, -halfSize - s);
        float dC = length(p - c) - r;
        
        if (tBot > 0) d = pp_smin(d, dC, k);
        else d = pp_smax(d, -dC, k);
    }

    // --- LEFT EDGE ---
    // Normal (-1, 0), Edge at x = -halfSize
    int tLeft = (int)round(LeftType);
    if (tLeft != 0) {
        float s = (tLeft > 0) ? shift : -shift;
        float2 c = float2(-halfSize - s, LeftOffset * halfSize);
        float dC = length(p - c) - r;
        
        if (tLeft > 0) d = pp_smin(d, dC, k);
        else d = pp_smax(d, -dC, k);
    }

    // Anti-aliasing
    float aa = fwidth(d);
    float edge = 1.0 - smoothstep(-aa, aa, d);

    outColor = float4(Color.rgb * edge, Color.a * edge);
}

// ------------------------------------------------------------------------
//  Visual Result (High-level, parameter-invariant description)
// ------------------------------------------------------------------------
//  This function generates a **stylized 2D puzzle-piece-like primitive**
//  using Signed Distance Functions (SDFs).
//
//  The shape is based on a square body with optional circular protrusions
//  or indentations (tabs and slots) on each of its four sides, forming a
//  classic jigsaw puzzle silhouette. The size of the base shape, the
//  presence, direction, position, and roundness of each side feature,
//  as well as color and placement, are fully controlled by input
//  parameters and are not fixed by the function itself.
//
//  The output is an anti-aliased RGBA color suitable for icons,
//  game UI elements, educational graphics, symbolic visuals,
//  and expressive procedural 2D shapes.
// ------------------------------------------------------------------------
