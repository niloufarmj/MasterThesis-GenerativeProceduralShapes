#ifndef PI
#define PI 3.14159265359
#endif

// Helper: Calculate signed distance to a 2D triangle (CCW vertices)
// Returns negative inside, positive outside
float sdRightTriangle_Helper(float2 p, float2 p0, float2 p1, float2 p2)
{
    float2 e0 = p1 - p0;
    float2 e1 = p2 - p1;
    float2 e2 = p0 - p2;

    float2 v0 = p - p0;
    float2 v1 = p - p1;
    float2 v2 = p - p2;

    float2 pq0 = v0 - e0 * clamp(dot(v0, e0) / dot(e0, e0), 0.0, 1.0);
    float2 pq1 = v1 - e1 * clamp(dot(v1, e1) / dot(e1, e1), 0.0, 1.0);
    float2 pq2 = v2 - e2 * clamp(dot(v2, e2) / dot(e2, e2), 0.0, 1.0);

    // Winding number / sign determination
    float s = sign(e0.x * e2.y - e0.y * e2.x);
    
    // Combine distances to 3 edges
    float2 d = min(min(float2(dot(pq0, pq0), s * (v0.x * e0.y - v0.y * e0.x)),
                       float2(dot(pq1, pq1), s * (v1.x * e1.y - v1.y * e1.x))), 
                       float2(dot(pq2, pq2), s * (v2.x * e2.y - v2.y * e2.x)));

    // Return signed distance
    return -sqrt(d.x) * sign(d.y);
}

// Helper: Alpha Blending (Source Over Destination)
float4 blendColors_Helper(float4 src, float4 dst)
{
    float a = src.a + dst.a * (1.0 - src.a);
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-8);
    return float4(c, a);
}

void RightTriangle_float(float2 UV, float Width, float Height, float2 Center, float Rotation, float4 FillColor, float4 StrokeColor, float StrokeWidth, out float4 outColor)
{
    // PLAN:
    // 1) Translate UV to Center and rotate point to handle shape rotation.
    // 2) Define 3 vertices for the right triangle (Box aligned).
    // 3) Calculate exact SDF using triangle formula.
    // 4) Compute Fill and Stroke masks using AA (smoothstep).
    // 5) Composite Stroke over Fill for final output.

    // 1. Center & Rotate Space
    float2 p = UV - Center;
    float c = cos(Rotation);
    float s = sin(Rotation);
    // Rotate coordinate system by -Rotation to rotate shape by +Rotation
    p = float2(c * p.x + s * p.y, -s * p.x + c * p.y);

    // 2. Define Vertices (Centered Bounding Box, CCW Order)
    // We place the right angle at the bottom-left of the bounding box
    float hw = Width * 0.5;
    float hh = Height * 0.5;
    
    float2 v0 = float2(-hw, -hh); // Bottom-Left (Right Angle)
    float2 v1 = float2(hw, -hh);  // Bottom-Right
    float2 v2 = float2(-hw, hh);  // Top-Left

    // 3. SDF Calculation
    float dist = sdRightTriangle_Helper(p, v0, v1, v2);

    // 4. Anti-Aliasing & Masking
    // Estimate pixel width for sharp, smooth edges
    float aa = fwidth(dist);
    
    // Fill Mask: Distance < 0 is inside
    float fillMask = 1.0 - smoothstep(0.0, aa, dist);
    
    // Stroke Mask: Distance approx 0 is edge
    // We create a band of total width 'StrokeWidth' centered on the edge
    float halfStroke = max(StrokeWidth, 0.0) * 0.5;
    float strokeDist = abs(dist) - halfStroke;
    float strokeMask = 1.0 - smoothstep(0.0, aa, strokeDist);

    // 5. Apply Colors
    float4 fill = float4(FillColor.rgb, saturate(FillColor.a) * fillMask);
    float4 stroke = float4(StrokeColor.rgb, saturate(StrokeColor.a) * strokeMask);

    // 6. Composite (Stroke Over Fill)
    outColor = blendColors_Helper(stroke, fill);
}