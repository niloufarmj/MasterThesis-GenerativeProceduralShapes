#ifndef PI
#define PI 3.14159265359
#endif

float sdUnevenCapsule_TD(float2 p, float r1, float r2, float h)
{
    p.x = abs(p.x);
    float b = (r1 - r2) / h;
    float a = sqrt(1.0 - b * b);
    float k = dot(p, float2(-b, a));
    if (k < 0.0) return length(p) - r1;
    if (k > a * h) return length(p - float2(0.0, h)) - r2;
    return dot(p, float2(a, b)) - r1;
}

void TearDropShape_float(
    float2 UV,
    float2 Center,
    float Radius,
    float Height,
    float Rotation,
    float4 FillColor,
    out float4 outColor
)
{
    float2 p = UV - Center;

    float cosR = cos(Rotation);
    float sinR = sin(Rotation);
    p = float2(cosR * p.x + sinR * p.y, -sinR * p.x + cosR * p.y);

    float r = max(Radius, 0.001);
    float h = max(Height, r * 1.01);

    // Center the shape vertically: shape spans from y = -r (bottom) to y = h (tip)
    // Midpoint = (h - r) * 0.5
    p.y += (h - r) * 0.5;

    float dist = sdUnevenCapsule_TD(p, r, 0.0, h);

    float aa = fwidth(dist);
    aa = max(aa, 0.0005);

    float alpha = smoothstep(aa, -aa, dist);

    outColor = float4(FillColor.rgb * alpha, FillColor.a * alpha);
}