#ifndef PI
#define PI 3.14159265359
#endif

// --- Helper Functions ---

// Straight-alpha "src over dst" blending
float4 pent_over(float4 src, float4 dst)
{
    float a = src.a + dst.a * (1.0 - src.a);
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-8);
    return float4(c, a);
}

// Perpendicular vector (right-hand rule)
float2 pent_perpRight(float2 e)
{
    return float2(e.y, -e.x);
}

// Distance from point p to segment ab
float pent_distPointToSegment(float2 p, float2 a, float2 b)
{
    float2 e = b - a;
    float ee = max(dot(e, e), 1e-12);
    float t = clamp(dot(p - a, e) / ee, 0.0, 1.0);
    float2 q = a + t * e;
    return length(p - q);
}

// Signed distance to a convex polygon with 5 vertices
// Returns d < 0 inside, d > 0 outside
float pent_sdConvexPoly5(float2 p, float2 v[5])
{
    float d2 = 1e20;
    float s = -1e20;
    
    [unroll]
    for (int i = 0; i < 5; ++i)
    {
        float2 a = v[i];
        float2 b = v[(i + 1) % 5];
        float2 e = b - a;
        float2 n = normalize(pent_perpRight(e)); // outward normal
        
        // Euclidean distance to segment squared
        float distSeg = pent_distPointToSegment(p, a, b);
        d2 = min(d2, distSeg * distSeg);
        
        // Signed distance to line (for inside/outside check)
        s = max(s, dot(p - a, n));
    }
    
    return (s > 0.0) ? sqrt(d2) : -sqrt(d2);
}

// --- Main Function ---
// User Request: A pentagon with dynamic size, stroke, center, rotation, and corner radius
void PentagonShape_float(
    float2 UV,
    float Radius,
    float CornerRadius,
    float2 Center,
    float RotationRadians,
    float4 FillColor,
    float4 StrokeColor,
    float StrokeWidth,
    out float4 outColor)
{
    // PLAN:
    // 1) Recenter UVs to Center and apply Rotation.
    // 2) Define 5 vertices for a regular pentagon.
    // 3) Calculate Apothem to limit corner radius.
    // 4) Inset vertices inward to allow for rounded corners.
    // 5) Calculate SDF to the inset polygon, then subtract CornerRadius.
    // 6) Generate Fill and Stroke masks with AA.
    // 7) Composite Stroke over Fill.

    // 1) Coordinate transforms
    float2 p = UV - Center;
    float c = cos(RotationRadians);
    float s = sin(RotationRadians);
    // Rotate point by -angle to rotate shape by +angle
    p = float2(c * p.x + s * p.y, -s * p.x + c * p.y);

    // 2) Base vertices calculation
    float2 v[5];
    [unroll]
    for (int i = 0; i < 5; ++i)
    {
        // Start at 90 degrees (top)
        float ang = 0.5 * PI + (2.0 * PI * i) / 5.0;
        v[i] = Radius * float2(cos(ang), sin(ang));
    }

    // 3) Handle Corner Radius logic
    // Max safe radius is related to the apothem (distance from center to midpoint of edge)
    float apothem = Radius * cos(PI / 5.0);
    // Clamp radius to prevent artifacts (keep slightly below max)
    float r = clamp(CornerRadius, 0.0, apothem * 0.95);

    // 4) Inset vertices for rounding
    // Moving edges inward by 'r' effectively scales the shape down
    float scaleFactor = (apothem - r) / max(apothem, 1e-8);
    [unroll]
    for (int j = 0; j < 5; ++j)
    {
        v[j] *= scaleFactor;
    }

    // 5) Signed Distance Field
    // Distance to inset polygon minus radius gives rounded corners
    float dist = pent_sdConvexPoly5(p, v) - r;

    // 6) Antialiasing and Masks
    float aa = fwidth(dist);
    float fillMask = 1.0 - smoothstep(0.0, aa, dist);
    
    // Stroke is centered on the edge
    float halfStroke = StrokeWidth * 0.5;
    float strokeDist = abs(dist) - halfStroke;
    float strokeMask = 1.0 - smoothstep(0.0, aa, strokeDist);

    // 7) Composition
    float4 fill = float4(FillColor.rgb, FillColor.a * fillMask);
    float4 stroke = float4(StrokeColor.rgb, StrokeColor.a * strokeMask);

    outColor = pent_over(stroke, fill);
}