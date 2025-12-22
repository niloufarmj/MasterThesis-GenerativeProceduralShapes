#ifndef PI
#define PI 3.14159265359
#endif

// --- Helper Functions ---

// Standard rotation matrix
void rotate2D(inout float2 p, float angle) {
    float s = sin(angle);
    float c = cos(angle);
    p = float2(p.x * c - p.y * s, p.x * s + p.y * c);
}

// Signed Distance to a Rounded Box
// p: point, b: half-extents, r: radius
float sdRoundedBox(float2 p, float2 b, float r) {
    float2 q = abs(p) - b + r;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

// Signed Distance to a Triangle defined by 3 points
float sdTriangle(float2 p, float2 p0, float2 p1, float2 p2) {
    float2 e0 = p1 - p0;
    float2 e1 = p2 - p1;
    float2 e2 = p0 - p2;
    float2 v0 = p - p0;
    float2 v1 = p - p1;
    float2 v2 = p - p2;
    float2 pq0 = v0 - e0 * clamp(dot(v0, e0) / dot(e0, e0), 0.0, 1.0);
    float2 pq1 = v1 - e1 * clamp(dot(v1, e1) / dot(e1, e1), 0.0, 1.0);
    float2 pq2 = v2 - e2 * clamp(dot(v2, e2) / dot(e2, e2), 0.0, 1.0);
    float s = sign(e0.x * e2.y - e0.y * e2.x);
    float2 d = min(min(float2(dot(pq0, pq0), s * (v0.x * e0.y - v0.y * e0.x)),
                       float2(dot(pq1, pq1), s * (v1.x * e1.y - v1.y * e1.x))), 
                       float2(dot(pq2, pq2), s * (v2.x * e2.y - v2.y * e2.x)));
    return -sqrt(d.x) * sign(d.y);
}

// Smooth Minimum for blending shapes
float smin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / max(k, 0.0001), 0.0, 1.0);
    return lerp(b, a, h) - k * h * (1.0 - h);
}

// Alpha blending helper (Src Over Dst)
float4 blendOver(float4 src, float4 dst) {
    float finalAlpha = src.a + dst.a * (1.0 - src.a);
    float3 finalColor = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(finalAlpha, 0.0001);
    return float4(finalColor, finalAlpha);
}

// --- Main Function ---
void SpeechBubble_float(float2 UV, float2 Center, float2 Size, float CornerRadius, float TailAngle, float2 TailSize, float4 FillColor, float4 StrokeColor, float StrokeWidth, out float4 outColor) {
    // PLAN:
    // 1) Center the coordinates.
    // 2) Compute SDF for the main rounded box body.
    // 3) Calculate the attachment point for the tail on the box boundary.
    // 4) Compute SDF for the tail (triangle) positioned at that point.
    // 5) Smoothly union the body and tail.
    // 6) Render stroke and fill with anti-aliasing.

    // 1. Setup coordinates
    float2 p = UV - Center;
    float2 halfSize = Size * 0.5;
    
    // 2. Body SDF (Rounded Box)
    float dBody = sdRoundedBox(p, halfSize, CornerRadius);
    
    // 3. Calculate Tail Position
    // Ray direction from center based on angle
    float2 ray = float2(cos(TailAngle), sin(TailAngle));
    
    // Find intersection with the sharp bounding box to attach tail base
    // t = distance to box edge along ray
    // Avoid divide by zero with max(abs, epsilon)
    float2 invRay = 1.0 / max(abs(ray), 0.0001);
    float t = min(halfSize.x * invRay.x, halfSize.y * invRay.y);
    
    // Overlap the tail slightly into the box to ensure smooth merge (10% of radius)
    // This prevents the tail from floating off rounded corners
    float overlap = CornerRadius * 0.5;
    float2 tailBasePos = ray * (t - overlap);
    
    // 4. Tail SDF (Triangle)
    // We calculate this in a local space where the tail points along +X
    float2 pRel = p - tailBasePos;
    // Rotate pRel by -TailAngle so the desired direction becomes (1,0)
    // Rotate -Angle means cos(a), -sin(a)
    float c = cos(TailAngle);
    float s = sin(TailAngle);
    float2 pTailLocal = float2(pRel.x * c + pRel.y * s, -pRel.x * s + pRel.y * c);
    
    // Define Triangle Vertices in local space (pointing Right)
    // Base is on Y-axis (x=0), Tip is at x=TailLength
    float halfTailWidth = TailSize.x * 0.5;
    float tailLength = TailSize.y;
    
    float2 v0 = float2(0.0, halfTailWidth);  // Base Top
    float2 v1 = float2(0.0, -halfTailWidth); // Base Bottom
    float2 v2 = float2(tailLength, 0.0);     // Tip
    
    float dTail = sdTriangle(pTailLocal, v0, v1, v2);
    
    // 5. Combine (Smooth Union)
    // Smoothness factor relative to corner radius for consistent look
    float smoothFactor = max(CornerRadius * 0.5, 0.01);
    float d = smin(dBody, dTail, smoothFactor);
    
    // 6. Rendering
    // AA calculation
    float aa = fwidth(d);
    
    // Fill Layer
    float fillAlpha = 1.0 - smoothstep(-aa, aa, d);
    float4 fillLayer = float4(FillColor.rgb, FillColor.a * fillAlpha);
    
    // Stroke Layer (centered on edge)
    float halfStroke = StrokeWidth * 0.5;
    float strokeDist = abs(d) - halfStroke;
    float strokeAlpha = 1.0 - smoothstep(-aa, aa, strokeDist);
    float4 strokeLayer = float4(StrokeColor.rgb, StrokeColor.a * strokeAlpha);
    
    // Composite Stroke over Fill
    outColor = blendOver(strokeLayer, fillLayer);
}