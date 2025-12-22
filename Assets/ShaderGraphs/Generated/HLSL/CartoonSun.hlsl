#ifndef PI
#define PI 3.14159265359
#endif

// Helper: Modulo that handles negatives correctly (unlike fmod)
float nm_mod(float x, float y) {
    return x - y * floor(x / y);
}

// Helper: Signed Distance to Isosceles Triangle (Inigo Quilez)
// q.x = half width, q.y = height
// Triangle tip at (0,0), base at y = q.y
float sdIsosceles(float2 p, float2 q) {
    p.x = abs(p.x);
    float2 a = p - q * clamp(dot(p, q) / dot(q, q), 0.0, 1.0);
    float2 b = p - q * float2(clamp(p.x / q.x, 0.0, 1.0), 1.0);
    float k = sign(q.y);
    float d = min(dot(a, a), dot(b, b));
    float s = max(k * (p.x * q.y - p.y * q.x), k * (p.y - q.y));
    return sqrt(d) * sign(s);
}

// Helper: Alpha blending (Src Over Dst)
float4 blendOver(float4 src, float4 dst) {
    float outA = src.a + dst.a * (1.0 - src.a);
    float3 outRGB = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(outA, 1e-5);
    return float4(outRGB, outA);
}

void CartoonSun_float(float2 UV, float SunRadius, float4 SunColor, float RayCount, float RayLength, float RayWidth, float RayGap, float4 RayColor, float Rotation, out float4 outColor) {
    // PLAN:
    // 1) Center UV coordinates.
    // 2) Calculate SDF for the central sun circle.
    // 3) Calculate SDF for the rays using angular repetition (polar coordinates).
    //    - Rotate space by Rotation parameter.
    //    - Divide space into N sectors.
    //    - Align each sector to X-axis.
    //    - Shift x by (SunRadius + Gap) to separate rays from body.
    //    - Use Triangle SDF for the ray shape.
    // 4) Compute anti-aliased masks for both shapes.
    // 5) Composite the rays and the sun body.

    float2 p = UV - 0.5;

    // --- 1. Sun Body (Circle) ---
    float dBody = length(p) - SunRadius;
    float aa = 0.005; // Fixed AA width for stability
    float maskBody = smoothstep(aa, -aa, dBody);
    float4 layerBody = float4(SunColor.rgb * maskBody, maskBody * SunColor.a);

    // --- 2. Sun Rays (Triangles) ---
    // Rotate global space
    float c = cos(Rotation);
    float s = sin(Rotation);
    float2 pRot = float2(c * p.x - s * p.y, s * p.x + c * p.y);

    // Polar Coordinates for repetition
    float an = 2.0 * PI / max(1.0, floor(RayCount));
    float angle = atan2(pRot.y, pRot.x);
    float r = length(pRot);

    // Sector repetition: center the sector around angle 0
    float sectorAngle = nm_mod(angle + PI + an * 0.5, an) - an * 0.5;

    // Convert back to Cartesian local to the ray
    // This aligns the ray along the positive X axis
    float2 pRay = float2(cos(sectorAngle), sin(sectorAngle)) * r;

    // Offset ray start position (separation from sun surface)
    pRay.x -= (SunRadius + RayGap);

    // Transform to align with sdIsosceles expectations
    // We want: Ray Base at x=0, Ray Tip at x=RayLength
    // sdIsosceles expects: Tip at (0,0), Base at y=height
    // Transformation: Map Ray Tip (L, 0) -> (0,0) and Ray Base (0, 0) -> (0, L)
    // New X = old Y (width axis), New Y = RayLength - old X (height axis)
    float2 pTri = float2(pRay.y, RayLength - pRay.x);

    // Calculate Triangle SDF
    float dRay = sdIsosceles(pTri, float2(RayWidth * 0.5, RayLength));
    
    // Mask for rays
    float maskRay = smoothstep(aa, -aa, dRay);
    float4 layerRay = float4(RayColor.rgb * maskRay, maskRay * RayColor.a);

    // --- 3. Composition ---
    // Draw Body OVER Rays (standard painter's algorithm)
    // This ensures that if the gap is negative, the sun covers the ray roots cleanly.
    outColor = blendOver(layerBody, layerRay);
}