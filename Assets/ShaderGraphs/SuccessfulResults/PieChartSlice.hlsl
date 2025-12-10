#ifndef PI
#define PI 3.14159265359
#endif

// SDF for a Pie Slice (Angular Sector)
// p: sampling point (centered)
// c: sin/cos of the half-aperture angle
// r: radius of the slice
// Returns: Signed Distance (negative inside)
float sdPie_PieSlice(float2 p, float2 c, float r) {
    p.x = abs(p.x);
    float l = length(p) - r;
    float m = length(p - c * clamp(dot(p, c), 0.0, r));
    return max(l, m * sign(c.y * p.x - c.x * p.y));
}

// Blend function: Source Over Destination (Straight Alpha)
float4 over_PieSlice(float4 src, float4 dst) {
    float a = src.a + dst.a * (1.0 - src.a);
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-8);
    return float4(c, a);
}

void PieChartSlice_float(float2 UV, float2 Center, float Radius, float StartAngleRad, float SweepAngleRad, float4 FillColor, float4 StrokeColor, float StrokeWidth, out float4 outColor) {
    // PLAN:
    // 1) Recenter UV coordinates to the pie center.
    // 2) Calculate the bisector angle of the slice (MidAngle).
    // 3) Rotate the coordinate system so the slice aligns with the Y-axis (required for the SDF).
    // 4) Compute the SDF using the half-sweep angle.
    // 5) Generate anti-aliased masks for fill and stroke.
    // 6) Composite stroke over fill.

    // 1. Recenter
    float2 p = UV - Center;

    // 2. Compute Angles
    // Clamp sweep to a safe range (0 to almost 360) to prevent artifacts at exactly 360 if unstable
    // But standard SDF holds up well. We ensure it's positive.
    float sweep = max(SweepAngleRad, 0.0);
    float halfSweep = sweep * 0.5;
    float midAngle = StartAngleRad + halfSweep;

    // 3. Rotation
    // We want the MidAngle to map to the UP vector (0, 1), which is PI/2 radians.
    // We rotate the point 'p' by (PI/2 - MidAngle).
    float rotAngle = 0.5 * PI - midAngle;
    float cRot = cos(rotAngle);
    float sRot = sin(rotAngle);
    // Apply 2D rotation matrix
    p = float2(cRot * p.x - sRot * p.y, sRot * p.x + cRot * p.y);

    // 4. Calculate SDF
    // cPie is the sin/cos of the half-aperture for the symmetric SDF
    float2 cPie = float2(sin(halfSweep), cos(halfSweep));
    float dist = sdPie_PieSlice(p, cPie, Radius);

    // 5. Anti-aliasing
    float aa = fwidth(dist);
    
    // Fill Mask (Inner shape)
    float fillMask = 1.0 - smoothstep(0.0, aa, dist);
    float4 fillLayer = float4(FillColor.rgb, saturate(FillColor.a) * fillMask);

    // Stroke Mask (Border)
    float halfStroke = max(StrokeWidth, 0.0) * 0.5;
    float edgeDist = abs(dist) - halfStroke;
    float strokeMask = 1.0 - smoothstep(0.0, aa, edgeDist);
    float4 strokeLayer = float4(StrokeColor.rgb, saturate(StrokeColor.a) * strokeMask);

    // 6. Composition
    outColor = over_PieSlice(strokeLayer, fillLayer);
}