/*
  User Request: A cartoon bomb shape with a round body, a short fuse on top, and a small spark.
  Features: Adjust size (Body), Fuse Length, Spark Size. Includes a shiny highlight and proper layering.
*/

#ifndef PI
#define PI 3.14159265359
#endif

// --- Helpers ---

// Circle SDF
float cb_sdCircle(float2 p, float r) {
    return length(p) - r;
}

// Box SDF
float cb_sdBox(float2 p, float2 b) {
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// 5-Pointed Star SDF (for the spark)
float cb_sdStar5(in float2 p, in float r, in float rf) {
    const float2 k1 = float2(0.809016994375, -0.587785252292);
    const float2 k2 = float2(-k1.x, k1.y);
    p.x = abs(p.x);
    p -= 2.0 * max(dot(k1, p), 0.0) * k1;
    p -= 2.0 * max(dot(k2, p), 0.0) * k2;
    p.x = abs(p.x);
    p.y -= r;
    float2 ba = rf * float2(-k1.y, k1.x) - float2(0, 1);
    float h = clamp(dot(p, ba) / dot(ba, ba), 0.0, r);
    return length(p - ba * h) * sign(p.y * ba.x - p.x * ba.y);
}

// Quadratic Bezier SDF (exact)
float cb_sdBezier(float2 pos, float2 A, float2 B, float2 C) {
    float2 a = B - A;
    float2 b = A - 2.0 * B + C;
    float2 c = a * 2.0;
    float2 d = A - pos;
    float kk = 1.0 / dot(b, b);
    float kx = kk * dot(a, b);
    float ky = kk * (2.0 * dot(a, a) + dot(d, b)) / 3.0;
    float kz = kk * dot(d, a);
    float res = 0.0;
    float p = ky - kx * kx;
    float p3 = p * p * p;
    float q = kx * (2.0 * kx * kx - 3.0 * ky) + kz;
    float h = q * q + 4.0 * p3;

    if (h >= 0.0) {
        h = sqrt(h);
        float2 x = (float2(h, -h) - q) / 2.0;
        float2 uv = sign(x) * pow(abs(x), float2(1.0 / 3.0, 1.0 / 3.0));
        float t = clamp(uv.x + uv.y - kx, 0.0, 1.0);
        return length(d + (c + b * t) * t);
    }

    float z = sqrt(-p);
    float v = acos(q / (p * z * 2.0)) / 3.0;
    float m = cos(v);
    float n = sin(v) * 1.732050808;
    float3 t = clamp(float3(m + m, -n - m, n - m) * z - kx, 0.0, 1.0);
    float2 qx = d + (c + b * t.x) * t.x;
    float dx = dot(qx, qx);
    float2 qy = d + (c + b * t.y) * t.y;
    float dy = dot(qy, qy);
    float2 qz = d + (c + b * t.z) * t.z;
    float dz = dot(qz, qz);
    return sqrt(min(dx, min(dy, dz)));
}

// Alpha compositing helper (Source Over Destination)
float4 cb_over(float4 src, float4 dst) {
    float a = src.a + dst.a * (1.0 - src.a);
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-6);
    return float4(c, a);
}

// --- Main Function ---
void CartoonBomb_float(float2 UV, float BodySize, float FuseLength, float SparkSize, float Rotation, float4 BodyColor, float4 FuseColor, float4 SparkColor, out float4 outColor) {
    // PLAN:
    // 1. Center UVs and apply overall rotation.
    // 2. Define geometry for Body (Circle) and Neck (Box).
    // 3. Define Bezier curve for the Fuse coming out of the neck.
    // 4. Define Star SDF for the Spark at the tip of the Fuse.
    // 5. Calculate SDFs and anti-aliasing (smoothstep).
    // 6. Layer colors: Fuse -> Body -> Highlight -> Spark.
    
    // 1. Coordinates
    float2 p = UV - 0.5;
    float c = cos(Rotation);
    float s = sin(Rotation);
    p = float2(c * p.x + s * p.y, -s * p.x + c * p.y);

    // 2. Body & Neck Geometry
    // Main body
    float rBody = max(BodySize, 0.001);
    float dBody = cb_sdCircle(p, rBody);
    
    // Neck (connector for fuse)
    float2 neckSize = float2(rBody * 0.3, rBody * 0.15);
    float2 neckPos = float2(0.0, rBody);
    float dNeck = cb_sdBox(p - neckPos, neckSize * 0.5);
    
    // Combine Body and Neck
    float dMain = min(dBody, dNeck);
    float aa = fwidth(dMain);
    aa = max(aa, 0.001);

    // 3. Fuse Geometry (Bezier)
    // Starts at top of neck
    float2 fuseStart = neckPos + float2(0.0, neckSize.y * 0.5);
    // Ends somewhere up and to the right (curved)
    float fLen = max(FuseLength, 0.0);
    float2 fuseEnd = fuseStart + float2(fLen * 0.5, fLen * 0.8);
    // Control point forces it to go up first
    float2 fuseControl = fuseStart + float2(0.0, fLen);
    
    float dFuseCurve = cb_sdBezier(p, fuseStart, fuseControl, fuseEnd);
    float fuseWidth = rBody * 0.12;
    float dFuse = dFuseCurve - fuseWidth * 0.5;

    // 4. Spark Geometry
    // Star shape at the end of the fuse
    float dSpark = cb_sdStar5(p - fuseEnd, max(SparkSize, 0.0), 0.45);

    // 5. Highlight Geometry (Cartoon reflection on body)
    // A small white circle on the top-left of the body
    float2 highlightPos = float2(-rBody * 0.35, rBody * 0.35);
    float dHighlight = cb_sdCircle(p - highlightPos, rBody * 0.25);

    // 6. Compositing Layers
    
    // Layer 1: Fuse (Bottom)
    float fuseMask = 1.0 - smoothstep(0.0, aa, dFuse);
    float4 layerFuse = float4(FuseColor.rgb, FuseColor.a * fuseMask);
    
    // Layer 2: Body (Middle)
    float bodyMask = 1.0 - smoothstep(0.0, aa, dMain);
    float4 layerBody = float4(BodyColor.rgb, BodyColor.a * bodyMask);

    // Layer 2b: Highlight (Additive or Overlay on Body)
    // Only show highlight where body exists
    float highlightMask = 1.0 - smoothstep(0.0, aa * 2.0, dHighlight); // Softer edge
    float4 layerHighlight = float4(1.0, 1.0, 1.0, 0.4 * highlightMask); // Semi-transparent white
    // Composite highlight onto body
    layerBody = cb_over(layerHighlight, layerBody);
    // Mask again to ensure it stays inside body shape (clean edges)
    layerBody.a *= bodyMask;

    // Layer 3: Spark (Top)
    float sparkMask = 1.0 - smoothstep(0.0, aa, dSpark);
    float4 layerSpark = float4(SparkColor.rgb, SparkColor.a * sparkMask);

    // Final Composition (Bottom-up: Fuse -> Body -> Spark)
    float4 comp = layerFuse;
    comp = cb_over(layerBody, comp);
    comp = cb_over(layerSpark, comp);

    outColor = comp;
}