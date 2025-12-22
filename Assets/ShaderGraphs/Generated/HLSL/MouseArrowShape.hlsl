/* 
  PLAN:
  1. Define a helper function sdArrowPolygon to calculate SDF for the specific 4-vertex arrow shape.
     The shape is a "Dart" or "Arrowhead" typical of mouse cursors (Tip, Wing, Notch, Wing).
  2. In the main function:
     a. Center the UVs to (0,0).
     b. Apply 2D rotation to the coordinate system based on the Angle parameter.
     c. Define the 4 vertices of the arrow based on the Size parameter.
     d. Calculate the signed distance using the helper.
     e. Apply smoothstep for anti-aliasing.
     f. Output the final RGBA color.
*/

#ifndef PI
#define PI 3.14159265359
#endif

// Helper: Calculate squared length of a vector
float dot2(float2 v) { return dot(v, v); }

// Helper: SDF for a general polygon with 4 vertices
// Uses the standard winding number and edge distance algorithm
float sdArrowPolygon(float2 p, float2 v0, float2 v1, float2 v2, float2 v3) {
    float2 verts[4] = { v0, v1, v2, v3 };
    float d = dot(p - verts[0], p - verts[0]);
    float s = 1.0;
    
    // Loop unrolled for 4 vertices
    [unroll]
    for (int i = 0; i < 4; i++) {
        int j = (i + 1) % 4;
        float2 e = verts[j] - verts[i];
        float2 w = p - verts[i];
        
        // Distance to line segment
        float2 b = w - e * clamp(dot(w, e) / dot(e, e), 0.0, 1.0);
        d = min(d, dot(b, b));
        
        // Winding number parity check for inside/outside sign
        bool3 cond = bool3(p.y >= verts[i].y, p.y < verts[j].y, e.x * w.y > e.y * w.x);
        if (all(cond) || all(!cond)) s *= -1.0;
    }
    
    return s * sqrt(d);
}

void MouseArrowShape_float(float2 UV, float Size, float Angle, float4 Color, out float4 outColor) {
    // User Request: A computer mouse cursor shaped like a simple arrow
    
    // 1. Center and Rotate Coordinates
    float2 p = UV - 0.5;
    
    // Rotation (rotate point by -Angle to rotate shape by +Angle)
    float c = cos(Angle);
    float s = sin(Angle);
    p = float2(p.x * c + p.y * s, -p.x * s + p.y * c);
    
    // 2. Define Arrow Shape Vertices (Dart / Mouse Pointer Shape)
    // Scaled by Size. Aspect ratio roughly 1:1.4
    // Coordinates are relative to the center (0,0)
    float tipY = 0.5 * Size;
    float tailY = -0.4 * Size;
    float notchY = -0.2 * Size;
    float wingX = 0.35 * Size;
    
    // Vertices in CCW order starting from Tip
    float2 v0 = float2(0.0, tipY);      // Top Tip
    float2 v1 = float2(-wingX, tailY);  // Left Wing
    float2 v2 = float2(0.0, notchY);    // Bottom Notch (Re-entrant corner)
    float2 v3 = float2(wingX, tailY);   // Right Wing

    // 3. Calculate SDF
    float dist = sdArrowPolygon(p, v0, v1, v2, v3);
    
    // 4. Anti-aliasing (smooth edge)
    // smoothstep from positive (outside) to negative (inside)
    float edge = smoothstep(0.005, -0.005, dist);
    
    // 5. Output Color
    // Apply mask to RGB and Alpha (premultiplied-like behavior for blending)
    outColor = float4(Color.rgb * edge, edge);
}