#ifndef PI
#define PI 3.14159265359
#endif

// 2D Rotation Helper
float2 rotate2D(float2 p, float angle) {
    float c = cos(angle);
    float s = sin(angle);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

// Smooth Minimum Helper (for blending stem to leaves)
float smin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return lerp(b, a, h) - k * h * (1.0 - h);
}

// Signed Distance to a Heart (Tip at 0,0, lobes pointing +Y)
// Based on Inigo Quilez's formula, centered to have tip at origin.
float sdHeart(float2 p) {
    p.x = abs(p.x);
    // This formula creates a heart fitting roughly in unit circle
    // Tip is at (0,0). Lobes extend upwards.
    if(p.y + p.x > 1.0)
        return sqrt(dot(p - float2(0.25, 0.75), p - float2(0.25, 0.75))) - sqrt(2.0)/4.0;
    return sqrt(min(dot(p - float2(0.00, 1.00), p - float2(0.00, 1.00)),
                    dot(p - 0.5 * max(p.x + p.y, 0.0), p - 0.5 * max(p.x + p.y, 0.0)))) * sign(p.x - p.y);
}

// Signed Distance to Quadratic Bezier (Stem)
// A=Start, B=Control, C=End
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
        return length(d + (c + b * t) * t);
    } else {
        float z = sqrt(-p);
        float v = acos(q / (p * z * 2.0)) / 3.0;
        float m = cos(v);
        float n = sin(v) * 1.732050808;
        float3 t = clamp(float3(m + m, -n - m, n - m) * z - kx, 0.0, 1.0);
        return sqrt(min(dot(d + (c + b * t.x) * t.x, d + (c + b * t.x) * t.x),
                    min(dot(d + (c + b * t.y) * t.y, d + (c + b * t.y) * t.y),
                        dot(d + (c + b * t.z) * t.z, d + (c + b * t.z) * t.z))));
    }
}

void CartoonClover_float(float2 UV, float2 Center, float2 LeafSize, float4 LeafColor, float StemLength, float StemThickness, float StemCurvature, float4 StemColor, float OutlineThickness, float4 OutlineColor, out float4 outColor) {
    // PLAN:
    // 1) Center UVs. 
    // 2) Generate 4 heart leaves rotated 90 degrees apart. Use min() to keep them distinct (sharp creases).
    // 3) Generate stem using Bezier SDF. Combine with leaves using smin() for a slight organic join.
    // 4) Compute colors (fill and outline) using smoothstep for AA.
    
    // 1. Setup
    float2 p = UV - Center;
    float2 safeLeafSize = max(LeafSize, 0.001);
    
    // 2. Leaves (Radial Repetition)
    float dLeaves = 1e9;
    
    // Loop 4 times for 4 leaves
    // We use a slight offset outward so the tips don't overlap messily at the absolute center
    float centerOffset = 0.02 * min(safeLeafSize.x, safeLeafSize.y);
    
    for(int i = 0; i < 4; i++) {
        float angle = float(i) * (PI * 0.5);
        
        // Rotate p to local leaf space (leaf points UP in local space)
        float2 pLocal = rotate2D(p, -angle);
        
        // Shift leaf out slightly from center
        pLocal.y -= centerOffset;
        
        // Non-uniform scaling for Width/Height adjustment
        // We divide coordinate by size. Distance field must be corrected by scaling factor.
        // Approximation: multiply result by min scale.
        float d = sdHeart(pLocal / safeLeafSize) * min(safeLeafSize.x, safeLeafSize.y);
        
        // Use strict min() to keep leaves visually distinct at junctions
        dLeaves = min(dLeaves, d);
    }
    
    // 3. Stem SDF
    // Bezier from (0,0) down to (0, -Length). 
    // Control point offsets X by Curvature.
    // We shift the start slightly down so it connects behind the leaves properly.
    float2 stemStart = float2(0.0, 0.0);
    float2 stemEnd = float2(0.0, -max(StemLength, 0.0));
    float2 stemControl = float2(StemCurvature, -StemLength * 0.5);
    
    float dStemCurve = sdBezier(p, stemStart, stemControl, stemEnd);
    float dStem = dStemCurve - StemThickness;
    
    // 4. Combine Leaves and Stem
    // We use smin here to make the stem look attached organically, but fairly tight (k=0.03)
    float dUnion = smin(dLeaves, dStem, 0.03);
    
    // 5. Rendering
    float aa = fwidth(dUnion);
    
    // Color mixing: Stem is distinct from leaves usually, but we want a smooth transition if blended
    // We decide color based on which SDF is closer
    float mixFactor = smoothstep(-0.01, 0.01, dStem - dLeaves);
    float4 fillColor = lerp(StemColor, LeafColor, mixFactor);
    
    // Fill Alpha
    float fillMask = 1.0 - smoothstep(0.0, aa, dUnion);
    float4 fillLayer = float4(fillColor.rgb * fillMask, fillMask * fillColor.a);
    
    // Outline
    float halfOutline = OutlineThickness * 0.5;
    float outlineEdge = abs(dUnion) - halfOutline;
    float outlineMask = 1.0 - smoothstep(0.0, aa, outlineEdge);
    float4 outlineLayer = float4(OutlineColor.rgb * outlineMask, outlineMask * OutlineColor.a);
    
    // Composite: Outline OVER Fill
    // Standard Over: out = src + dst * (1 - src.a)
    float4 blended = outlineLayer + fillLayer * (1.0 - outlineLayer.a);
    
    outColor = blended;
}

// ------------------------------------------------------------------------
//  Visual Result (High-level, parameter-invariant description)
// ------------------------------------------------------------------------
//  This function generates a **stylized 2D four-leaf clover** using
//  Signed Distance Functions (SDFs).
//
//  The visual result is composed of:
//  - A radial cluster of four heart-shaped leaves arranged at 90-degree intervals.
//  - A curved stem extending downward from the central junction.
//
//  The leaves and stem are blended using a smooth union operation to create
//  an organic, connected silhouette. A consistent outline surrounds the entire
//  shape. The geometry (leaf size, stem curvature, length) and colors are
//  fully adjustable.
//
//  The output is an anti-aliased RGBA color suitable for nature icons,
//  Irish/St. Patrick's Day themes, and lucky charms.
// ------------------------------------------------------------------------