#ifndef PI
#define PI 3.14159265359
#endif

// --- Helpers ---

// 2D Rotation
float2 rotate(float2 p, float angle) {
    float c = cos(angle);
    float s = sin(angle);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

// Quadratic Bezier SDF
float sdBezier(float2 pos, float2 A, float2 B, float2 C) {
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
        float2 uv = sign(x) * pow(abs(x), 1.0 / 3.0);
        float t = clamp(uv.x + uv.y - kx, 0.0, 1.0);
        res = length(d + (c + b * t) * t);
    } else {
        float z = sqrt(-p);
        float v = acos(q / (p * z * 2.0)) / 3.0;
        float m = cos(v);
        float n = sin(v) * 1.732050808;
        float3 t = clamp(float3(m + m, -n - m, n - m) * z - kx, 0.0, 1.0);
        res = min(dot2(d + (c + b * t.x) * t.x),
                  dot2(d + (c + b * t.y) * t.y));
        // The third root is usually not needed for distance but kept for completeness in some implementations
        // Simplified here to standard IQ version
        res = sqrt(min(res, dot2(d + (c + b * t.z) * t.z)));
    }
    return res;
}

// Fallback simple Bezier if the above is too heavy or causes issues in some HLSL compilers
// Using a simpler estimation or segment approximation is often safer for UI elements
// Re-implementing a robust simple version:
float dot2(float2 v) { return dot(v, v); }
float sdBezierSimple(float2 pos, float2 A, float2 B, float2 C) {
    float2 a = B - A; 
    float2 b = A - 2.0*B + C; 
    float2 c = a * 2.0; 
    float2 d = A - pos; 
    float kk = 1.0/dot(b,b); 
    float kx = kk * dot(a,b); 
    float ky = kk * (2.0*dot(a,a)+dot(d,b)) / 3.0; 
    float kz = kk * dot(d,a);      
    float res = 0.0;
    float p = ky - kx*kx; 
    float p3 = p*p*p; 
    float q = kx*(2.0*kx*kx-3.0*ky) + kz; 
    float h = q*q + 4.0*p3;
    if( h >= 0.0) { 
        h = sqrt(h); 
        float2 x = (float2(h,-h)-q)/2.0; 
        float2 uv = sign(x)*pow(abs(x), float2(1.0/3.0, 1.0/3.0)); 
        float t = clamp( uv.x+uv.y-kx, 0.0, 1.0 ); 
        res = length(d+(c+b*t)*t); 
    } else { 
        float z = sqrt(-p); 
        float v = acos( q/(p*z*2.0) ) / 3.0; 
        float m = cos(v); 
        float n = sin(v)*1.732050808; 
        float3 t = clamp(float3(m+m,-n-m,n-m)*z-kx, 0.0, 1.0); 
        res = min( dot2(d+(c+b*t.x)*t.x), dot2(d+(c+b*t.y)*t.y) ); 
        res = sqrt( min(res, dot2(d+(c+b*t.z)*t.z)) ); 
    }
    return res;
}

// Signed distance to a trapezoid (isosceles)
// wBottom: half width at bottom, wTop: half width at top, h: half height
float sdTrapezoid(float2 p, float wBottom, float wTop, float h) {
    p.x = abs(p.x);
    float k1 = wBottom;
    float k2 = wTop - wBottom;
    float k3 = 2.0 * h;
    
    // Side edge
    float2 e = float2(k2, k3);
    float2 q = p - float2(k1, -h);
    float2 d = q - e * clamp(dot(q, e) / dot(e, e), 0.0, 1.0);
    float s = -1.0;
    if (q.x > e.x * q.y / e.y) s = 1.0;
    
    // Top/Bottom edges
    // Simplification: box intersection logic for Y
    float dEdge = length(d) * s;
    
    // Combine with top/bottom planes
    // Usually simpler to just use segment distance for the side and combine with y bounds
    // But for solid shape:
    if (p.y > h) dEdge = max(dEdge, p.y - h);
    if (p.y < -h) dEdge = max(dEdge, -h - p.y);
    
    return dEdge;
}

// Segment SDF
float sdSegment(float2 p, float2 a, float2 b) {
    float2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}

