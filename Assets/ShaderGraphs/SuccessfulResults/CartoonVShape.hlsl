#ifndef PI
#define PI 3.14159265359
#endif

// --- Helpers ---

// Exact Euclidean distance to a line segment
inline float sdSegment(float2 p, float2 a, float2 b)
{
    float2 pa = p - a, ba = b - a;
    float h = saturate(dot(pa, ba) / dot(ba, ba));
    return length(pa - ba * h);
}

// Signed distance to a convex quadrilateral (must be CCW)
inline float sdConvexPoly4(float2 p, float2 v0, float2 v1, float2 v2, float2 v3)
{
    float2 v[4] = { v0, v1, v2, v3 };
    float d2 = 1e20;
    float s = -1e20;
    
    [unroll]
    for (int i = 0; i < 4; ++i)
    {
        float2 a = v[i];
        float2 b = v[(i + 1) % 4];
        
        // Distance to edge segment
        float sdE = sdSegment(p, a, b);
        d2 = min(d2, sdE * sdE);
        
        // Outward normal (CCW) -> Right hand rule from edge vector
        float2 e = b - a;
        float2 n = normalize(float2(e.y, -e.x));
        
        // Signed distance to edge line
        s = max(s, dot(p - a, n));
    }
    
    return (s > 0.0) ? sqrt(d2) : -sqrt(d2);
}

// Straight-alpha blend (Src over Dst)
inline float4 blendOver(float4 src, float4 dst)
{
    float finalAlpha = src.a + dst.a * (1.0 - src.a);
    float3 finalRGB = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(finalAlpha, 1e-8);
    return float4(finalRGB, finalAlpha);
}

// --- Main Function ---
// Generates a cartoon 'V' shape with adjustable size, thickness, corner radius, and outline.
void CartoonVShape_float(float2 UV, float2 Center, float2 Size, float Thickness, float CornerRadius, float4 FillColor, float4 OutlineColor, float OutlineWidth, out float4 outColor)
{
    // PLAN:
    // 1) Center and reflect UVs to handle symmetry (V is symmetric).
    // 2) Define the right-half of the V as a convex quadrilateral.
    // 3) Calculate inner vertices based on Thickness to ensure correct shape.
    // 4) Compute SDF to the quad, then subtract CornerRadius for rounding.
    // 5) Generate fill and stroke masks with AA.
    // 6) Blend stroke over fill.

    // 1) Coordinates
    float2 p = UV - Center;
    p.x = abs(p.x); // Symmetry: work on the right half only

    // 2) Define V Geometry (Right Half)
    // We model the leg of the V as a polygon.
    // Dimensions
    float w = max(Size.x, 0.001); // Half-width at top
    float h = max(Size.y, 0.001); // Half-height
    
    // Vertices of the outer edge
    float2 vOuterBot = float2(0.0, -h);
    float2 vOuterTop = float2(w, h);
    
    // Calculate inner edge based on thickness
    // Vector along the outer leg
    float2 legDir = normalize(vOuterTop - vOuterBot);
    // Normal pointing inward (Top-Left direction relative to the leg)
    float2 inwardNormal = float2(-legDir.y, legDir.x);
    
    // Points on the inner line (infinite line equation)
    float2 pInnerBase = vOuterBot + inwardNormal * max(Thickness, 0.001);
    
    // Intersect Inner Line with Top (y = h)
    // InnerLine: P = pInnerBase + t * legDir
    // y = pInnerBase.y + t * legDir.y = h  -> t = (h - pInnerBase.y) / legDir.y
    float tTop = (h - pInnerBase.y) / legDir.y;
    float2 vInnerTop = pInnerBase + legDir * tTop;
    
    // Intersect Inner Line with Center Axis (x = 0)
    // x = pInnerBase.x + t * legDir.x = 0  -> t = -pInnerBase.x / legDir.x
    float tBot = -pInnerBase.x / legDir.x;
    float2 vInnerBot = pInnerBase + legDir * tBot;
    
    // 3) SDF Calculation
    // Vertices in CCW order for the right half
    // V0: Bottom Outer (0, -h)
    // V1: Top Outer (w, h)
    // V2: Top Inner (calculated)
    // V3: Bottom Inner (calculated, on axis)
    
    // Safety: clamp vertical positions if thickness is too extreme
    vInnerBot.y = min(vInnerBot.y, h);
    vInnerTop.x = max(vInnerTop.x, 0.0);
    
    float dPoly = sdConvexPoly4(p, vOuterBot, vOuterTop, vInnerTop, vInnerBot);
    
    // Apply Corner Radius (Rounding)
    // Subtracting radius expands the shape, creating round corners.
    // To maintain approximate visual size, we rely on the user adjusting Size/Thickness,
    // or we could inset. Here we use standard SDF rounding behavior.
    float d = dPoly - max(CornerRadius, 0.0);

    // 4) Rendering with AA
    float aa = fwidth(d);
    
    // Fill Mask (d < 0)
    float fillAlpha = 1.0 - smoothstep(0.0, aa, d);
    float4 fillLayer = float4(FillColor.rgb, FillColor.a * fillAlpha);
    
    // Outline Mask (band around d=0)
    // Stroke centered on the edge
    float halfStroke = max(OutlineWidth, 0.0) * 0.5;
    float strokeDist = abs(d) - halfStroke;
    float strokeAlpha = 1.0 - smoothstep(0.0, aa, strokeDist);
    float4 strokeLayer = float4(OutlineColor.rgb, OutlineColor.a * strokeAlpha);
    
    // 5) Composite
    outColor = blendOver(strokeLayer, fillLayer);
}