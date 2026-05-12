#ifndef PI
#define PI 3.14159265359
#endif

float sminScallop(float a, float b, float k) {
    float h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * 0.25;
}

void ScallopedDisc_float(
    float2 UV,
    float2 Center,
    float Radius,
    float BumpCount,
    float BumpSize,
    float BumpSmoothness,
    float4 Color,
    out float4 outColor
) {
    float2 p = UV - Center;

    // Polar coordinates
    float angle = atan2(p.y, p.x);
    float r = length(p);

    // Number of bumps around the perimeter
    float count = max(BumpCount, 3.0);

    // Quantize angle to nearest bump
    float sector = (2.0 * PI) / count;
    float nearestAngle = round(angle / sector) * sector;

    // Direction of nearest bump center
    float2 bumpDir = float2(cos(nearestAngle), sin(nearestAngle));
    // Position of nearest bump center (on the base circle perimeter)
    float2 bumpCenter = bumpDir * Radius;

    // SDF of base disc
    float dDisc = r - Radius;

    // SDF of the nearest bump (small circle placed at the perimeter)
    float dBump = length(p - bumpCenter) - BumpSize;

    // Smooth union of disc and bump
    float k = max(BumpSmoothness, 0.001);
    float h = max(k - abs(dDisc - dBump), 0.0) / k;
    float d = min(dDisc, dBump) - h * h * k * 0.25;

    // Anti-aliasing
    float aa = fwidth(d);
    aa = max(aa, 0.0005);
    float alpha = smoothstep(aa, -aa, d);

    outColor = float4(Color.rgb * alpha, alpha);
}