// Main Shape Function
// Draws a cartoon pastry piping bag with adjustable parameters
void CartoonPastryBag_float(float2 UV, float BodyWidth, float BodyLength, float4 BagColor, float TailSize, float TailAngle, float2 NozzleSize, float4 NozzleColor, float4 ApertureColor, float StrokeWidth, float4 StrokeColor, out float4 outColor) {
    // 1. Setup Coordinates
    float2 p = UV - 0.5;
    float aa = fwidth(length(p)); // Anti-aliasing factor
    
    // Dimensions half-sizes
    float wBodyTop = BodyWidth * 0.5;
    float wBodyBot = NozzleSize.x * 0.5;
    float hBody = BodyLength * 0.5;
    float hNozzle = NozzleSize.y * 0.5;
    float wNozzleBot = NozzleSize.x * 0.2; // Nozzle tip is narrower
    
    // Vertical Offsets to stack components
    // Center the main body at (0,0)
    float yTie = hBody;
    float yNozzle = -hBody - hNozzle;
    
    // 2. SDF Definitions
    
    // --- Body ---
    // Inflated look: subtract a bit from the sides or use rounded trapezoid
    // Standard trapezoid for the main volume
    float dBody = sdTrapezoid(p, wBodyBot, wBodyTop, hBody);
    // Round the body slightly for "inflated" look
    dBody -= 0.02;
    
    // --- Nozzle ---
    float2 pNozzle = p - float2(0.0, yNozzle);
    float dNozzle = sdTrapezoid(pNozzle, wNozzleBot, wBodyBot, hNozzle);
    
    // --- Tie (Closure) ---
    // Small rounded capsule at the top of the body
    float2 pTie = p - float2(0.0, yTie);
    float dTie = length(max(abs(pTie) - float2(wBodyTop * 0.8, 0.015), 0.0)) - 0.015;
    
    // --- Tail (Fanned Ruffles) ---
    // Positioned above the tie
    float2 pTail = p - float2(0.0, yTie + 0.02);
    // Convert to polar for fan shape
    float angle = atan2(pTail.x, pTail.y); // 0 is Up
    float r = length(pTail);
    // Ruffled edge: sine wave added to radius
    float ruffle = sin(angle * 20.0) * 0.03 * TailSize * 5.0;
    // Sector SDF: distance to radius bounds and angle bounds
    float dTail = max(r - TailSize - ruffle, abs(angle) - TailAngle);
    
    // --- Aperture (Hole at nozzle tip) ---
    float2 pAperture = p - float2(0.0, yNozzle - hNozzle);
    float dAperture = length(pAperture / float2(1.0, 0.5)) - wNozzleBot * 0.6;
    
    // --- Creases (Volume Lines) ---
    // Curved lines on the body to show volume
    // Left crease
    float dCrease1 = sdBezierSimple(p, float2(-wBodyTop*0.6, hBody*0.3), float2(-wBodyTop*0.2, 0.0), float2(-wBodyBot*0.8, -hBody*0.4));
    // Right crease
    float dCrease2 = sdBezierSimple(p, float2(wBodyTop*0.5, hBody*0.5), float2(wBodyTop*0.3, 0.0), float2(wBodyBot*0.5, -hBody*0.3));
    float dCreases = min(dCrease1, dCrease2);

    // 3. Rendering Layers
    
    float4 col = float4(0,0,0,0);
    
    // Layer 1: Tail (Behind)
    float maskTail = smoothstep(aa, -aa, dTail);
    col = lerp(col, BagColor, maskTail);
    
    // Layer 2: Nozzle
    float maskNozzle = smoothstep(aa, -aa, dNozzle);
    col = lerp(col, NozzleColor, maskNozzle);
    
    // Layer 3: Body
    float maskBody = smoothstep(aa, -aa, dBody);
    col = lerp(col, BagColor, maskBody);
    
    // Layer 4: Tie
    float maskTie = smoothstep(aa, -aa, dTie);
    // Darken tie slightly for contrast
    float4 tieColor = BagColor * 0.9;
    tieColor.a = BagColor.a;
    col = lerp(col, tieColor, maskTie);
    
    // Layer 5: Aperture
    float maskAperture = smoothstep(aa, -aa, dAperture);
    col = lerp(col, ApertureColor, maskAperture);
    
    // 4. Strokes & Outlines
    
    // Combine shapes for the main silhouette outline
    float dUnion = min(dBody, min(dTail, min(dTie, dNozzle)));
    float maskOutline = smoothstep(StrokeWidth, StrokeWidth - aa, abs(dUnion));
    // Only draw outline where there is shape (dUnion < 0 roughly)
    // Actually we want the outline centered on the edge (d=0)
    // But we want to composite it OVER the colors.
    // Mask for the stroke itself:
    float strokeAlpha = smoothstep(StrokeWidth + aa, StrokeWidth, abs(dUnion)); // 0 outside stroke, 1 inside
    // We want a standard stroke: 1.0 where |d| < width
    float strokeFactor = 1.0 - smoothstep(StrokeWidth - aa, StrokeWidth + aa, abs(dUnion));
    
    // Crease strokes
    float creaseFactor = 1.0 - smoothstep(StrokeWidth*0.5 - aa, StrokeWidth*0.5 + aa, dCreases);
    // Clip creases to body
    creaseFactor *= maskBody;
    
    // Apply Creases
    col = lerp(col, StrokeColor, creaseFactor);
    
    // Apply Main Outline
    col = lerp(col, StrokeColor, strokeFactor);
    
    // Apply Aperture Outline (optional detail)
    float apertureStroke = 1.0 - smoothstep(StrokeWidth*0.5 - aa, StrokeWidth*0.5 + aa, abs(dAperture));
    col = lerp(col, StrokeColor, apertureStroke);

    // Final Alpha: The shape exists where dUnion < StrokeWidth
    float alpha = smoothstep(StrokeWidth, StrokeWidth - aa, dUnion);
    col.a = saturate(alpha + strokeFactor);
    
    // Ensure straight alpha output for blending if needed, or pre-multiplied logic
    // Here we output standard RGBA
    outColor = col;
}