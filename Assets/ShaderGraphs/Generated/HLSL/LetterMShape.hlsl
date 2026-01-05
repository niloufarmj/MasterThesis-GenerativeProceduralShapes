#ifndef PI
#define PI 3.14159265359
#endif

// --- Helper Functions ---

// Calculate distance to a line segment [a, b]
inline float sdSegment(float2 p, float2 a, float2 b) {
    float2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}

// Signed distance to a box
inline float sdBox(float2 p, float2 b) {
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// Signed distance to a convex quadrilateral (must be CCW)
inline float sdConvexPoly4(float2 p, float2 v0, float2 v1, float2 v2, float2 v3) {
    float2 v[4] = { v0, v1, v2, v3 };
    float d2 = 1e20;
    float s = -1e20;
    
    [unroll]
    for (int i = 0; i < 4; ++i) {
        float2 a = v[i];
        float2 b = v[(i + 1) % 4];
        
        // Distance to edge
        float sdE = sdSegment(p, a, b);
        d2 = min(d2, sdE * sdE);
        
        // Signed distance to line (outward normal)
        float2 e = b - a;
        float2 n = normalize(float2(e.y, -e.x)); // Right-hand perp is outward for CCW
        s = max(s, dot(p - a, n));
    }
    
    return (s > 0.0) ? sqrt(d2) : -sqrt(d2);
}

// Porter-Duff "Source Over" blending
inline float4 blendOver(float4 src, float4 dst) {
    float outA = src.a + dst.a * (1.0 - src.a);
    float3 outRGB = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(outA, 1e-5);
    return float4(outRGB, outA);
}

// --- Main Function ---
// Letter M: Two vertical outer legs and two angled inner strokes meeting at a valley.
void LetterMShape_float(float2 UV, float Width, float Height, float LegThickness, float ValleyDepth, float CornerRadius, float2 Center, float Rotation, float4 FillColor, float4 StrokeColor, float StrokeWidth, out float4 outColor) {
    // PLAN:
    // 1) Center and rotate UVs.
    // 2) Apply horizontal symmetry (abs(x)) to model just the right half.
    // 3) Construct Right Leg (Box) and Right Diagonal (Convex Quad).
    // 4) Union shapes, apply corner radius, and render with AA.

    // 1) Transform UV
    float2 p = UV - Center;
    float cosA = cos(Rotation);
    float sinA = sin(Rotation);
    p = float2(cosA * p.x + sinA * p.y, -sinA * p.x + cosA * p.y);
    
    // 2) Symmetry: Work on the right half only
    p.x = abs(p.x);

    // Parameters setup
    float halfW = max(Width * 0.5, 0.001);
    float halfH = max(Height * 0.5, 0.001);
    float t = max(LegThickness, 0.001);
    float valley = clamp(ValleyDepth, 0.0, Height);
    
    // 3) Define Shapes (Right Half)
    
    // A. Vertical Leg (Right side)
    // Centered at the outer edge minus half thickness
    float2 legCenter = float2(halfW - t * 0.5, 0.0);
    float2 legSize = float2(t * 0.5, halfH);
    float dLeg = sdBox(p - legCenter, legSize);
    
    // B. Diagonal Stroke
    // Defined as a quad connecting the top-inner leg corner to the valley center.
    // Vertices must be CCW. 
    // Key points:
    float2 vTopRight = float2(halfW, halfH); // Outer top corner
    float2 vValleyTop = float2(0.0, halfH - valley); // Valley top point
    
    // Calculate vertical thickness of the diagonal strip to maintain constant perpendicular width 't'
    float2 diagVec = vTopRight - vValleyTop;
    float diagLen = length(diagVec);
    // Through similar triangles, the vertical drop for thickness t is:
    float vDrop = (diagLen > 0.0001) ? (t * diagLen / max(halfW, 0.001)) : t;
    
    float2 vValleyBot = float2(0.0, vValleyTop.y - vDrop);
    float2 vTopRightBot = float2(halfW, halfH - vDrop);
    
    // CCW Order: ValleyTop -> ValleyBot -> TopRightBot -> TopRight
    float dDiag = sdConvexPoly4(p, vValleyTop, vValleyBot, vTopRightBot, vTopRight);
    
    // 4) Union & Rendering
    float dShape = min(dLeg, dDiag);
    
    // Apply Corner Radius (rounds convex corners)
    float r = clamp(CornerRadius, 0.0, min(halfW, halfH));
    dShape -= r;
    
    // Anti-aliasing
    float aa = fwidth(dShape);
    float fillMask = 1.0 - smoothstep(-aa, aa, dShape);
    
    // Stroke
    float halfStroke = max(StrokeWidth * 0.5, 0.0);
    float strokeDist = abs(dShape) - halfStroke;
    float strokeMask = 1.0 - smoothstep(-aa, aa, strokeDist);
    
    // Composition
    float4 fillLayer = float4(FillColor.rgb, FillColor.a * fillMask);
    float4 strokeLayer = float4(StrokeColor.rgb, StrokeColor.a * strokeMask);
    
    outColor = blendOver(strokeLayer, fillLayer);
}