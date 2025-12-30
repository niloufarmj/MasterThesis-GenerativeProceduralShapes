#ifndef PI
#define PI 3.14159265359
#endif

// Helper: Perpendicular vector (right hand rule)
float2 nm_perpRight(float2 e) {
    return float2(e.y, -e.x);
}

// Helper: Distance from point p to segment ab
float nm_distPointToSegment(float2 p, float2 a, float2 b) {
    float2 e = b - a;
    float ee = max(dot(e, e), 1e-12);
    float t = clamp(dot(p - a, e) / ee, 0.0, 1.0);
    return length(p - (a + t * e));
}

// Helper: Signed Distance Function for a Regular Pentagon
float nm_sdPentagon(float2 p, float r) {
    // 5 vertices for the pentagon
    float2 v[5];
    
    // Calculate vertices starting from top (upright orientation)
    // 0.5 * PI corresponds to 90 degrees (top of the unit circle)
    [unroll]
    for (int k = 0; k < 5; k++) {
        float ang = 0.5 * PI + (2.0 * PI * float(k)) / 5.0;
        v[k] = float2(cos(ang), sin(ang)) * r;
    }

    float maxHalf = -1e9; // Max distance to any half-space (negative inside)
    float minEdge = 1e9;  // Min distance to any edge (absolute)

    // Iterate over all 5 edges
    [unroll]
    for (int i = 0; i < 5; i++) {
        int j = (i + 1) % 5;
        float2 a = v[i];
        float2 b = v[j];
        float2 e = b - a;
        float2 n = normalize(nm_perpRight(e)); // Outward normal

        // Distance to the line defined by the edge (signed)
        maxHalf = max(maxHalf, dot(p - a, n));
        // Distance to the segment itself (unsigned)
        minEdge = min(minEdge, nm_distPointToSegment(p, a, b));
    }

    // If maxHalf is negative, we are inside all half-spaces (inside the shape)
    // Return negative distance if inside, positive if outside
    return (maxHalf <= 0.0) ? -minEdge : minEdge;
}

void PentagonShape_float(float2 UV, float Size, float Rotation, float4 Color, out float4 outColor) {
    // PLAN:
    // 1) Center UV coordinates to (0,0) and handle scale (Size).
    // 2) Rotate the coordinate space by -Rotation to rotate the shape.
    // 3) Calculate the Signed Distance Field (SDF) for a pentagon.
    // 4) Apply anti-aliasing using smoothstep on the distance.
    // 5) Output the final color with alpha transparency.

    // 1) Center UVs
    float2 centered = UV - 0.5;

    // 2) Rotate p by -Rotation (rotates the sampling point, effectively rotating the shape)
    float c = cos(Rotation);
    float s = sin(Rotation);
    float2 p = float2(c * centered.x + s * centered.y, -s * centered.x + c * centered.y);

    // 3) Calculate SDF
    // We use Size as the circumradius of the pentagon
    float dist = nm_sdPentagon(p, max(Size, 0.001));

    // 4) Anti-aliasing
    // Create a smooth mask based on distance. 0.01 provides a soft edge.
    float mask = smoothstep(0.01, -0.01, dist);

    // 5) Output Color
    // Apply the mask to the alpha channel. We maintain the input Color's alpha as well.
    outColor = float4(Color.rgb, Color.a * mask);
}