#ifndef PI
#define PI 3.14159265359
#endif

// --- Helper Functions ---

// Smooth Min (Soft Union)
float smin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / max(k, 0.0001), 0.0, 1.0);
    return lerp(b, a, h) - k * h * (1.0 - h);
}

// Rounded Box SDF
float sdRoundBox(float2 p, float2 b, float r) {
    float2 q = abs(p) - b + r;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

// Uneven Rounded Box SDF (different radii per corner)
// r: top-right, bottom-right, top-left, bottom-left
float sdRoundBox4(float2 p, float2 b, float4 r) {
    float rad = (p.x > 0.0) ? ( (p.y > 0.0) ? r.x : r.y ) : ( (p.y > 0.0) ? r.z : r.w );
    float2 q = abs(p) - b + rad;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - rad;
}

// Approximate Ellipse SDF
float sdEllipseApprox(float2 p, float2 r) {
    float k0 = length(p / max(r, 0.0001));
    return (k0 - 1.0) * min(r.x, r.y);
}

// Seed SDF with rotation
float sdSeed(float2 p, float2 center, float angle, float2 size) {
    float2 q = p - center;
    float c = cos(angle), s = sin(angle);
    q = float2(c * q.x + s * q.y, -s * q.x + c * q.y);
    return sdEllipseApprox(q, size);
}

// Composite Source Over Destination
float4 compositeOver(float4 src, float4 dst) {
    float a = src.a + dst.a * (1.0 - src.a);
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-6);
    return float4(c, a);
}

// Render a shape layer with fill and outline stroke
float4 renderLayer(float d, float4 fillColor, float4 strokeColor, float strokeWidth, float aa) {
    // Inner Fill
    float fillMask = 1.0 - smoothstep(0.0, aa, d);
    float4 fillOut = float4(fillColor.rgb, saturate(fillColor.a) * fillMask);
    
    // Outer Stroke
    float halfStroke = strokeWidth * 0.5;
    float strokeMask = 1.0 - smoothstep(0.0, aa, abs(d) - halfStroke);
    float4 strokeOut = float4(strokeColor.rgb, saturate(strokeColor.a) * strokeMask);
    
    // Stroke over Fill to ensure sharp internal boundary
    return compositeOver(strokeOut, fillOut);
}

// --- Main Function ---
void Burger_float(
    float2 UV,
    float2 Center,
    float Scale,
    float4 BunColor,
    float4 LettuceColor,
    float4 PattyColor,
    float4 SeedColor,
    float4 OutlineColor,
    float OutlineWidth,
    float SeedCount,
    float SeedSize,
    out float4 outColor
) {
    // 1. Setup Coordinate Space
    float2 p = UV - Center;
    p /= max(Scale, 0.001);
    
    // Analytic anti-aliasing factor
    float aa = max(fwidth(p.x) * 1.5, 0.001);
    
    // Initialize transparent background
    outColor = float4(0.0, 0.0, 0.0, 0.0);
    
    // 2. Bottom Bun
    // Flat top, rounded bottom corners
    float dBottom = sdRoundBox4(p - float2(0.0, -0.26), float2(0.34, 0.07), float4(0.03, 0.07, 0.03, 0.07));
    float4 bottomLayer = renderLayer(dBottom, BunColor, OutlineColor, OutlineWidth, aa);
    outColor = compositeOver(bottomLayer, outColor);
    
    // 3. Patty
    // Standard rounded rectangle
    float dPatty = sdRoundBox(p - float2(0.0, -0.15), float2(0.36, 0.05), 0.03);
    float4 pattyLayer = renderLayer(dPatty, PattyColor, OutlineColor, OutlineWidth, aa);
    outColor = compositeOver(pattyLayer, outColor);
    
    // 4. Lettuce
    // Wavy flared bottom, straight top
    float2 qLet = p - float2(0.0, -0.07);
    // Interpolator for the bottom half distortion
    float tLet = smoothstep(0.04, -0.04, qLet.y);
    // Apply sine wave displacement to bottom edge
    float wave = sin(qLet.x * 25.0) * 0.018 * tLet;
    qLet.y -= wave;
    // Flare outwards at the bottom
    qLet.x = abs(qLet.x);
    qLet.x -= tLet * 0.03;
    
    float dLettuce = sdRoundBox(qLet, float2(0.38, 0.04), 0.02);
    dLettuce *= 0.8; // Gradient correction for domain distortion safety
    
    float4 lettuceLayer = renderLayer(dLettuce, LettuceColor, OutlineColor, OutlineWidth, aa);
    outColor = compositeOver(lettuceLayer, outColor);
    
    // 5. Top Bun
    // Smooth composite dome: Semi-ellipse unioned with a straight flat base
    float2 localTop = p - float2(0.0, 0.10);
    float dEl = sdEllipseApprox(localTop - float2(0.0, -0.05), float2(0.36, 0.20));
    float dBox = sdRoundBox(localTop - float2(0.0, -0.11), float2(0.36, 0.04), 0.04);
    float dTop = smin(dEl, dBox, 0.02);
    
    float4 topLayer = renderLayer(dTop, BunColor, OutlineColor, OutlineWidth, aa);
    outColor = compositeOver(topLayer, outColor);
    
    // 6. Seeds
    // Placed procedurally across the top bun dome
    float seedSizeX = 0.012 * max(SeedSize, 0.001);
    float seedSizeY = 0.025 * max(SeedSize, 0.001);
    float2 seedDims = float2(seedSizeX, seedSizeY);
    
    float dSeeds = 1e9;
    int sCount = int(round(SeedCount));
    
    if (sCount == 1 || sCount >= 3) {
        // Center-top seed
        dSeeds = min(dSeeds, sdSeed(p, float2(0.0, 0.20), 0.0, seedDims));
    }
    if (sCount >= 2) {
        // Left and Right angled seeds
        dSeeds = min(dSeeds, sdSeed(p, float2(-0.16, 0.16), -0.5, seedDims));
        dSeeds = min(dSeeds, sdSeed(p, float2(0.16, 0.15), 0.5, seedDims));
    }
    
    // Seeds are drawn as solid fills (no outline required)
    float seedMask = 1.0 - smoothstep(0.0, aa, dSeeds);
    float4 seedLayer = float4(SeedColor.rgb, saturate(SeedColor.a) * seedMask);
    outColor = compositeOver(seedLayer, outColor);
}
