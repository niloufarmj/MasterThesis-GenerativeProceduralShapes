#ifndef PI
#define PI 3.14159265359
#endif

void ChevronShape_float(
    float2 UV,
    float2 Size,
    float Thickness,
    float Rotation,
    float2 Center,
    float4 Color,
    out float4 outColor
) {
    // Center and rotate UVs
    float2 p = UV - Center;
    float c = cos(Rotation);
    float s = sin(Rotation);
    p = float2(c * p.x + s * p.y, -s * p.x + c * p.y);
    
    // Mirror Y axis to symmetrically draw top and bottom arms simultaneously
    p.y = abs(p.y);
    
    // Protect against degenerate zero sizes
    float2 size = max(Size, float2(0.001, 0.001));
    float halfW = size.x * 0.5;
    float halfH = size.y * 0.5;
    
    // The sharp tip of the chevron on the right
    float2 tip = float2(halfW, 0.0);
    
    // Vector representing the top arm (from tip to back left)
    float2 v = float2(-size.x, halfH);
    float len = length(v);
    float2 armDir = v / len;
    
    // Normal to the top arm, pointing outwards (up-right)
    float2 n = float2(armDir.y, -armDir.x);
    
    // Distance to the outer half-plane
    float d_outer = dot(p - tip, n);
    
    // Distance to the inner half-plane (shifted inwards by Thickness)
    float d_inner = - (d_outer + Thickness);
    
    // Distance to the back cut (perpendicular to the arm at its end)
    float2 end = tip + armDir * len; // exact end point of outer edge at (-halfW, halfH)
    float d_back = dot(p - end, armDir);
    
    // The solid arm is the geometric intersection of these three half-planes
    float d = max(d_outer, max(d_inner, d_back));
    
    // Anti-aliasing perfectly scaled to the distance field's gradient using fwidth
    float aa = max(fwidth(d), 0.001);
    float alpha = 1.0 - smoothstep(0.0, aa, d);
    
    outColor = float4(Color.rgb, Color.a * alpha);
}