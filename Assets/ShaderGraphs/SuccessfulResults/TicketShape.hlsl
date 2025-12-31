#ifndef PI
#define PI 3.14159265359
#endif

// Helper: Signed Distance to a Box
inline float nm_sdBox(float2 p, float2 b) {
    float2 q = abs(p) - b;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
}

// Helper: Alpha Blending (Src Over Dst) for Straight Alpha
inline float4 nm_over(float4 src, float4 dst) {
    float a = src.a + dst.a * (1.0 - src.a);
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-8);
    return float4(c, a);
}

// PLAN:
// 1. Recenter UVs to create a local coordinate system.
// 2. Define the base rectangular body using a Box SDF.
// 3. Define the corner cutouts by calculating the distance to the box corners (using symmetry).
// 4. Combine shapes: Box minus Cutouts (using max(box, -cutout)).
// 5. Compute Anti-Aliasing (AA) width using fwidth.
// 6. Compute Fill and Outline coverage masks.
// 7. Composite Outline over Fill and return.

void TicketShape_float(float2 UV, float Width, float Height, float CutoutRadius, float2 Center, float4 FillColor, float4 OutlineColor, float OutlineThickness, out float4 OutColor) {
    // 1. Setup coordinates (centered)
    float2 p = UV - Center;

    // 2. Define Dimensions
    // Use half-dimensions for SDF calculations
    float2 halfSize = float2(max(Width, 0.0), max(Height, 0.0)) * 0.5;

    // 3. Base Rectangle SDF
    float dBox = nm_sdBox(p, halfSize);

    // 4. Corner Cutouts SDF
    // The cutouts are circles subtracted from the four corners.
    // We work in the first quadrant (abs(p)) to handle all 4 corners symmetrically.
    float2 q = abs(p);
    
    // Clamp radius to prevent self-intersection artifacts if radius > size
    float maxR = min(halfSize.x, halfSize.y);
    float r = clamp(CutoutRadius, 0.0, maxR);
    
    // Calculate distance from the corner vertex (which is at 'halfSize' in the 1st quadrant)
    float distToCorner = length(q - halfSize);
    
    // The cutout is a circle centered on the corner vertex.
    // SDF for circle: distance - radius.
    float dCutoutCircle = distToCorner - r;
    
    // Boolean Subtraction: Shape = Box - Circle
    // SDF Formula: max(dBase, -dSubtract)
    float d = max(dBox, -dCutoutCircle);

    // 5. Anti-aliasing
    float aa = fwidth(d);
    aa = max(aa, 0.001); // Safety clamp for preview windows

    // 6. Fill Logic
    // d < 0 inside the shape
    float fillMask = 1.0 - smoothstep(0.0, aa, d);
    // Construct Fill Layer (Straight Alpha)
    float4 fillLayer = float4(FillColor.rgb, FillColor.a * fillMask);

    // 7. Outline Logic
    // Outline is a band centered on the shape edge (d=0)
    float halfThick = max(OutlineThickness, 0.0) * 0.5;
    float dOutline = abs(d) - halfThick;
    float outlineMask = 1.0 - smoothstep(0.0, aa, dOutline);
    // Construct Outline Layer
    float4 outlineLayer = float4(OutlineColor.rgb, OutlineColor.a * outlineMask);

    // 8. Composite
    // Draw Outline OVER Fill
    OutColor = nm_over(outlineLayer, fillLayer);
}