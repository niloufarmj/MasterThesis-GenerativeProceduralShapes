#ifndef PI
#define PI 3.14159265359
#endif

#ifndef NM_OVER_HELPER
#define NM_OVER_HELPER
// Helper for standard alpha blending (Source Over Destination)
inline float4 nm_over(float4 src, float4 dst)
{
    float a = src.a + dst.a * (1.0 - src.a);
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-8);
    return float4(c, a);
}
#endif

// Helper: Calculate 2D perpendicular vector (right-hand rule)
inline float2 nm_perpRight(float2 e)
{
    return float2(e.y, -e.x);
}

// Helper: Squared distance from point p to segment ab
inline float nm_distPointToSegment(float2 p, float2 a, float2 b)
{
    float2 e = b - a;
    float ee = max(dot(e, e), 1e-12);
    float t = clamp(dot(p - a, e) / ee, 0.0, 1.0);
    float2 q = a + t * e;
    return length(p - q);
}

// Helper: Signed Distance to a Convex Pentagon (5 vertices)
// Returns negative inside, positive outside
inline float nm_sdConvexPoly5(float2 p, float2 v[5])
{
    float d2 = 1e20;
    float s = -1e20;
    
    [unroll]
    for (int i = 0; i < 5; ++i)
    {
        float2 a = v[i];
        float2 b = v[(i + 1) % 5];
        float2 e = b - a;
        float2 n = normalize(nm_perpRight(e)); // outward normal
        
        // Squared distance to the edge segment
        d2 = min(d2, nm_distPointToSegment(p, a, b) * nm_distPointToSegment(p, a, b));
        
        // Signed distance to the line (for inside/outside check)
        s = max(s, dot(p - a, n));
    }
    
    return (s > 0.0) ? sqrt(d2) : -sqrt(d2);
}

void PentagonRounded_float(float2 UV, float Radius, float CornerRadius, float2 Center, float Rotation, float4 FillColor, float4 StrokeColor, float StrokeWidth, out float4 outColor)
{
    // PLAN:
    // 1) Recenter UV coordinates to the specified Center.
    // 2) Rotate the coordinate system by -Rotation.
    // 3) Calculate the vertices of a regular pentagon.
    // 4) Apply CornerRadius by insetting vertices (shrinking the polygon) and subtracting radius from SDF.
    // 5) Compute SDF distance, anti-aliasing factor, fill mask, and stroke mask.
    // 6) Blend Stroke over Fill for final output.

    // 1) Center UV space
    float2 p = UV - Center;

    // 2) Rotate sampling point by -Rotation so the shape appears rotated by +Rotation
    float c = cos(Rotation);
    float s = sin(Rotation);
    float2 pr = float2(c * p.x + s * p.y,
                       -s * p.x + c * p.y);

    // 3) Calculate base pentagon vertices (upright, centered at origin)
    // We use max(Radius, 0.0) to prevent negative size artifacts
    float R = max(Radius, 0.0);
    float2 v[5];
    
    [unroll]
    for (int i = 0; i < 5; ++i)
    {
        // Start at 90 degrees (pi/2) to point up
        float ang = 0.5 * PI + (2.0 * PI * i) / 5.0;
        v[i] = R * float2(cos(ang), sin(ang));
    }

    // 4) Handle Corner Radius
    // The maximum valid corner radius is the apothem (distance from center to midpoint of edge)
    // Apothem = R * cos(PI/5)
    float apothem = R * 0.809016994; // cos(36 degrees)
    float r = clamp(CornerRadius, 0.0, apothem - 0.0001);

    // Calculate the inset factor. To round corners by 'r', we shrink the polygon edges inward by 'r'.
    // For a regular polygon, this scales the vertices by (Apothem - r) / Apothem.
    float safeApothem = max(apothem, 1e-6);
    float insetFactor = (safeApothem - r) / safeApothem;
    
    float2 vi[5];
    [unroll]
    for (int k = 0; k < 5; ++k)
    {
        vi[k] = v[k] * insetFactor;
    }

    // 5) Calculate Signed Distance Field (SDF)
    // Distance to the smaller inset polygon minus the corner radius creates the rounded exterior
    float dist = nm_sdConvexPoly5(pr, vi) - r;

    // Anti-aliasing width based on screen derivatives
    float aa = fwidth(dist);

    // 6) Fill Coverage (Inside the shape)
    // smoothstep from 0 to aa creates a soft edge at the boundary (dist=0)
    float fillMask = 1.0 - smoothstep(0.0, aa, dist);
    float4 fillOut = float4(FillColor.rgb, saturate(FillColor.a) * fillMask);

    // 7) Stroke Coverage
    // The stroke is a band centered on the edge (dist=0)
    float halfStroke = 0.5 * max(StrokeWidth, 0.0);
    float strokeDist = abs(dist) - halfStroke;
    float strokeMask = 1.0 - smoothstep(0.0, aa, strokeDist);
    float4 strokeOut = float4(StrokeColor.rgb, saturate(StrokeColor.a) * strokeMask);

    // 8) Composite: Draw stroke OVER fill
    outColor = nm_over(strokeOut, fillOut);
}