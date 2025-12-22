#ifndef PI
#define PI 3.14159265359
#endif

// Helper: Rounded Box SDF
// p: sampling point
// b: half-extents (width/2, height/2)
// r: corner radius
float sdRoundedBox(float2 p, float2 b, float r) {
    float2 q = abs(p) - b + r;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

void LockIcon_float(float2 UV, float Size, float2 BodySize, float BodyRadius, float ShackleRadius, float ShackleHeight, float ShackleThickness, float4 Color, out float4 outColor) {
    // PLAN:
    // 1) Center UV and scale by Size to keep coordinate system uniform.
    // 2) Define Body using a RoundedBox SDF, positioned slightly down.
    // 3) Define Shackle using a U-shape (Arch) constructed via SDF elongation.
    //    - Elongate a ring SDF downwards to form the straight legs.
    // 4) Combine Body and Shackle using min() (Union).
    // 5) Apply smoothstep for anti-aliasing and output color.

    // 1. Coordinate Setup
    float2 p = UV - 0.5;
    float s = max(Size, 0.001); // Safety against div by zero
    p /= s;

    // 2. Lock Body Parameters
    // BodySize is input as full width/height, convert to half-extents
    float2 bHalf = BodySize * 0.5;
    // Clamp radius to ensure valid shape
    float bRad = clamp(BodyRadius, 0.0, min(bHalf.x, bHalf.y));
    
    // Offset body downwards so the complete icon (with shackle) appears centered
    float verticalOffset = -ShackleHeight * 0.3;
    float2 bodyPos = float2(0.0, verticalOffset);
    
    // Calculate Body SDF
    float dBody = sdRoundedBox(p - bodyPos, bHalf, bRad);

    // 3. Shackle Parameters
    // We treat ShackleRadius as the OUTER extent of the shackle curve.
    // We need the radius of the centerline for the SDF.
    float halfThick = ShackleThickness * 0.5;
    float rLine = max(0.0, ShackleRadius - halfThick);

    // Calculate geometry of the U-shape
    // ShackleHeight is the visible height above the body.
    // The arch part takes up 'ShackleRadius' of that height.
    // The straight part takes the rest.
    float straightH = max(0.0, ShackleHeight - ShackleRadius);
    
    // The geometric center of the arc (where straight legs meet the curve)
    float bodyTopY = bodyPos.y + bHalf.y;
    float2 archCenter = float2(0.0, bodyTopY + straightH);
    
    // Leg Length: How far the straight legs extend downwards into the body.
    // Extend them deep enough to be hidden (e.g., to the center of the body).
    float legDepth = straightH + bHalf.y;

    // 4. Shackle SDF (Elongated Ring)
    float2 q = p - archCenter;
    // Elongate the y-coordinate downwards to stretch the circle into a U-shape
    q.y -= clamp(q.y, -legDepth, 0.0);
    // Distance to the midline of the shackle
    float dShackle = abs(length(q) - rLine) - halfThick;

    // 5. Combine Shapes (Union)
    float dist = min(dBody, dShackle);

    // 6. Anti-aliasing and Color Output
    // Use smoothstep for soft edges
    float edge = smoothstep(0.005, -0.005, dist);
    
    // Output final color mixed with alpha
    outColor = float4(Color.rgb * edge, Color.a * edge);
}