#ifndef PI
#define PI 3.14159265359
#endif

// Helper: Calculate signed distance to a 2D parallelogram
// wi: half-width, he: half-height, sk: skew offset
float sdParallelogram_Helper(float2 p, float wi, float he, float sk)
{
    float2 e = float2(sk, he);
    if (p.y < 0.0) p = -p;
    
    float2 w = p - e; 
    w.x -= clamp(w.x, -wi, wi);
    float2 d = float2(dot(w, w), -w.y);
    
    float s = p.x * e.y - p.y * e.x;
    if (s < 0.0) p = -p;
    
    float2 v = p - float2(wi, 0.0); 
    v -= e * clamp(dot(v, e) / dot(e, e), -1.0, 1.0);
    
    d = min(d, float2(dot(v, v), wi * he - abs(s)));
    return sqrt(d.x) * sign(-d.y);
}

// Helper: Alpha Blending (Source Over Destination)
float4 blendColors_Helper(float4 src, float4 dst)
{
    float a = src.a + dst.a * (1.0 - src.a);
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-8);
    return float4(c, a);
}

void Parallelogram_float(
    float2 UV,
    float Width,
    float Height,
    float SkewAngle,
    float2 Center,
    float Rotation,
    float4 FillColor,
    float4 StrokeColor,
    float StrokeWidth,
    out float4 outColor
)
{
    // 1. Center & Rotate Space
    float2 p = UV - Center;
    float c = cos(Rotation);
    float s = sin(Rotation);
    // Rotate coordinate system by -Rotation to rotate shape by +Rotation
    p = float2(c * p.x + s * p.y, -s * p.x + c * p.y);

    // 2. Prepare Parallelogram Parameters
    float wi = max(Width * 0.5, 0.0);
    float he = max(Height * 0.5, 1e-4); // Prevent division by zero
    
    // Calculate horizontal skew offset based on angle (clamped to prevent infinity)
    float clampedSkew = clamp(SkewAngle, -85.0, 85.0);
    float sk = he * tan(clampedSkew * PI / 180.0);

    // 3. SDF Calculation
    float dist = sdParallelogram_Helper(p, wi, he, sk);

    // 4. Anti-Aliasing & Masking
    float aa = fwidth(dist);
    
    // Fill Mask: Distance < 0 is inside
    float fillMask = 1.0 - smoothstep(0.0, aa, dist);
    
    // Stroke Mask: Centered on the edge boundary (dist == 0)
    float halfStroke = max(StrokeWidth, 0.0) * 0.5;
    float strokeDist = abs(dist) - halfStroke;
    float strokeMask = 1.0 - smoothstep(0.0, aa, strokeDist);

    // 5. Apply Colors
    float4 fill = float4(FillColor.rgb, saturate(FillColor.a) * fillMask);
    float4 stroke = float4(StrokeColor.rgb, saturate(StrokeColor.a) * strokeMask);

    // 6. Composite (Stroke Over Fill)
    outColor = blendColors_Helper(stroke, fill);
}
