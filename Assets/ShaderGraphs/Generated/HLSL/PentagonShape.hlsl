void PentagonShape_float(float2 UV, float Size, float4 Color, out float4 outColor) {
    // PLAN:
    // 1) Center UV and scale by Size
    // 2) Convert to polar coordinates
    // 3) Calculate signed distance field for a pentagon
    // 4) Apply smoothstep for anti-aliasing and set output color

    // Center and scale UV coordinates
    float2 centered = (UV - float2(0.5, 0.5)) / Size;

    // Convert to polar coordinates
    float angle = atan2(centered.y, centered.x);
    float radius = length(centered);

    // Number of sides (pentagon)
    const int N = 5;

    // Calculate the angle and distance for the pentagon sides
    float angleRepeat = 2.0 * PI / float(N);
    float a = cos(PI / float(N));
    float d = abs((radius - a) / cos(fmod(angle, angleRepeat) - PI / float(N)));

    // SDF (negative inside, positive outside)
    float dist = radius * cos(angle - round(angle / angleRepeat) * angleRepeat) - a;

    // Anti-aliasing with smoothstep
    float aa = fwidth(dist);
    float edge = smoothstep(0.01, -0.01, dist);

    // Color output with alpha blending based on edge
    outColor = float4(Color.rgb * edge, edge);
}