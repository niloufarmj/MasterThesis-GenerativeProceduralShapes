#ifndef PI
#define PI 3.14159265359
#endif

// --- Helper Functions ---

// Exact signed distance to a line segment AB
inline float sdSegment(float2 p, float2 a, float2 b)
{
    float2 pa = p - a, ba = b - a;
    float h = saturate(dot(pa, ba) / dot(ba, ba));
    return length(pa - ba * h);
}

// Exact signed distance to a convex 4-sided polygon (CCW winding)
inline float sdConvexPoly4(float2 p, float2 v0, float2 v1, float2 v2, float2 v3)
{
    float2 v[4] = { v0, v1, v2, v3 };
    float d2 = 1e20;
    float s = -1e20;
    
    [unroll]
    for (int i = 0; i < 4; ++i)
    {
        float2 a = v[i];
        float2 b = v[(i + 1) & 3];
        
        // Distance to edge segment
        float sdE = sdSegment(p, a, b);
        d2 = min(d2, sdE * sdE);
        
        // Signed distance to edge line (outward normal)
        float2 e = b - a;
        float2 n = normalize(float2(e.y, -e.x));
        s = max(s, dot(p - a, n));
    }
    
    return (s > 0.0) ? sqrt(d2) : -sqrt(d2);
}

// Alpha blending helper (Src over Dst)
inline float4 nm_over(float4 src, float4 dst)
{
    float a = src.a + dst.a * (1.0 - src.a);
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-8);
    return float4(c, a);
}

// --- Main Function ---
void GemDiamondShape_float(float2 UV, float Width, float Height, float2 Center, float Rotation, float4 FillColor, float4 StrokeColor, float StrokeWidth, out float4 outColor)
{
    // PLAN:
    // 1) Recenter and rotate UV coordinates.
    // 2) Define rhombus/diamond vertices based on Width and Height.
    // 3) Calculate signed distance using convex polygon SDF.
    // 4) Compute analytic anti-aliasing.
    // 5) Generate fill and stroke layers.
    // 6) Composite layers for final output.

    // 1. Coordinate Transform
    float2 p = UV - Center;
    float c = cos(Rotation);
    float s = sin(Rotation);
    float2 pr = float2(c * p.x + s * p.y, -s * p.x + c * p.y);

    // 2. Define Vertices (CCW order: Right, Top, Left, Bottom)
    float2 v0 = float2(Width * 0.5, 0.0);
    float2 v1 = float2(0.0, Height * 0.5);
    float2 v2 = float2(-Width * 0.5, 0.0);
    float2 v3 = float2(0.0, -Height * 0.5);

    // 3. SDF Calculation
    float d = sdConvexPoly4(pr, v0, v1, v2, v3);
    float aa = fwidth(d);

    // 4. Fill Layer
    float fillMask = 1.0 - smoothstep(0.0, aa, d);
    float4 fillOut = float4(FillColor.rgb, saturate(FillColor.a) * fillMask);

    // 5. Stroke Layer
    float halfW = max(StrokeWidth, 0.0) * 0.5;
    float strokeDist = abs(d) - halfW;
    float strokeMask = 1.0 - smoothstep(0.0, aa, strokeDist);
    float4 strokeOut = float4(StrokeColor.rgb, saturate(StrokeColor.a) * strokeMask);

    // 6. Composition
    outColor = nm_over(strokeOut, fillOut);
}