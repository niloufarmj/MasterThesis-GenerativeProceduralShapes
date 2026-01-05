#ifndef PI
#define PI 3.14159265359
#endif

// Helper: Distance from point p to line segment ab
float sdSegment_U(float2 p, float2 a, float2 b) {
    float2 pa = p - a, ba = b - a;
    float h = saturate(dot(pa, ba) / max(dot(ba, ba), 1e-6));
    return length(pa - ba * h);
}

// Helper: Distance from point p to a 90-degree arc in quadrant IV (0 to -PI/2)
// Center is 'c', radius is 'r'. The arc connects (r,0) and (0,-r) relative to c.
float sdCornerArc_U(float2 p, float2 c, float r) {
    float2 diff = p - c;
    float angle = atan2(diff.y, diff.x);
    // Clamp angle to the arc's range [-PI/2, 0]
    float clampedAngle = clamp(angle, -PI * 0.5, 0.0);
    float2 closest = c + float2(cos(clampedAngle), sin(clampedAngle)) * r;
    return length(p - closest);
}

void LetterUShape_float(float2 UV, float Width, float Height, float Thickness, float Curvature, float4 Color, out float4 outColor) {
    // PLAN:
    // 1) Center the UV coordinates (0,0 at center).
    // 2) Fold space symmetrically (p.x = abs(p.x)) to build the right half of the U.
    // 3) Define the skeleton of the U using 3 parts:
    //    - Vertical Line: straight side extending up.
    //    - Corner Arc: rounded bottom corner.
    //    - Horizontal Line: connects the bottom arcs (if curvature is low).
    // 4) Compute minimum distance to this skeleton.
    // 5) Subtract Thickness to create the outline.
    // 6) Anti-alias and colorize.

    // 1) Center UVs
    float2 p = UV - 0.5;
    
    // Parameters setup
    float halfW = Width * 0.5;
    float h = Height; 
    // Clamp curvature to be valid (radius cannot exceed half width)
    float r = clamp(Curvature, 0.0, 1.0) * halfW;
    float thick = Thickness * 0.5; // Half-thickness for SDF subtraction

    // Center the shape vertically
    // The shape extends from y = -r to y = h.
    // Midpoint is (h - r) / 2.0
    float offsetY = (h - r) * 0.5;
    p.y -= offsetY;

    // 2) Symmetry: fold X axis
    p.x = abs(p.x);

    // 3) Define Geometry Points
    // The arc center is at (halfW - r, 0) relative to the vertical offset
    // Vertical segment starts at (halfW, 0) and goes up to (halfW, h)
    // Horizontal segment starts at (0, -r) and goes to (halfW - r, -r)
    float2 arcCenter = float2(halfW - r, 0.0);
    
    // 4) Calculate Distances to Skeleton Segments
    // Vertical Side
    float d_vert = sdSegment_U(p, float2(halfW, 0.0), float2(halfW, h));
    
    // Bottom Horizontal (connects the two curved corners)
    // If r == halfW (full round), this segment has length 0 and sits at (0, -r)
    float d_horiz = sdSegment_U(p, float2(0.0, -r), float2(halfW - r, -r));
    
    // Corner Arc (connects vertical side to bottom horizontal)
    float d_arc = sdCornerArc_U(p, arcCenter, r);

    // Combine distances (Union of 3 parts)
    float d_skeleton = min(d_vert, min(d_horiz, d_arc));

    // 5) Create outline by subtracting thickness
    // SDF is negative inside the stroke, positive outside
    float dist = d_skeleton - thick;

    // 6) Anti-aliasing
    float edge = smoothstep(0.005, -0.005, dist);

    // Output color
    outColor = float4(Color.rgb * edge, Color.a * edge);
}