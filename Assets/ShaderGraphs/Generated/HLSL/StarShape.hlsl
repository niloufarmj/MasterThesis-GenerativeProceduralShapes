#ifndef PI
#define PI 3.14159265359
#endif

// SDF for an N-pointed star
// p: Centered UV coordinates
// r: Outer radius (peak)
// n: Number of points
// rInner: Inner radius (valley)
float sdStar(float2 p, float r, float n, float rInner) {
    // Angle per sector (half wedge)
    float an = PI / n;
    float sector = 2.0 * an;
    
    // Convert to polar coordinates (angle 0 is +Y axis)
    float angle = atan2(p.x, p.y);
    
    // Fold angle to repeat sectors
    // Shift angle by half sector to align sector center to 0
    float id = floor((angle + an) / sector);
    float localAngle = angle - id * sector;
    
    // Map back to cartesian in the local rotated frame
    float len = length(p);
    p = float2(sin(localAngle), cos(localAngle)) * len;
    
    // Symmetry along the Y axis (local sector center)
    p.x = abs(p.x);
    
    // Define the edge segment from Peak (0, r) to Valley
    float2 p1 = float2(0.0, r);
    float2 p2 = float2(rInner * sin(an), rInner * cos(an));
    
    // Standard distance to segment
    float2 e = p2 - p1;
    float2 w = p - p1;
    float2 b = w - e * clamp(dot(w, e) / dot(e, e), 0.0, 1.0);
    float d = length(b);
    
    // Determine sign (negative inside, positive outside)
    // Use perpendicular vector to edge to determine side
    // Edge goes from Top to Right-Down. Normal points 'right/up' (outside)
    float2 perp = float2(e.y, -e.x);
    float s = dot(w, perp);
    
    return d * sign(s);
}

void StarShape_float(float2 UV, float Radius, float InnerRadius, float Points, float Rotation, float2 Center, float4 Color, out float4 outColor) {
    // PLAN:
    // 1) Center the UV coordinates based on Center input.
    // 2) Rotate the coordinates.
    // 3) Calculate SDF using the star formula.
    // 4) Apply smoothstep for anti-aliased edges.
    // 5) Output the final color.

    // 1) Center UVs
    float2 p = UV - Center;
    
    // 2) Apply Rotation
    float c = cos(Rotation);
    float s = sin(Rotation);
    p = float2(p.x * c - p.y * s, p.x * s + p.y * c);
    
    // 3) Calculate Signed Distance Field (SDF)
    // Ensure safe values for n and radii
    float n = max(3.0, round(Points));
    float r = max(0.0, Radius);
    float r2 = max(0.0, InnerRadius);
    
    float dist = sdStar(p, r, n, r2);
    
    // 4) Anti-aliasing
    // Use fwidth for resolution-independent smoothness, or fallback to fixed value
    float delta = fwidth(dist);
    float edge = smoothstep(delta, -delta, dist);
    
    // 5) Final Output
    outColor = float4(Color.rgb * edge, edge * Color.a);
}