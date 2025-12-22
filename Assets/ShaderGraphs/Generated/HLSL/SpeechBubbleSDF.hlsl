#ifndef PI
#define PI 3.14159265359
#endif

// --- Helpers ---

// 1. Safe length for normalization
float sb_len(float2 v) {
    return length(v);
}

// 2. Rotate vector p by angle (radians)
float2 sb_rotate(float2 p, float angle) {
    float c = cos(angle);
    float s = sin(angle);
    return float2(p.x * c - p.y * s, p.x * s + p.y * c);
}

// 3. Signed Distance to Rounded Box
float sb_sdRoundedBox(float2 p, float2 b, float r) {
    float2 q = abs(p) - b + r;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

// 4. Signed Distance to Triangle (IQ)
float sb_sdTriangle(float2 p, float2 p0, float2 p1, float2 p2) {
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

// 5. Smooth Minimum (Polynomial)
float sb_smin(float a, float b, float k) {
    float h = max(k - abs(a - b), 0.0) / max(k, 0.0001);
    return min(a, b) - h * h * k * 0.25;
}

// 6. Blend Colors (Src Over Dst)
float4 sb_blend(float4 src, float4 dst) {
    float outA = src.a + dst.a * (1.0 - src.a);
    float3 outRGB = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(outA, 0.0001);
    return float4(outRGB, outA);
}

// --- Main Function ---
void SpeechBubbleSDF_float(float2 UV, float2 Center, float2 Size, float CornerRadius, float PointerAngle, float2 PointerSize, float4 FillColor, float4 StrokeColor, float StrokeWidth, out float4 outColor) {
    // PLAN:
    // 1) Center UVs. Clamp radii to avoid artifacts.
    // 2) Calculate box SDF.
    // 3) Calculate pointer base position on the box edge using ray intersection.
    // 4) Define pointer triangle in local space and rotate it to match angle.
    // 5) Combine box and pointer with smooth union.
    // 6) Render fill and stroke with anti-aliasing.

    // 1. Setup
    float2 p = UV - Center;
    float2 halfSize = Size * 0.5;
    // Ensure corner radius fits in the box
    float r = clamp(CornerRadius, 0.0, min(halfSize.x, halfSize.y));
    
    // 2. Body SDF
    float dBody = sb_sdRoundedBox(p, halfSize, r);
    
    // 3. Pointer Position
    // Determine where the pointer attaches. Ray from center.
    float2 rayDir = float2(cos(PointerAngle), sin(PointerAngle));
    // Intersect ray with unrounded box bounds to find attachment point
    // t = distance to edge. Avoid div/0.
    float2 invRay = 1.0 / (abs(rayDir) + 1e-6);
    float t = min(halfSize.x * invRay.x, halfSize.y * invRay.y);
    
    // Overlap pointer slightly into the box for better blending
    float overlap = r * 0.5; 
    float2 pointerBase = rayDir * (t - overlap);
    
    // 4. Pointer SDF
    // Transform p to pointer-local space:
    // Origin at pointerBase, X axis aligned with rayDir.
    float2 pLocal = p - pointerBase;
    pLocal = sb_rotate(pLocal, -PointerAngle);
    
    // Define triangle vertices in local space (pointing Right along +X)
    // Winding: Bottom -> Top -> Tip (CCW-ish to ensure correct sign)
    float halfW = PointerSize.x * 0.5;
    float len = PointerSize.y;
    float2 v0 = float2(0.0, -halfW); // Base Bottom
    float2 v1 = float2(0.0, halfW);  // Base Top
    float2 v2 = float2(len, 0.0);    // Tip
    
    float dPointer = sb_sdTriangle(pLocal, v0, v1, v2);
    
    // 5. Combine
    // Smooth union blending
    float smoothK = max(r * 0.5, 0.01);
    float d = sb_smin(dBody, dPointer, smoothK);
    
    // 6. Rendering
    // Anti-aliasing width
    float aa = length(fwidth(p));
    if (aa < 1e-4) aa = 0.005; // Fallback if fwidth fails
    
    // Fill Mask (inner shape)
    float fillMask = 1.0 - smoothstep(-aa, aa, d);
    float4 fillLayer = float4(FillColor.rgb, FillColor.a * fillMask);
    
    // Stroke Mask (border)
    float halfStroke = StrokeWidth * 0.5;
    float strokeDist = abs(d) - halfStroke;
    float strokeMask = 1.0 - smoothstep(-aa, aa, strokeDist);
    float4 strokeLayer = float4(StrokeColor.rgb, StrokeColor.a * strokeMask);
    
    // Composite: Stroke Over Fill
    outColor = sb_blend(strokeLayer, fillLayer);
}