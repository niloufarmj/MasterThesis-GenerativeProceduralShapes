#ifndef PI
#define PI 3.14159265359
#endif

// --- Helper Functions ---

// Circle SDF
float grapes_sdCircle(float2 p, float r) {
    return length(p) - r;
}

// Segment SDF (for stem)
float grapes_sdSegment(float2 p, float2 a, float2 b, float thickness) {
    float2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h) - thickness;
}

// 2D Rotation Helper
float2 grapes_rotate(float2 p, float angle) {
    float c = cos(angle);
    float s = sin(angle);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

// Simple Leaf SDF (Vesica: intersection of two offset circles)
float grapes_sdLeaf(float2 p, float size) {
    // A leaf shape formed by two intersecting circles
    float r = size * 0.8;
    float offset = size * 0.45;
    // Left and Right circles
    float c1 = length(p - float2(-offset, 0.0)) - r;
    float c2 = length(p - float2(offset, 0.0)) - r;
    // Intersection = max
    return max(c1, c2);
}

// --- Main Function ---
// Generates a bunch of grapes (circles) with a stem and a leaf on top.
void GrapesWithLeaf_float(float2 UV, float Size, float GrapeSize, float LeafSize, float4 GrapeColor, float4 LeafColor, out float4 outColor) {
    // PLAN:
    // 1) Center and scale UV coordinates to create a local metric space.
    // 2) Construct the grape cluster using a hard union (min) of 6 circles in a pyramid.
    // 3) Construct a stem and leaf positioned above the grapes.
    // 4) Combine the two major shapes (grapes vs foliage) and determining color.
    // 5) Apply analytic anti-aliasing and output.

    // 1. Setup Coordinates
    // Map UV [0,1] to [-1,1] then scale by Size
    float2 p = (UV - 0.5) * 2.0;
    p /= max(Size, 0.0001);

    // 2. Grapes Configuration
    // Define layout parameters
    float r = max(GrapeSize, 0.01);
    float spacing = r * 1.8; // Packing density
    float rowHeight = spacing * 0.866; // Sqrt(3)/2 for hex packing
    
    // Offset the cluster center downwards so the leaf has room on top
    float2 grapeCenter = float2(0.0, -0.2);
    float2 gp = p - grapeCenter;

    // 3. Grapes SDF (3-2-1 Pyramid)
    float dGrapes = 1e9;
    
    // Row 1 (Top): 3 grapes
    dGrapes = min(dGrapes, grapes_sdCircle(gp - float2(-spacing, rowHeight), r));
    dGrapes = min(dGrapes, grapes_sdCircle(gp - float2(0.0, rowHeight), r));
    dGrapes = min(dGrapes, grapes_sdCircle(gp - float2(spacing, rowHeight), r));
    
    // Row 2 (Middle): 2 grapes
    dGrapes = min(dGrapes, grapes_sdCircle(gp - float2(-spacing * 0.5, 0.0), r));
    dGrapes = min(dGrapes, grapes_sdCircle(gp - float2(spacing * 0.5, 0.0), r));
    
    // Row 3 (Bottom): 1 grape
    dGrapes = min(dGrapes, grapes_sdCircle(gp - float2(0.0, -rowHeight), r));

    // 4. Foliage (Stem + Leaf) SDF
    // Stem connects top-middle grape to leaf
    float2 stemStart = grapeCenter + float2(0.0, rowHeight + r * 0.8);
    float2 stemEnd = stemStart + float2(0.05, 0.3);
    float dStem = grapes_sdSegment(p, stemStart, stemEnd, 0.03);

    // Leaf positioned at end of stem
    float2 leafPos = stemEnd;
    float2 lp = p - leafPos;
    lp = grapes_rotate(lp, -0.6); // Rotate ~35 degrees
    float dLeafBody = grapes_sdLeaf(lp, max(LeafSize, 0.01));

    // Union Stem and Leaf
    float dFoliage = min(dStem, dLeafBody);

    // 5. Final Composition
    float dFinal = min(dGrapes, dFoliage);
    
    // Color Logic: Determine if pixel is closer to Grapes or Foliage
    // step(a, b) returns 1.0 if a <= b. 
    // If dGrapes <= dFoliage, we use GrapeColor. 
    float isGrape = step(dGrapes, dFoliage);
    float4 finalColor = lerp(LeafColor, GrapeColor, isGrape);

    // 6. Anti-Aliasing
    // Use fwidth for pixel-perfect AA width, clamped to avoid artifacts
    float aaWidth = max(fwidth(dFinal), 0.001);
    float alpha = 1.0 - smoothstep(-aaWidth, aaWidth, dFinal);

    // Output
    outColor = float4(finalColor.rgb * alpha, alpha);
}