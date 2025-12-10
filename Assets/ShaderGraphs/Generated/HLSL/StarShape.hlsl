#ifndef PI
#define PI 3.14159265359
#endif

// --- Helper: Signed Distance to an N-pointed Star ---
// p: sampling point (centered)
// r: outer radius
// rInner: inner radius (valley)
// n: number of points
inline float sdStar_Function(float2 p, float r, float rInner, float n)
{
    // Clamp N to reasonable value
    n = max(2.0, n);
    
    // Angle per sector (half-wedge for one point)
    float an = PI / n;
    float sector = 2.0 * an;
    
    // Rotate p to align 0 angle with Y axis (standard for this math)
    float angle = atan2(p.x, p.y);
    
    // Sector repetition: map full circle to [-an, an]
    float id = floor(angle / sector + 0.5);
    float a = angle - id * sector;
    
    // Fold symmetry: map [-an, an] to [0, an]
    // This reduces the problem to a single edge in the first half-sector
    a = abs(a);
    
    // Reconstruct point in the folded wedge
    float len = length(p);
    float2 p_wedge = float2(sin(a), cos(a)) * len;
    
    // Define the star edge segment in this wedge
    // Vertex 1: Outer tip (at angle 0 in wedge, radius r) -> (0, r)
    float2 v1 = float2(0.0, r);
    // Vertex 2: Inner valley (at angle 'an' in wedge, radius rInner)
    float2 v2 = float2(sin(an), cos(an)) * rInner;
    
    // Calculate distance to segment v1-v2
    float2 pa = p_wedge - v1;
    float2 ba = v2 - v1;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    float2 dVec = pa - ba * h;
    
    // Determine sign (negative inside)
    // We use the normal (-ba.y, ba.x) which points outward from the origin side
    float2 normal = float2(-ba.y, ba.x);
    float s = dot(pa, normal);
    
    return length(dVec) * sign(s);
}

// --- Helper: Alpha Blending (Src Over Dst) ---
inline float4 star_blend_over(float4 src, float4 dst)
{
    float a = src.a + dst.a * (1.0 - src.a);
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-8);
    return float4(c, a);
}

void StarShape_float(float2 UV, float Size, float Points, float InnerRatio, float Rotation, float4 FillColor, float4 StrokeColor, float StrokeWidth, out float4 outColor)
{
    // PLAN:
    // 1) Center UV coordinates at (0.5, 0.5).
    // 2) Rotate the coordinate system by the Rotation parameter.
    // 3) Compute SDF for the star using helper function.
    // 4) Compute Fill and Stroke masks using smoothstep AA.
    // 5) Composite Stroke over Fill for final output.

    // 1) Center UV
    float2 center = float2(0.5, 0.5);
    float2 p = UV - center;
    
    // 2) Apply Rotation (rotate point by -angle -> shape rotates by +angle)
    float c = cos(Rotation);
    float s = sin(Rotation);
    p = float2(c * p.x + s * p.y, -s * p.x + c * p.y);
    
    // 3) Calculate Radii
    float rOuter = max(Size, 0.0);
    float rInner = rOuter * clamp(InnerRatio, 0.01, 1.0);
    
    // Calculate SDF
    float dist = sdStar_Function(p, rOuter, rInner, Points);
    
    // 4) Antialiasing
    // fwidth gives a good estimate for pixel-perfect AA
    float aa = fwidth(dist);
    aa = max(aa, 0.0001); // Safety clamp
    
    // Fill Mask (dist < 0 is inside)
    // smoothstep(0, aa, dist) goes 0->1 at edge. We want 1 inside.
    float fillAlpha = 1.0 - smoothstep(-0.5 * aa, 0.5 * aa, dist);
    float4 fillLayer = float4(FillColor.rgb, FillColor.a * fillAlpha);
    
    // Stroke Mask (band around dist == 0)
    // We subtract stroke width from abs(dist)
    float halfStroke = max(StrokeWidth, 0.0) * 0.5;
    float strokeDist = abs(dist) - halfStroke;
    float strokeAlpha = 1.0 - smoothstep(-0.5 * aa, 0.5 * aa, strokeDist);
    float4 strokeLayer = float4(StrokeColor.rgb, StrokeColor.a * strokeAlpha);
    
    // 5) Composite
    outColor = star_blend_over(strokeLayer, fillLayer);
}