#ifndef PI
#define PI 3.14159265359
#endif

// Helper: Squared length for Bezier math
float dot2(float2 v) { return dot(v, v); }

// Helper: Signed Distance to a Box
// p: position relative to box center
// b: half-extents (width/2, height/2)
float sdBox(float2 p, float2 b) {
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// Helper: Signed Distance to a Quadratic Bezier Curve
// pos: sample position
// A: start point, B: control point, C: end point
// Source: Inigo Quilez
float sdBezier(float2 pos, float2 A, float2 B, float2 C) {
    float2 a = B - A;
    float2 b = A - 2.0*B + C;
    float2 c = a * 2.0;
    float2 d = A - pos;
    float kk = 1.0 / dot(b,b);
    float kx = kk * dot(a,b);
    float ky = kk * (2.0*dot(a,a)+dot(d,b)) / 3.0;
    float kz = kk * dot(d,a);
    float res = 0.0;
    float p = ky - kx*kx;
    float p3 = p*p*p;
    float q = kx*(2.0*kx*kx - 3.0*ky) + kz;
    float h = q*q + 4.0*p3;
    if(h >= 0.0) {
        h = sqrt(h);
        float2 x = (float2(h, -h) - q) / 2.0;
        float2 uv = sign(x)*pow(abs(x), float2(1.0/3.0, 1.0/3.0));
        float t = clamp(uv.x+uv.y-kx, 0.0, 1.0);
        res = dot2(d + (c + b*t)*t);
    } else {
        float z = sqrt(-p);
        float v = acos( q/(p*z*2.0) ) / 3.0;
        float m = cos(v);
        float n = sin(v)*1.732050808;
        float3 t = clamp(float3(m+m, -n-m, n-m)*z-kx, 0.0, 1.0);
        res = min(dot2(d+(c+b*t.x)*t.x), dot2(d+(c+b*t.y)*t.y));
        res = min(res, dot2(d+(c+b*t.z)*t.z));
    }
    return sqrt(res);
}

// Main Function: Cartoon Musical Note
// Renders a flat style musical note with head, stem, and optional flag
void MusicalNote_float(float2 UV, float2 Center, float Size, float HeadRadius, float StemHeight, float StemThickness, float FlagLength, float FlagCurvature, float4 Color, out float4 outColor) {
    // PLAN:
    // 1) Center and Scale UV coordinates.
    // 2) Create Note Head SDF (Circle).
    // 3) Create Stem SDF (Box), positioned tangentially to the head.
    // 4) Create Flag SDF (Bezier), attached to stem top.
    // 5) Union all shapes and apply anti-aliasing.

    // 1. Coordinate Setup
    float2 p = UV - Center;
    float s = max(Size, 0.001); // Avoid division by zero
    p /= s;

    // 2. Note Head (Circle centered at local origin)
    float dHead = length(p) - HeadRadius;

    // 3. Stem (Vertical Box)
    // Align stem to the right side of the head circle
    float stemX = HeadRadius - StemThickness * 0.5;
    // Box spans from y=0 to y=StemHeight
    float2 stemCenter = float2(stemX, StemHeight * 0.5);
    float2 stemHalfSize = float2(StemThickness * 0.5, StemHeight * 0.5);
    float dStem = sdBox(p - stemCenter, stemHalfSize);

    // 4. Flag (Curved Bezier Tail)
    float dFlag = 1000.0;
    if (FlagLength > 0.001) {
        // Start at top of stem
        float2 A = float2(stemX, StemHeight);
        // End point: extends right and drops down
        float2 C = float2(stemX + FlagLength, StemHeight - FlagLength * 0.6);
        // Control point: creates the arch/curvature
        float2 B = float2(stemX + FlagLength * 0.3, StemHeight + FlagCurvature);
        
        // Thickness relative to stem (slightly tapering feel by being thinner)
        float flagThick = StemThickness * 0.9;
        dFlag = sdBezier(p, A, B, C) - flagThick * 0.5;
    }

    // 5. Combine Shapes (Union)
    float d = min(dHead, dStem);
    d = min(d, dFlag);

    // 6. Anti-Aliasing
    // Use fwidth to keep edges sharp regardless of Size parameter
    float aa = fwidth(d);
    aa = max(aa, 0.001);
    
    // SDF is negative inside the shape
    float mask = 1.0 - smoothstep(-aa, aa, d);

    // Output
    outColor = float4(Color.rgb * mask, Color.a * mask);
}

// ------------------------------------------------------------------------
//  Visual Result
// ------------------------------------------------------------------------
//  This function generates a **stylized musical note** (resembling an 
//  eighth note or quaver) using Signed Distance Functions (SDFs).
//
//  The visual result is composed of:
//  - A circular **note head** at the bottom.
//  - A vertical rectangular **stem** attached tangentially to the right 
//    side of the head.
//  - A curved **flag** (tail) extending from the top of the stem, created 
//    using a quadratic Bezier curve for smooth, organic flow.
//
//  The shape features granular control over the geometry, allowing adjustment
//  of the head radius, stem height and thickness, and the length and 
//  curvature of the flag. Setting the flag length to zero produces a 
//  quarter note (crotchet).
//
//  The output is a solid, flat-colored silhouette with anti-aliased edges,
//  perfect for rhythm games, audio players, or music notation interfaces.
// ------------------------------------------------------------------------