#ifndef PI
#define PI 3.14159265359
#endif

// --- Helper Functions ---

// Signed distance to a rounded box
// p: point, b: half-extents, r: corner radius
float nm_sdRoundedBox(float2 p, float2 b, float r) {
    float2 q = abs(p) - b + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

// Signed distance to the Shackle (U-shaped arch)
// p: point relative to base of legs
// r: radius of the arch (horizontal spread)
// h: height of the straight vertical legs
// t: thickness of the tube
float nm_sdArch(float2 p, float r, float h, float t) {
    // Symmetry: work on positive x side
    p.x = abs(p.x);
    
    // The shape is composed of two parts joined at y=h with G1 continuity (vertical tangent):
    // 1. A semi-circle arc centered at (0,h) with radius r, for y > h
    // 2. A vertical segment from (r,0) to (r,h), for y <= h
    // Because the join has a vertical tangent, the boundary between the two closest-point regions is exactly y=h.
    
    float distCenter = 0.0;
    if (p.y > h) {
        // Distance to semi-circle arc
        distCenter = abs(length(p - float2(0.0, h)) - r);
    } else {
        // Distance to vertical segment (r,0)-(r,h)
        // We clamp p.y to [0, h] to get round cap at the bottom and correct join at top
        float py = clamp(p.y, 0.0, h);
        distCenter = distance(p, float2(r, py));
    }
    
    return distCenter - t;
}

// Composite Premultiplied Alpha Colors (A over B)
// A: Foreground, B: Background
float4 nm_compositePreMul(float4 A, float4 B) {
    float4 Out;
    Out.rgb = A.rgb + B.rgb * (1.0 - A.a);
    Out.a = A.a + B.a * (1.0 - A.a);
    return Out;
}

void CartoonLockShape_float(float2 UV, float2 BodySize, float BodyCornerRadius, float ShackleRadius, float ShackleLegHeight, float ShackleThickness, float4 BodyColor, float4 ShackleColor, out float4 outColor) {
    // PLAN:
    // 1) Center UV coordinates.
    // 2) Define Body position and Shackle position relative to each other.
    // 3) Calculate SDF for Body (Rounded Box) and Shackle (Arch).
    // 4) Apply anti-aliasing to create masks.
    // 5) Composite Body color OVER Shackle color.

    float2 centered = UV - 0.5;
    
    // --- Positioning ---
    // Shift everything down slightly so the lock looks centered visually (shackle adds height)
    float2 bodyCenter = float2(0.0, -0.1);
    float2 pBody = centered - bodyCenter;
    
    // Shackle is anchored inside the body.
    // We position the base of the shackle legs slightly below the top of the body.
    float2 bodyHalfSize = BodySize * 0.5;
    // Shackle base starts at 75% of body height (inside the body)
    float shackleBaseOffsetY = bodyHalfSize.y * 0.5;
    float2 shackleOrigin = bodyCenter + float2(0.0, shackleBaseOffsetY);
    float2 pShackle = centered - shackleOrigin;

    // --- SDF Calculation ---
    // 1. Body SDF
    // Clamp radius to prevent artifacts if user inputs large value
    float rBody = clamp(BodyCornerRadius, 0.0, min(bodyHalfSize.x, bodyHalfSize.y));
    float dBody = nm_sdRoundedBox(pBody, bodyHalfSize, rBody);

    // 2. Shackle SDF
    float dShackle = nm_sdArch(pShackle, ShackleRadius, ShackleLegHeight, ShackleThickness);

    // --- Rendering ---
    // Anti-aliasing width
    float aa = length(float2(ddx(dBody), ddy(dBody)));
    aa = max(aa, 0.001); // Safety for preview

    // Compute Alpha Masks (Smoothstep SDFs)
    float mBody = 1.0 - smoothstep(-aa, aa, dBody);
    float mShackle = 1.0 - smoothstep(-aa, aa, dShackle);

    // Create Premultiplied Colors
    float4 colBody = float4(BodyColor.rgb * mBody, mBody * BodyColor.a);
    float4 colShackle = float4(ShackleColor.rgb * mShackle, mShackle * ShackleColor.a);

    // Composite: Body OVER Shackle (legs are hidden behind body)
    outColor = nm_compositePreMul(colBody, colShackle);
}