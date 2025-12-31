#ifndef PI
#define PI 3.14159265359
#endif

// --- Helper Functions ---

// 2D Rotation
float2 rotate(float2 p, float a) {
    float c = cos(a), s = sin(a);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

// Smooth Minimum for blending shapes
float smin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / max(k, 0.001), 0.0, 1.0);
    return lerp(b, a, h) - k * h * (1.0 - h);
}

// Squared length
float dot2(float2 v) { return dot(v, v); }

// SDF for an Axis-Aligned Ellipse (Approximation for performance, good for convex)
float sdEllipse(float2 p, float2 ab) {
    // Symmetry
    p = abs(p);
    if (p.x > p.y) { p = p.yx; ab = ab.yx; }
    
    // Approximate distance
    float l = ab.y * ab.y - ab.x * ab.x;
    float m = ab.x * p.x / l;
    float m2 = m * m;
    float n = ab.y * p.y / l;
    float n2 = n * n;
    float c = (m2 + n2 - 1.0) / 3.0;
    float c3 = c * c * c;
    float q = c3 + m2 * n2 * 2.0;
    float d = c3 + m2 * n2;
    float g = m + m * n2;
    float co;
    
    if (d < 0.0) {
        float h = acos(q / c3) / 3.0;
        float s = cos(h);
        float t = sin(h) * sqrt(3.0);
        float rx = sqrt(-c * (s + t + 2.0) + m2);
        float ry = sqrt(-c * (s - t + 2.0) + m2);
        co = (ry + sign(l) * rx + abs(g) / (rx * ry) - m) / 2.0;
    } else {
        float h = 2.0 * m * n * sqrt(d);
        float s = sign(q + h) * pow(abs(q + h), 1.0 / 3.0);
        float u = sign(q - h) * pow(abs(q - h), 1.0 / 3.0);
        float rx = -s - u - c * 4.0 + 2.0 * m2;
        float ry = (s - u) * sqrt(3.0);
        float rm = sqrt(rx * rx + ry * ry);
        co = (ry / sqrt(rm - rx) + 2.0 * g / rm - m) / 2.0;
    }
    
    float2 r = ab * float2(co, sqrt(1.0 - co * co));
    return length(r - p) * sign(p.y - r.y);
}

// SDF for Quadratic Bezier Curve (Unsigned distance)
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
        float2 uv = sign(x) * pow(abs(x), float2(1.0 / 3.0, 1.0 / 3.0));
        float t = clamp(uv.x + uv.y - kx, 0.0, 1.0);
        res = dot2(d + (c + b * t) * t);
    } else {
        float z = sqrt(-p);
        float v = acos(q / (p * z * 2.0)) / 3.0;
        float m = cos(v);
        float n = sin(v) * 1.732050808;
        float3 t = clamp(float3(m + m, -n - m, n - m) * z - kx, 0.0, 1.0);
        res = min(dot2(d + (c + b * t.x) * t.x), dot2(d + (c + b * t.y) * t.y));
    }
    return sqrt(res);
}

// SDF for a Segment (Stem)
float sdSegment(float2 p, float2 a, float2 b) {
    float2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}

