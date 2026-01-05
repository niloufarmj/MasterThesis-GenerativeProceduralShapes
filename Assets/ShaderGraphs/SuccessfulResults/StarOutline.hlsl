#ifndef PI
#define PI 3.14159265359
#endif

// Signed distance function for a 5-pointed star
// p: centered coordinate
// r: outer radius
// rf: inner radius
float sdStar5(in float2 p, in float r, in float rf)
{
    const float2 k1 = float2(0.809016994375, -0.587785252292);
    const float2 k2 = float2(-k1.x, k1.y);
    
    p.x = abs(p.x);
    p -= 2.0 * max(dot(k1, p), 0.0) * k1;
    p -= 2.0 * max(dot(k2, p), 0.0) * k2;
    
    p.x = abs(p.x);
    p.y -= r;
    
    float2 ba = rf * float2(-k1.y, k1.x) - float2(0.0, 1.0);
    float h = clamp(dot(p, ba) / dot(ba, ba), 0.0, r);
    
    return length(p - ba * h) * sign(p.y * ba.x - p.x * ba.y);
}

void StarOutline_float(float2 UV, float Radius, float InnerRatio, float Rotation, float2 Center, float StrokeWidth, float4 StrokeColor, out float4 outColor)
{
    // PLAN:
    // 1) Center UVs: p = UV - Center.
    // 2) Rotate p by Rotation angle.
    // 3) Calculate star SDF using outer radius and inner radius (Radius * InnerRatio).
    // 4) Compute stroke distance field: abs(d) - StrokeWidth/2.
    // 5) Apply anti-aliasing using smoothstep and fwidth.
    // 6) Output final color.

    // 1) Center and aspect correction not needed if UVs are square, 
    // but we assume standard UV space. Center default is (0.5, 0.5).
    float2 p = UV - Center;
    
    // 2) Rotation
    float c = cos(Rotation);
    float s = sin(Rotation);
    p = float2(p.x * c - p.y * s, p.x * s + p.y * c);
    
    // 3) Star SDF
    // Inner radius is derived from ratio. 0.382 gives straight lines (pentagram).
    float rInner = Radius * InnerRatio;
    float d = sdStar5(p, Radius, rInner);
    
    // 4) Stroke SDF
    // abs(d) gives distance from the shape boundary.
    // Subtracting half width centers the stroke on the boundary.
    float halfStroke = StrokeWidth * 0.5;
    float strokeDist = abs(d) - halfStroke;
    
    // 5) Anti-aliasing
    // Use fwidth for screen-space consistent AA size
    float aa = fwidth(d);
    // If fwidth is zero (e.g. constant UVs), fallback to small value
    aa = max(aa, 0.001);
    
    // Alpha is 1.0 inside stroke (strokeDist < 0), 0.0 outside
    // smoothstep(low, high, x) -> 0 if x < low, 1 if x > high
    // We want 1 when x < 0. So we invert logic or swap edges.
    float alpha = 1.0 - smoothstep(-aa, aa, strokeDist);
    
    // 6) Output
    // Pre-multiplied alpha or standard blending pattern
    outColor = float4(StrokeColor.rgb * alpha, alpha * StrokeColor.a);
}

// ------------------------------------------------------------------------
//  Visual Result (High-level, parameter-invariant description)
// ------------------------------------------------------------------------
//  This function generates a **hollow 5-pointed star outline** using
//  Signed Distance Functions (SDFs).
//
//  The visual result is composed of:
//  - A **continuous star-shaped stroke** with 5 vertices.
//  - A **transparent interior**, creating a wireframe or sticker-like appearance.
//  - Rounded outer corners resulting from the uniform stroke expansion.
//
//  The geometry features an adjustable **InnerRatio** (controlling the sharpness
//  or "fatness" of the star points) and **StrokeWidth**, allowing for variations
//  from thin wireframes to thick, bold symbols.
//
//  The output is an anti-aliased RGBA color suitable for rating systems,
//  favorite icons, and decorative celestial patterns.
// ------------------------------------------------------------------------