#ifndef PI
#define PI 3.14159265359
#endif

// --- Helper Functions ---

// Exact SDF to a segment AB
float sdSegment_Kite(float2 p, float2 a, float2 b)
{
    float2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}

// Exact SDF to a convex quadrilateral (CCW order)
// Returns negative inside, positive outside
float sdConvexPoly4_Kite(float2 p, float2 v0, float2 v1, float2 v2, float2 v3)
{
    float2 v[4] = { v0, v1, v2, v3 };
    float d2 = 1e20;
    float s = -1e20;
    
    [unroll]
    for (int i = 0; i < 4; ++i)
    {
        float2 a = v[i];
        float2 b = v[(i + 1) & 3];
        
        // Distance to edge
        float sdE = sdSegment_Kite(p, a, b);
        d2 = min(d2, sdE * sdE);
        
        // Signed distance to edge line (outward normal)
        float2 e = b - a;
        float2 n = normalize(float2(e.y, -e.x)); // Right-hand perp (outward for CCW)
        float sEdge = dot(p - a, n);
        s = max(s, sEdge);
    }
    
    return (s > 0.0) ? sqrt(d2) : -sqrt(d2);
}

// Alpha compositing (Source Over Destination)
float4 composite_over_Kite(float4 src, float4 dst)
{
    float a = src.a + dst.a * (1.0 - src.a);
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-8);
    return float4(c, a);
}

// --- Main Function ---
// PLAN:
// 1. Center the UV coordinates based on Center input.
// 2. Rotate the coordinate system by the Rotation angle.
// 3. Define the 4 vertices of the kite based on Width, HeightTop, and HeightBottom.
//    - A kite is a quadrilateral with two pairs of equal-length sides.
//    - Vertices: Top(0, H_top), Right(W, 0), Bottom(0, -H_bot), Left(-W, 0).
// 4. Calculate SDF using a convex polygon distance function.
// 5. Apply smoothstep for Anti-Aliasing on fill and stroke.
// 6. Composite stroke over fill.

void KiteShape_float(float2 UV, float Width, float HeightTop, float HeightBottom, float2 Center, float Rotation, float4 FillColor, float4 StrokeColor, float StrokeWidth, out float4 outColor)
{
    // 1. Center UVs
    float2 p = UV - Center;
    
    // 2. Rotate (Standard rotation matrix)
    float c = cos(Rotation);
    float s = sin(Rotation);
    p = float2(p.x * c - p.y * s, p.x * s + p.y * c);
    
    // 3. Define Vertices (Counter-Clockwise order)
    // Ensure positive dimensions
    float w = max(Width, 0.0);
    float hTop = max(HeightTop, 0.0);
    float hBot = max(HeightBottom, 0.0);
    
    float2 v0 = float2(0.0, hTop);   // Top
    float2 v1 = float2(-w, 0.0);     // Left
    float2 v2 = float2(0.0, -hBot);  // Bottom
    float2 v3 = float2(w, 0.0);      // Right
    
    // 4. Calculate Signed Distance Field
    float dist = sdConvexPoly4_Kite(p, v0, v1, v2, v3);
    
    // 5. Anti-Aliasing calculations
    float aa = fwidth(dist);
    
    // Fill Logic (Inside the shape)
    float fillAlpha = 1.0 - smoothstep(-aa, 0.0, dist);
    float4 fillLayer = float4(FillColor.rgb, FillColor.a * fillAlpha);
    
    // Stroke Logic (Border around the shape)
    float halfStroke = StrokeWidth * 0.5;
    float strokeDist = abs(dist) - halfStroke;
    float strokeAlpha = 1.0 - smoothstep(-aa, 0.0, strokeDist);
    float4 strokeLayer = float4(StrokeColor.rgb, StrokeColor.a * strokeAlpha);
    
    // 6. Composite Layers
    outColor = composite_over_Kite(strokeLayer, fillLayer);
}

// ------------------------------------------------------------------------
//  Visual Result (High-level, parameter-invariant description)
// ------------------------------------------------------------------------
//  This function generates a **2D kite-shaped quadrilateral primitive**
//  using a convex-polygon Signed Distance formulation.
//
//  The shape is a four-sided form with two pairs of adjacent equal-length
//  edges, producing a symmetric silhouette with a pointed region and a
//  broader opposing region. The exact proportions, orientation, placement,
//  fill, and outline appearance are fully controlled by input parameters
//  and are not fixed by the function itself.
//
//  The output is an anti-aliased RGBA color suitable for geometric icons,
//  symbolic shapes, decorative UI elements, and analytic procedural
//  2D graphics.
// ------------------------------------------------------------------------
