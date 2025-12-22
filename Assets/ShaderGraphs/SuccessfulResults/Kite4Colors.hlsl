#ifndef PI
#define PI 3.14159265359
#endif

// Helper: Calculate squared distance to a segment
// Handles degenerate segments (length 0) gracefully via epsilon
float nm_distSqSegment(float2 p, float2 a, float2 b) {
    float2 pa = p - a, ba = b - a;
    float lenSq = dot(ba, ba);
    float h = saturate(dot(pa, ba) / max(lenSq, 1e-8));
    float2 d = pa - ba * h;
    return dot(d, d);
}

// Helper: Exact SDF for a Convex Polygon with 4 vertices
// Returns negative inside, positive outside
float nm_sdConvexPoly4(float2 p, float2 v0, float2 v1, float2 v2, float2 v3) {
    float2 v[4] = { v0, v1, v2, v3 };
    float minDSq = 1e20;
    float maxSignedDist = -1e20;
    
    [unroll]
    for (int i = 0; i < 4; ++i) {
        float2 a = v[i];
        float2 b = v[(i + 1) % 4];
        float2 e = b - a;
        
        // Update minimum distance to boundary
        minDSq = min(minDSq, nm_distSqSegment(p, a, b));
        
        // Update half-space sign (using outward normal)
        // Normal of edge (x,y) is (y,-x) for CCW winding
        float2 n = normalize(float2(e.y, -e.x));
        maxSignedDist = max(maxSignedDist, dot(p - a, n));
    }
    
    float dist = sqrt(minDSq);
    return (maxSignedDist > 0.0) ? dist : -dist;
}

void Kite4Colors_float(float2 UV, float Width, float HeightTop, float HeightBottom, float Size, float2 Center, float4 ColorTR, float4 ColorTL, float4 ColorBL, float4 ColorBR, out float4 outColor) {
    // PLAN:
    // 1) Center UVs and scale by Size to get local coordinates (p).
    // 2) Define 4 vertices of the kite based on width/height params.
    // 3) Calculate signed distance (SDF) to the convex kite polygon.
    // 4) Determine internal colors by mixing the 4 input colors based on which quadrant (p.x, p.y) the pixel falls in.
    // 5) Apply smoothstep anti-aliasing to the shape edge and output final color.

    // 1. Coordinates
    float2 p = UV - Center;
    float s = max(Size, 0.0001); // Prevent divide by zero
    p /= s;
    
    // 2. Vertices (Clockwise or CCW? Our Poly function assumes CCW for outward normals)
    // Top=(0,Ht), Left=(-W,0), Bottom=(0,-Hb), Right=(W,0)
    // Let's list them CCW: Right -> Top -> Left -> Bottom
    float w = max(Width, 0.0);
    float ht = max(HeightTop, 0.0);
    float hb = max(HeightBottom, 0.0);
    
    float2 vRight = float2(w, 0.0);
    float2 vTop   = float2(0.0, ht);
    float2 vLeft  = float2(-w, 0.0);
    float2 vBot   = float2(0.0, -hb);
    
    // 3. SDF Calculation
    // Vertices order: Right, Top, Left, Bottom
    float dist = nm_sdConvexPoly4(p, vRight, vTop, vLeft, vBot);
    
    // 4. Anti-Aliasing & Mask
    float aa = fwidth(dist);
    float mask = 1.0 - smoothstep(0.0, aa, dist);
    
    // 5. Internal Color Logic
    // The kite diagonals lie on the X and Y axes of our local 'p' space.
    // We blend the 4 colors based on p.x and p.y for smooth internal seams.
    float seamAA = aa; // Use same AA width for internal seams
    float mixX = smoothstep(-seamAA, seamAA, p.x); // 0 at Left, 1 at Right
    float mixY = smoothstep(-seamAA, seamAA, p.y); // 0 at Bottom, 1 at Top
    
    // Blend Left/Right pairs first
    float4 topColor = lerp(ColorTL, ColorTR, mixX);
    float4 botColor = lerp(ColorBL, ColorBR, mixX);
    
    // Blend Top/Bottom
    float4 finalFill = lerp(botColor, topColor, mixY);
    
    // 6. Final Output
    // Premultiplied alpha-like blending for the mask (or standard transparent setup)
    outColor = float4(finalFill.rgb * mask, finalFill.a * mask);
}

// ------------------------------------------------------------------------
//  Visual Result (High-level, parameter-invariant description)
// ------------------------------------------------------------------------
//  This function generates a **2D kite-shaped primitive with quadrant-based
//  color regions** using Signed Distance Functions (SDFs).
//
//  The shape is a convex kite (diamond-like) silhouette defined by a top
//  point, a bottom point, and symmetric left/right points. The interior
//  of the shape is divided into four regions by its diagonals, allowing
//  each quadrant to be filled with an independent color. The overall
//  proportions, placement, scale, and color assignment are fully
//  controlled by input parameters and are not fixed by the function
//  itself.
//
//  The output is an anti-aliased RGBA color suitable for symbolic icons,
//  educational visuals, color-coded indicators, and expressive procedural
//  2D graphics.
// ------------------------------------------------------------------------
