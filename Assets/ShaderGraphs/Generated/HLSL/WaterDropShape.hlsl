#ifndef PI
#define PI 3.14159265359
#endif

// SDF for an isosceles triangle with base at y=0, tip at y=q.y, half-width q.x
// Returns negative inside, positive outside
float wd_sdIsosceles(float2 p, float2 q) {
    p.x = abs(p.x);
    float2 a = p - q * clamp(dot(p, q) / dot(q, q), 0.0, 1.0);
    float2 b = p - q * float2(clamp(p.x / q.x, 0.0, 1.0), 1.0);
    float k = sign(q.y);
    float d = min(dot(a, a), dot(b, b));
    float s = max(k * (p.x * q.y - p.y * q.x), k * (p.y - q.y));
    return sqrt(d) * sign(s);
}

// Smooth union of two SDFs (k = blend amount)
float wd_opSmoothUnion(float d1, float d2, float k) {
    float h = clamp(0.5 + 0.5 * (d2 - d1) / k, 0.0, 1.0);
    return lerp(d2, d1, h) - k * h * (1.0 - h);
}

void WaterDropShape_float(float2 UV, float Size, float Rotation, float4 Color, out float4 outColor) {
    // 1) Center and Scale UV
    float2 p = UV - 0.5;
    
    // 2) Apply Rotation
    float s = sin(Rotation);
    float c = cos(Rotation);
    p = float2(p.x * c - p.y * s, p.x * s + p.y * c);
    
    // 3) Define Water Drop Geometry
    // A drop is formed by a circle at the bottom and a triangle on top
    float r = Size * 0.3;          // Radius of the bottom circle
    float triH = Size * 0.8;       // Height of the triangle part
    float w = r;                   // Triangle half-width matches circle radius
    
    // Center the shape vertically
    // Shape spans from -r (circle bottom) to +triH (triangle tip)
    float centerY = (triH - r) * 0.5;
    p.y -= centerY;
    
    // 4) Calculate SDFs
    // Circle centered at origin (relative to shifted p)
    float dCircle = length(p) - r;
    
    // Isosceles Triangle with base at origin, pointing up
    float dTri = wd_sdIsosceles(p, float2(w, triH));
    
    // 5) Smooth Union to blend circle and triangle into a drop
    // The blend factor k controls how "fleshy" or "blobby" the drop is
    float k = Size * 0.1;
    float dist = wd_opSmoothUnion(dCircle, dTri, k);
    
    // 6) Anti-aliasing
    float edge = smoothstep(0.01, -0.01, dist);
    
    // 7) Output
    outColor = float4(Color.rgb * edge, edge);
}