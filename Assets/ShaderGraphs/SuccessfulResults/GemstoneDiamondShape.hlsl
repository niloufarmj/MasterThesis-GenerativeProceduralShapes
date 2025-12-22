// PLAN:
// 1. Define helpers for cross product and segment distance.
// 2. Define a generic 5-sided convex polygon SDF function.
// 3. In the main function, center and rotate the UV coordinates.
// 4. Calculate the 5 vertices of the diamond based on input width, height, table, and girdle.
//    - Bottom tip, Right girdle, Top-Right table, Top-Left table, Left girdle.
// 5. Compute SDF using the polygon function.
// 6. Apply smoothstep for anti-aliasing and output final color.

#ifndef PI
#define PI 3.14159265359
#endif

// Helper: Perpendicular vector (right hand rule)
float2 gd_perpRight(float2 e) {
    return float2(e.y, -e.x);
}

// Helper: Squared distance from point p to segment ab
float gd_distSegmentSq(float2 p, float2 a, float2 b) {
    float2 pa = p - a;
    float2 ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    float2 d = pa - ba * h;
    return dot(d, d);
}

// Helper: SDF to a convex polygon with 5 vertices (CCW order)
float gd_sdPoly5(float2 p, float2 v0, float2 v1, float2 v2, float2 v3, float2 v4) {
    float2 v[5] = { v0, v1, v2, v3, v4 };
    float d2 = 1e20;
    float s = -1e20;

    [unroll]
    for (int i = 0; i < 5; i++) {
        float2 a = v[i];
        float2 b = v[(i + 1) % 5];
        
        // Distance to edge segment
        d2 = min(d2, gd_distSegmentSq(p, a, b));
        
        // Signed distance to edge line (outward normal)
        float2 e = b - a;
        float2 n = normalize(gd_perpRight(e));
        s = max(s, dot(p - a, n));
    }
    
    return s > 0.0 ? sqrt(d2) : -sqrt(d2);
}

void GemstoneDiamondShape_float(float2 UV, float Width, float Height, float TableWidth, float GirdlePos, float Rotation, float4 Color, out float4 outColor) {
    // 1. Center UV coordinates (0,0 at center)
    float2 p = UV - 0.5;
    
    // 2. Apply Rotation
    float c = cos(Rotation);
    float s = sin(Rotation);
    p = float2(c * p.x + s * p.y, -s * p.x + c * p.y);
    
    // 3. Define Diamond Vertices (CCW)
    // Coordinates relative to center (0,0)
    // Y range: [-Height/2, +Height/2]
    float halfH = Height * 0.5;
    float halfW = Width * 0.5;
    float halfTable = TableWidth * 0.5;
    
    // Y positions
    float yBottom = -halfH;
    float yTop = halfH;
    // Girdle Y based on ratio (0 = bottom, 1 = top). Default ~0.7 for diamond.
    float yGirdle = -halfH + (Height * clamp(GirdlePos, 0.01, 0.99));
    
    // Vertices
    float2 v0 = float2(0.0, yBottom);       // Bottom Tip
    float2 v1 = float2(halfW, yGirdle);     // Right Girdle (Widest)
    float2 v2 = float2(halfTable, yTop);    // Top Right (Table edge)
    float2 v3 = float2(-halfTable, yTop);   // Top Left (Table edge)
    float2 v4 = float2(-halfW, yGirdle);    // Left Girdle (Widest)
    
    // 4. Calculate SDF
    float dist = gd_sdPoly5(p, v0, v1, v2, v3, v4);
    
    // 5. Anti-aliasing
    float edge = smoothstep(0.01, -0.01, dist);
    
    // 6. Output
    outColor = float4(Color.rgb * edge, edge);
}