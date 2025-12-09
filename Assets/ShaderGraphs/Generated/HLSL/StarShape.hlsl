#ifndef PI
#define PI 3.14159265359
#endif

// --- Helper Functions ---

// Blend function (Source Over Destination)
float4 Star_Over(float4 src, float4 dst) {
    float a = src.a + dst.a * (1.0 - src.a);
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-8);
    return float4(c, a);
}

// SDF for N-pointed Star
// p: Centered UV coordinates
// r: Outer radius (tip)
// rIn: Inner radius (valley)
// n: Number of points
float Star_SDF(float2 p, float r, float rIn, float n) {
    // Ensure valid inputs
    n = max(n, 2.0);
    
    // Sector angle parameters
    float an = PI / n;
    float2 acs = float2(cos(an), sin(an));

    // 1. Align space so 0 is +Y (up)
    float angle = atan2(p.x, p.y) + PI;
    float seg = 2.0 * an;
    
    // 2. Repeat space into n sectors
    float a = fmod(angle, seg);
    
    // 3. Fold symmetry within sector
    // Maps [0, 2*an] -> [0, an] so edge is always on right
    if (a > an) a = seg - a;
    
    // 4. Reconstruct point in folded sector
    float len = length(p);
    float2 pSec = float2(sin(a), cos(a)) * len;
    
    // 5. Define edge vertices for the star segment
    // v1: Tip at angle 0 (relative to local sector center line)
    // v2: Valley at angle 'an'
    float2 v1 = float2(0.0, r);
    float2 v2 = float2(sin(an), cos(an)) * rIn;
    
    // 6. Compute distance to segment v1-v2
    float2 e = v2 - v1;
    float2 w = pSec - v1;
    float2 b = w - e * clamp(dot(w, e) / dot(e, e), 0.0, 1.0);
    float d = length(b);
    
    // 7. Determine sign (Inside/Outside)
    // The right-hand normal of the edge vector e points INSIDE the star.
    // If dot(w, nRight) > 0, we are inside.
    // Since standard SDF is negative inside, we flip the sign.
    float2 nRight = float2(e.y, -e.x);
    return -d * sign(dot(w, nRight));
}

// --- Main Function ---
// PLAN:
// 1. Center and rotate the UV coordinates.
// 2. Calculate the Star SDF using the outer and inner radii.
// 3. Compute antialiasing factor using fwidth.
// 4. Generate Fill and Stroke masks using smoothstep.
// 5. Composite Stroke over Fill for final output.
void StarShape_float(float2 UV, float2 Center, float Rotation, float Radius, float InnerRadius, float Points, float4 FillColor, float4 StrokeColor, float StrokeWidth, out float4 outColor) {
    // 1. Center coordinates
    float2 p = UV - Center;
    
    // 2. Apply Rotation (Rotate p by -angle to rotate shape by +angle)
    float c = cos(Rotation);
    float s = sin(Rotation);
    p = float2(c * p.x + s * p.y, -s * p.x + c * p.y);
    
    // 3. Calculate Signed Distance Field
    float dist = Star_SDF(p, Radius, InnerRadius, Points);
    
    // 4. Calculate AA width (screen-space derivative)
    float aa = fwidth(dist);
    
    // 5. Compute Fill Layer
    // Smoothstep creates a smooth transition at dist=0 from 1 (inside) to 0 (outside)
    float fillAlpha = 1.0 - smoothstep(0.0, aa, dist);
    float4 fillLayer = float4(FillColor.rgb, FillColor.a * fillAlpha);
    
    // 6. Compute Stroke Layer
    // Stroke is centered on the edge. Width is total width.
    float halfStroke = StrokeWidth * 0.5;
    // abs(dist) creates a hollow shell, subtracting halfStroke defines the band thickness
    float strokeDist = abs(dist) - halfStroke;
    float strokeAlpha = 1.0 - smoothstep(0.0, aa, strokeDist);
    float4 strokeLayer = float4(StrokeColor.rgb, StrokeColor.a * strokeAlpha);
    
    // 7. Composite Stroke OVER Fill
    outColor = Star_Over(strokeLayer, fillLayer);
}