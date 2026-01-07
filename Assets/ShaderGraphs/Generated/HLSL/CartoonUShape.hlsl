#ifndef PI
#define PI 3.14159265359
#endif

// Helper: Signed distance to a 2D line segment
float sdSegment(float2 p, float2 a, float2 b) {
    float2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}

// Helper: Alpha blending (Source Over Destination)
float4 over(float4 src, float4 dst) {
    float a = src.a + dst.a * (1.0 - src.a);
    // Guard division by zero
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-6);
    return float4(c, a);
}

// Main Function: Cartoon U Shape
// User Request: A cartoon letter U shape with adjustable size, color, center, thickness, curvature,
// outline with editable color and thickness, and dynamic corner radius for edges (tips).
void CartoonUShape_float(float2 UV, float Size, float2 Center, float4 Color, float Thickness, float Curvature, float EdgeRadius, float4 OutlineColor, float OutlineWidth, out float4 outColor) {
    // PLAN:
    // 1) Center and scale UVs. Use symmetry (abs(x)) to model just the right half.
    // 2) Define a "Skeleton" for the U: A vertical line, a bottom horizontal line, and a connecting arc.
    // 3) Curvature parameter controls the radius of the bottom arc.
    // 4) Compute SDF to the skeleton. Subtract Thickness to create the body.
    // 5) Handle "EdgeRadius" (Tips): Blend between a flat top and a round top based on parameter.
    // 6) Compute Outline SDF based on the body SDF.
    // 7) Anti-alias and composite using standard alpha blending.

    // 1. Coordinates
    float2 p = UV - Center;
    float s = max(Size, 0.001); // Avoid div by zero
    p /= s;
    
    // 2. Shape Parameters
    // Define intrinsic dimensions of the U in normalized space
    float w = 0.25;  // Half-width
    float h = 0.4;   // Half-height
    float th = max(Thickness * 0.1, 0.001); // Stroke thickness
    
    // Curvature: 0 = Box U, 1 = Round Bottom U
    float r_bot = clamp(Curvature, 0.0, 1.0) * w;
    
    // Symmetry: Work on the right side only
    p.x = abs(p.x);
    
    // 3. Skeleton SDF Calculation
    float d_skel = 1e5;
    
    // Segment A: Vertical Leg (Right side)
    // Starts where the bottom curve ends, goes up to the top.
    // We treat the top cap separately later, so just define the spine.
    float2 vStart = float2(w, -h + r_bot);
    float2 vEnd   = float2(w, h);
    float d_vert = sdSegment(p, vStart, vEnd);
    
    // Segment B: Bottom Horizontal (if not fully round)
    float d_bot = 1e5;
    if (r_bot < w - 0.001) {
        d_bot = sdSegment(p, float2(0.0, -h), float2(w - r_bot, -h));
    }
    
    // Segment C: Bottom Corner Arc
    // Connects Vertical Leg to Bottom Horizontal
    float d_arc = 1e5;
    float2 arcCenter = float2(w - r_bot, -h + r_bot);
    float2 diff = p - arcCenter;
    // Only consider the arc distance if we are in the bottom-right corner quadrant relative to the arc center
    // Otherwise, the segments handle the closest point.
    if (diff.x > 0.0 && diff.y < 0.0) {
        d_arc = abs(length(diff) - r_bot);
    }
    
    // Combine skeleton distances
    d_skel = min(d_vert, min(d_bot, d_arc));
    
    // 4. Create Body Shape (Skeleton expanded by thickness)
    float d_shape = d_skel - th;
    
    // 5. Tip Roundness Logic (EdgeRadius)
    // Default SDF (d_shape) gives perfectly round caps (radius = th).
    // We want to flatten the top if EdgeRadius < 1.
    if (p.y > h) {
        float dx = abs(p.x - w);
        float dy = p.y - h;
        
        // Distance for a Round Cap (Standard)
        float d_round = length(float2(dx, dy)) - th;
        
        // Distance for a Flat Cap (Box-like)
        // We intersect the vertical strip with a flat top.
        // Distance is max of x-dist-th and y-dist.
        float d_flat = max(dx - th, dy);
        
        // Blend based on user preference
        d_shape = lerp(d_flat, d_round, clamp(EdgeRadius, 0.0, 1.0));
    }
    
    // 6. Outline SDF
    // Centered outline around the main shape edge
    float outW = max(OutlineWidth * 0.05, 0.0);
    float d_outline = abs(d_shape) - outW;
    
    // 7. Rendering / Anti-Aliasing
    float aa = fwidth(d_shape);
    // Use a small constant fallback if fwidth is zero (e.g. preview windows sometimes)
    aa = max(aa, 0.001);
    
    // Fill Mask (Inverse SDF: <0 is inside)
    float fillAlpha = 1.0 - smoothstep(-aa, aa, d_shape);
    float4 fillColor = float4(Color.rgb, Color.a * fillAlpha);
    
    // Outline Mask
    float outlineAlpha = 1.0 - smoothstep(-aa, aa, d_outline);
    float4 strokeColor = float4(OutlineColor.rgb, OutlineColor.a * outlineAlpha);
    
    // Composite: Stroke drawn OVER Fill
    outColor = over(strokeColor, fillColor);
}