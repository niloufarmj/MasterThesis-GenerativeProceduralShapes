#ifndef PI
#define PI 3.14159265359
#endif

// Helper for alpha blending (SrcOver)
float4 magnet_blend(float4 src, float4 dst) {
    float outA = src.a + dst.a * (1.0 - src.a);
    float3 outRGB = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(outA, 1e-6);
    return float4(outRGB, outA);
}

// User Request: A cartoon horseshoe magnet with U-shaped body, split colors, and metal caps.
void MagnetCartoon_float(float2 UV, float Width, float Height, float ArmThickness, float CapHeight, float4 ColorNorth, float4 ColorSouth, float4 CapColor, float4 OutlineColor, float OutlineThickness, out float4 outColor) {
    // PLAN:
    // 1) Center UVs and adjust y-coordinate to align the U-shape's geometric center (arc center).
    // 2) Calculate key dimensions: outer radius, straight section length, centerline radius.
    // 3) Compute SDF for the U-shape (vertical lines + bottom semi-circle).
    // 4) Compute color zones: Caps (top of straight section), North (Left), South (Right).
    // 5) Generate masks for Fill and Outline using smoothstep AA.
    // 6) Composite Outline over Fill.

    // 1) Coordinates and Setup
    float2 p = UV - 0.5;
    
    // Clamp inputs to sane values to prevent breakage
    Width = max(Width, 0.01);
    Height = max(Height, Width * 0.5 + 0.01);
    ArmThickness = min(ArmThickness, Width * 0.5 - 0.001);
    
    // 2) Dimensions
    float R_outer = Width * 0.5;
    float H_straight = max(0.0, Height - R_outer);
    float R_center = (Width - ArmThickness) * 0.5;
    float halfArm = ArmThickness * 0.5;
    
    // Adjust P so that (0,0) is the center of the bottom arc curvature
    // Visually: Bottom is at -Height/2, Top is at +Height/2
    // Geometrically: Arc bottom is at -R_outer relative to Arc Center.
    // We want Visual Bottom (-Height/2) to align with Geometric Bottom (-R_outer)
    // So Arc Center Y in Visual coords is: -Height/2 + R_outer
    float arcCenterY = -Height * 0.5 + R_outer;
    p.y -= arcCenterY;

    // 3) SDF Calculation (U-Shape Centerline)
    float2 q = p;
    q.x = abs(q.x); // Symmetry for left/right arms
    
    float dCenterline = 0.0;
    if (q.y > 0.0) {
        // Straight vertical segment (Arms)
        // Clamp height to the straight section length
        float2 closest = float2(R_center, clamp(q.y, 0.0, H_straight));
        dCenterline = length(q - closest);
    } else {
        // Bottom Arc segment
        dCenterline = abs(length(q) - R_center);
    }
    
    // Signed Distance to surface (negative inside)
    float dist = dCenterline - halfArm;

    // 4) Antialiasing & Masks
    float aa = max(fwidth(dist), 0.001);
    float fillMask = 1.0 - smoothstep(0.0, aa, dist);
    
    // Outline sits on the edge. We draw it by expanding the shape slightly or checking the band.
    // Here we use a centered stroke logic (band around dist=0)
    float halfStroke = OutlineThickness * 0.5;
    float strokeDist = abs(dist) - halfStroke;
    float strokeMask = 1.0 - smoothstep(0.0, aa, strokeDist);
    
    // 5) Color Zones
    // Cap Logic: The caps are at the top of the straight section.
    // Check if y is within the top 'CapHeight' of the straight part.
    // Note: p.y is relative to arc center.
    float capThreshold = H_straight - CapHeight;
    bool isCap = (p.y > capThreshold) && (p.y <= H_straight + halfArm); // +halfArm covers rounded top if we had one, basically just > threshold inside shape
    
    // Pole Logic: Split by original x (Left = North, Right = South)
    // Using original UV.x is safer than p.x since p.x was not mirrored, but let's use p.x
    float4 poleColor = (p.x < 0.0) ? ColorNorth : ColorSouth;
    float4 fillColor = isCap ? CapColor : poleColor;
    
    // 6) Composition
    float4 fillLayer = float4(fillColor.rgb, fillColor.a * fillMask);
    float4 strokeLayer = float4(OutlineColor.rgb, OutlineColor.a * strokeMask);
    
    // Blend Stroke OVER Fill
    outColor = magnet_blend(strokeLayer, fillLayer);
}