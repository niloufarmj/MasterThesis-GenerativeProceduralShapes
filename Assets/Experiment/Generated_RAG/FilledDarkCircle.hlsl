#ifndef PI
#define PI 3.14159265359
#endif

void FilledCircle_float(
    float2 UV,
    float2 Center,
    float Radius,
    float4 FillColor,
    out float4 outColor
)
{
    float2 p = UV - Center;
    float d = length(p) - Radius;
    
    float aa = fwidth(d);
    aa = max(aa, 0.001);
    
    float mask = smoothstep(aa, -aa, d);
    
    outColor = FillColor * mask;
}