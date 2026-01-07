#ifndef PI
#define PI 3.14159265359
#endif

// ----------------------------------------------------------------------------------
// Helper Functions
// ----------------------------------------------------------------------------------

// Blend two colors using standard source-over-destination alpha blending
float4 nm_over(float4 src, float4 dst)
{
    float a = src.a + dst.a * (1.0 - src.a);
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-8);
    return float4(c, a);
}

// Signed Distance to a Box with rounded corners
// p: point, b: half-extents, r: corner radius
float nm_sdRoundBox(float2 p, float2 b, float r)
{
    float2 q = abs(p) - b + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

// Signed Distance to an Oriented Box (Line segment with thickness and rounded corners)
// a: start point, b: end point, th: total thickness, r: corner radius
float nm_sdOrientedBox(float2 p, float2 a, float2 b, float th, float r)
{
    float l = length(b - a);
    float2 d = (b - a) / max(l, 0.0001); // direction unit vector
    
    // Transform p to local space of the segment
    float2 q = p - (a + b) * 0.5;
    // Rotate -d.y, d.x is perpendicular
    q = float2(d.x * q.x + d.y * q.y, -d.y * q.x + d.x * q.y);
    
    // Half-extents: x is half-length, y is half-thickness
    float2 halfSize = float2(l * 0.5, th * 0.5);
    
    // Clamp radius to fit within the box (cannot exceed half-thickness)
    float r_clamped = min(r, min(halfSize.x, halfSize.y));
    
    return nm_sdRoundBox(q, halfSize, r_clamped);
}

// ----------------------------------------------------------------------------------
// Main Function: Cartoon Number 4
// ----------------------------------------------------------------------------------
// A thick, cartoon-style number 4 with adjustable dimensions, thickness, and outline.
void CartoonNumberFour_float(float2 UV, float Width, float Height, float Thickness, float CornerRadius, float4 FillColor, float4 OutlineColor, float OutlineWidth, float Size, out float4 outColor)
{
    // PLAN:
    // 1. Center coordinates at (0.5, 0.5).
    // 2. Define the skeleton of the '4' (Stem, Crossbar, Diagonal) scaled by Size.
    // 3. Generate 3 Oriented Box SDFs with rounded corners.
    // 4. Combine SDFs using min() for a unified, connected shape.
    // 5. Calculate anti-aliased Fill and Outline masks.
    // 6. Composite Outline over Fill using correct alpha blending.

    // 1. Coordinates
    float2 p = UV - 0.5;

    // Apply Size Scaling
    float s = max(Size, 0.001);
    float w = Width * s;
    float h = Height * s;
    float th = Thickness * s;
    float r = CornerRadius * s;
    
    // 2. Skeleton Geometry
    // Vertical Stem: Aligned slightly to the right for balance
    float x_stem = w * 0.25;
    float2 v_top = float2(x_stem, h * 0.5);
    float2 v_bot = float2(x_stem, -h * 0.5);
    
    // Horizontal Bar: Crosses the stem, slightly below center
    float y_bar = -h * 0.1;
    float2 h_left = float2(-w * 0.5, y_bar);
    float2 h_right = float2(w * 0.5, y_bar); // Extends past stem
    
    // Diagonal: Connects Top of Vertical to Start of Horizontal
    // Sharing points ensures perfect closure of the top triangle
    float2 d_start = v_top;
    float2 d_end = h_left;
    
    // 3. SDF Generation
    // Use OrientedBox for uniform thickness even at angles
    float dVert = nm_sdOrientedBox(p, v_top, v_bot, th, r);
    float dHorz = nm_sdOrientedBox(p, h_left, h_right, th, r);
    float dDiag = nm_sdOrientedBox(p, d_start, d_end, th, r);
    
    // 4. Union (Smooth merge of internal geometry, though visually convex union is min)
    float dist = min(dVert, min(dHorz, dDiag));
    
    // 5. Rendering
    float aa = fwidth(dist);
    
    // Fill Mask (Inside shape)
    float fillMask = 1.0 - smoothstep(-aa, 0.0, dist);
    
    // Outline Mask (Centered on edge)
    float sw = OutlineWidth * s;
    float halfStroke = sw * 0.5;
    float strokeDist = abs(dist) - halfStroke;
    float strokeMask = 1.0 - smoothstep(-aa, 0.0, strokeDist);
    
    // 6. Composition
    float4 fillLayer = float4(FillColor.rgb, FillColor.a * fillMask);
    float4 strokeLayer = float4(OutlineColor.rgb, OutlineColor.a * strokeMask);
    
    // Composite Stroke OVER Fill to ensure clean edges
    outColor = nm_over(strokeLayer, fillLayer);
}