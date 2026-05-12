#ifndef PI
#define PI 3.14159265359
#endif

// Rotate a 2D point by angle (radians)
float2 LB_Rotate2D(float2 p, float angle) {
    float c = cos(angle);
    float s = sin(angle);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

// SDF for a line segment between points a and b with half-thickness r
float sdSegment(float2 p, float2 a, float2 b, float r) {
    float2 ab = b - a;
    float2 ap = p - a;
    float t = clamp(dot(ap, ab) / dot(ab, ab), 0.0, 1.0);
    float2 closest = a + t * ab;
    return length(p - closest) - r;
}

// SDF for a parallelogram-like oriented box segment (thick angled segment)
// Actually we use polygon SDF for the lightning bolt shape
// 6-vertex polygon for lightning bolt: upper segment + lower segment forming zigzag
float sdLightningBolt(float2 p) {
    // Lightning bolt polygon vertices (CCW order)
    // Upper segment: top-left to mid-right diagonal
    // Lower segment: mid-left to bottom-right diagonal
    // The bolt points upward, with a sharp midpoint kink
    float2 v[7];
    // Upper-left top corner
    v[0] = float2(-0.08,  0.50);
    // Upper-right top corner
    v[1] = float2( 0.20,  0.50);
    // Right side of kink (midpoint outer)
    v[2] = float2( 0.05,  0.04);
    // Bottom-right tip
    v[3] = float2( 0.22, -0.50);
    // Bottom-left point (near tip)
    v[4] = float2(-0.02, -0.50);
    // Left side of kink (midpoint inner)
    v[5] = float2(-0.12,  0.04);
    // Close back - only 6 verts
    // Dummy repeat of v[0] handled by modulo

    int N = 6;
    float d = dot(p - v[0], p - v[0]);
    float s = 1.0;

    [unroll]
    for (int i = 0; i < 6; i++) {
        int j = (i + 1) % 6;
        float2 e = v[j] - v[i];
        float2 w = p - v[i];
        float2 b = w - e * clamp(dot(w, e) / dot(e, e), 0.0, 1.0);
        d = min(d, dot(b, b));
        // Sign via winding
        bool c0 = p.y >= v[i].y;
        bool c1 = p.y <  v[j].y;
        bool c2 = e.x * w.y > e.y * w.x;
        if ((c0 && c1 && c2) || (!c0 && !c1 && !c2)) s *= -1.0;
    }

    return s * sqrt(d);
}

float4 LB_Composite(float4 top, float4 bottom) {
    float a = top.a + bottom.a * (1.0 - top.a);
    float3 rgb = (top.rgb * top.a + bottom.rgb * bottom.a * (1.0 - top.a)) / max(a, 1e-7);
    return float4(rgb, a);
}

void LightningBoltTwoSegments_float(
    float2 UV,
    float Size,
    float2 Center,
    float Rotation,
    float4 FillColor,
    float4 StrokeColor,
    float StrokeWidth,
    out float4 outColor
) {
    // 1. Center UVs
    float2 p = UV - Center;

    // 2. Rotate
    p = LB_Rotate2D(p, -Rotation);

    // 3. Scale
    float sz = max(Size, 0.0001);
    p /= sz;

    // 4. SDF
    float dist = sdLightningBolt(p);

    // 5. Anti-aliasing
    float aa = max(fwidth(dist), 0.0001);

    // 6. Fill mask
    float fillMask = smoothstep(aa, -aa, dist);
    float4 fillLayer = float4(FillColor.rgb, FillColor.a * fillMask);

    // 7. Stroke mask
    float localStroke = StrokeWidth / sz;
    float halfStroke = localStroke * 0.5;
    float strokeMask = smoothstep(halfStroke + aa, halfStroke - aa, abs(dist));
    float4 strokeLayer = float4(StrokeColor.rgb, StrokeColor.a * strokeMask);

    // 8. Composite stroke over fill
    outColor = LB_Composite(strokeLayer, fillLayer);
}