// --- Main Function ---
// Generates a cartoon beetroot with adjustable root body, tip, leaves, and outline.
void CartoonBeetroot_float(float2 UV, float RootWidth, float RootHeight, float4 RootColor, 
                          float TipLength, float TipCurvature, 
                          float LeafCount, float StemLength, float SpreadAngle, float LeafWaviness, float4 LeafColor, 
                          float HighlightSize, float StrokeThickness, float4 StrokeColor, 
                          out float4 outColor) {
    
    // 1. Center and Scale Coordinates
    float2 p = (UV - 0.5) * 2.0;
    float aa = fwidth(length(p)); // Antialiasing factor
    float strokeHalf = StrokeThickness * 0.5;

    // --- LEAF GENERATION ---
    // Compute SDF for the cluster of leaves first (they go behind the root)
    float dLeaves = 1000.0;
    float safeLeafCount = floor(clamp(LeafCount, 0.0, 12.0));
    float2 pLeavesOrigin = p - float2(0.0, RootHeight * 0.85); // Leaves emerge from top of root

    if (safeLeafCount > 0.5) {
        for (float i = 0.0; i < safeLeafCount; i++) {
            // Calculate angle for this leaf
            float t = (safeLeafCount > 1.0) ? (i / (safeLeafCount - 1.0)) : 0.5;
            float angle = lerp(-SpreadAngle * 0.5, SpreadAngle * 0.5, t);
            
            // Rotate coordinate space for this leaf
            float2 pLeaf = rotate(pLeavesOrigin, angle);
            
            // Stem SDF
            float dStem = sdSegment(pLeaf, float2(0.0, 0.0), float2(0.0, StemLength)) - 0.01; // Thin stem
            
            // Leaf Blade SDF
            // Shift to end of stem
            float2 pBlade = pLeaf - float2(0.0, StemLength);
            // Add waviness
            pBlade.x += sin(pBlade.y * 15.0) * LeafWaviness * 0.1;
            // Blade shape (elongated ellipse)
            float dBlade = sdEllipse(pBlade - float2(0.0, 0.15), float2(0.12, 0.25));
            
            // Union Stem and Blade
            float dThisLeaf = min(dStem, dBlade);
            dLeaves = min(dLeaves, dThisLeaf);
        }
    }

    // --- ROOT BODY GENERATION ---
    // 1. Main Bulb (Ellipse)
    // Slightly tapered at bottom by modifying width based on y
    float taper = 1.0 + 0.2 * smoothstep(0.0, -RootHeight, p.y);
    float dBody = sdEllipse(p * float2(1.0 / taper, 1.0), float2(RootWidth, RootHeight));
    
    // 2. Root Tip (Bezier)
    // Tip starts at bottom of body, curves slightly
    float2 tipStart = float2(0.0, -RootHeight * 0.95);
    float2 tipEnd = float2(0.0, -RootHeight - TipLength);
    float2 tipControl = float2(TipCurvature * 0.5, -RootHeight - TipLength * 0.5);
    float dTip = sdBezier(p, tipStart, tipControl, tipEnd) - (0.01 + 0.03 * smoothstep(tipEnd.y, tipStart.y, p.y));
    
    // 3. Combine Body and Tip smoothly
    float dRoot = smin(dBody, dTip, 0.08);

    // --- HIGHLIGHT GENERATION ---
    // Reflection on the root body
    float2 pHigh = rotate(p - float2(-RootWidth * 0.4, RootHeight * 0.3), -0.5);
    float dHigh = sdEllipse(pHigh, float2(HighlightSize * 1.5, HighlightSize * 0.6));
    float highlightMask = smoothstep(0.01, -0.01, dHigh);

    // --- COMPOSITING AND RENDERING ---
    // We have two main layers: Leaves (Back) and Root (Front)
    
    // 1. Render Leaves
    float leafAlpha = smoothstep(0.0, -aa, dLeaves);
    float leafStroke = smoothstep(strokeHalf + aa, strokeHalf - aa, abs(dLeaves)); // Stroke band
    // Normally stroke is drawn on edge. Here we composite: Fill then Stroke.
    // Or simpler: Calculate stroke factor and mix.
    float4 colLeaf = float4(LeafColor.rgb, leafAlpha * LeafColor.a);
    // Apply stroke to leaf
    float leafBorderMask = smoothstep(strokeHalf, strokeHalf - aa, abs(dLeaves)); // Inner and outer
    // For cartoon style, outline is usually distinct. 
    // Let's assume Outline is drawn OVER the fill.
    float leafOutlineAlpha = smoothstep(strokeHalf, strokeHalf - aa, abs(dLeaves));
    // Composite Leaf Stroke over Leaf Fill
    colLeaf.rgb = lerp(colLeaf.rgb, StrokeColor.rgb, leafOutlineAlpha);
    colLeaf.a = max(colLeaf.a, leafOutlineAlpha * StrokeColor.a);

    // 2. Render Root
    float rootAlpha = smoothstep(0.0, -aa, dRoot);
    float rootOutlineAlpha = smoothstep(strokeHalf, strokeHalf - aa, abs(dRoot));
    
    float4 colRoot = float4(RootColor.rgb, rootAlpha * RootColor.a);
    // Apply Highlight to Root Fill (masked by root alpha so it doesn't spill)
    colRoot.rgb = lerp(colRoot.rgb, float3(1.0, 1.0, 1.0), highlightMask * 0.8 * rootAlpha);
    // Apply Stroke to Root
    colRoot.rgb = lerp(colRoot.rgb, StrokeColor.rgb, rootOutlineAlpha);
    colRoot.a = max(colRoot.a, rootOutlineAlpha * StrokeColor.a);

    // 3. Final Composite (Root over Leaves)
    // Standard Alpha Blending: Out = Src * SrcA + Dst * (1 - SrcA)
    float4 finalColor = float4(0.0, 0.0, 0.0, 0.0);
    
    // Start with Leaf
    finalColor = colLeaf;
    
    // Blend Root over Leaf
    float srcA = colRoot.a;
    float3 outRGB = colRoot.rgb * srcA + finalColor.rgb * finalColor.a * (1.0 - srcA);
    float outA = srcA + finalColor.a * (1.0 - srcA);
    
    // Un-premultiply for final output (if needed) or keep premultiplied.
    // Unity ShaderGraph usually expects straight alpha if mixing node is used, 
    // but here we output a single composed color.
    // We will output straight alpha approximation: RGB / A.
    if (outA > 0.001) {
        outRGB /= outA;
    }
    
    outColor = float4(outRGB, outA);
}