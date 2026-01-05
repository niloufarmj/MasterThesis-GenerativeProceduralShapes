#ifndef PI
#define PI 3.14159265359
#endif

// Helper: Signed Distance to a Box
// p: point relative to center
// b: half-extents (width/2, height/2)
float sdBox(float2 p, float2 b) {
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// Helper: Composite color (Source Over Destination)
float4 letter_over(float4 src, float4 dst) {
    float a = src.a + dst.a * (1.0 - src.a);
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-8);
    return float4(c, a);
}

void LetterEShape_float(
    float2 UV,
    float Width,
    float Height,
    float Thickness,
    float3 ArmLengths, // x=Top, y=Mid, z=Bot (0-1 relative to available width)
    float MidOffset,   // Vertical offset for middle arm
    float CornerRadius,
    float2 Center,
    float Rotation,
    float4 FillColor,
    float4 StrokeColor,
    float StrokeWidth,
    out float4 outColor
) {
    // PLAN:
    // 1) Transform UV to local centered/rotated space.
    // 2) Define dimensions for the spine and 3 arms based on inputs.
    // 3) Calculate SDF for each of the 4 component boxes.
    // 4) Combine them using min() to create a single union SDF.
    // 5) Apply CornerRadius by subtracting from the distance field (rounds convex corners).
    // 6) Compute smooth alpha masks for fill and stroke.
    // 7) Composite final output.

    // 1. Transform Coordinates
    float2 p = UV - Center;
    float rad = Rotation; // Input is radians
    float c = cos(rad);
    float s = sin(rad);
    p = float2(c * p.x + s * p.y, -s * p.x + c * p.y);

    // 2. Setup Dimensions
    float w = max(Width, 0.0) * 0.5;
    float h = max(Height, 0.0) * 0.5;
    float th = max(Thickness, 0.0);
    
    // Half thickness for calculations
    float hth = th * 0.5;

    // Available horizontal space for arms (Total Width - Spine Thickness)
    float armSpace = max(Width - th, 0.0);

    // 3. Define Shapes (Box SDFs)
    
    // --- Spine ---
    // Vertical bar aligned to the left edge of the bounding box
    // Center x = -w + hth. Full height 'h'.
    float2 spinePos = float2(-w + hth, 0.0);
    float2 spineSize = float2(hth, h);
    float dSpine = sdBox(p - spinePos, spineSize);

    // --- Arms ---
    // All arms start immediately to the right of the spine
    float startX = -w + th;

    // Top Arm: Positioned at top edge
    float lenTop = armSpace * saturate(ArmLengths.x);
    float2 topPos = float2(startX + lenTop * 0.5, h - hth);
    float2 topSize = float2(lenTop * 0.5, hth);
    float dTop = sdBox(p - topPos, topSize);

    // Middle Arm: Positioned at MidOffset
    float lenMid = armSpace * saturate(ArmLengths.y);
    float2 midPos = float2(startX + lenMid * 0.5, MidOffset);
    float2 midSize = float2(lenMid * 0.5, hth);
    float dMid = sdBox(p - midPos, midSize);

    // Bottom Arm: Positioned at bottom edge
    float lenBot = armSpace * saturate(ArmLengths.z);
    float2 botPos = float2(startX + lenBot * 0.5, -h + hth);
    float2 botSize = float2(lenBot * 0.5, hth);
    float dBot = sdBox(p - botPos, botSize);

    // 4. Combine Shapes (Union)
    float d = min(dSpine, min(dTop, min(dMid, dBot)));

    // 5. Apply Rounding
    // Subtracting radius from the union SDF rounds the outer corners
    // Note: This visually expands the shape by CornerRadius
    d -= max(CornerRadius, 0.0);

    // 6. Rendering (Anti-Aliasing & Stroke)
    // fwidth gives screen-space derivative for AA width
    float aa = fwidth(d);
    
    // Fill Alpha: 1.0 inside (d < 0), 0.0 outside
    float fillAlpha = smoothstep(aa, -aa, d);
    float4 fillColor = float4(FillColor.rgb, saturate(FillColor.a) * fillAlpha);

    // Stroke Alpha: Band around d=0
    float halfStroke = max(StrokeWidth, 0.0) * 0.5;
    float dStroke = abs(d) - halfStroke;
    float strokeAlpha = smoothstep(aa, -aa, dStroke);
    float4 strokeColor = float4(StrokeColor.rgb, saturate(StrokeColor.a) * strokeAlpha);

    // 7. Composite (Stroke Over Fill)
    outColor = letter_over(strokeColor, fillColor);
}