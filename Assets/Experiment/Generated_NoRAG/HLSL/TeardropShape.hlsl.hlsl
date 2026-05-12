#ifndef PI
#define PI 3.14159265359
#endif

void TeardropShape_float(float2 UV, float Size, float4 Color, out float4 outColor)
{
    // Center UV
    float2 p = (UV - float2(0.5, 0.5)) / max(Size, 0.001);

    // Teardrop SDF:
    // The teardrop has a round bottom and a pointed top.
    // We use a polar-coordinate based approach for a clean teardrop shape.
    // In our coordinate system: y increases downward in UV space,
    // so we flip y so that the point is at the top (negative y = up).
    // Flip y so point is at top
    float2 q = float2(p.x, -p.y);

    // Shift so the shape is centered vertically
    // Teardrop: bottom (round) at positive y, top (point) at negative y
    // We shift down a bit so it's visually centered
    q.y -= 0.1;

    // Teardrop SDF using the standard formulation:
    // A teardrop can be defined as:
    // For a point (x, y), map to polar: r, theta
    // Shape: r = cos(theta/2)^2  (cardioid-like)
    // We use a robust SDF approach:
    // Combine a circle (round part) with a cone (pointed top) smoothly.

    float ax = abs(q.x);

    // Circle for the round bottom
    float circleR = 0.38;
    float2 circleC = float2(0.0, 0.18);
    float dCircle = length(q - circleC) - circleR;

    // For the upper pointed part, use a parabola/cone blended region
    // We define the teardrop contour parametrically and use a distance field
    // Teardrop outline: x^2 = (1-y) * y^2  (scaled)
    // Rearranged: the shape is inside when x^2 <= (1-y)*y^2 for y in [0,1]
    // Scale to our coordinate system
    // Map q so bottom is at y=0, top tip is at y=1
    float scale = 0.7;
    float2 tq = float2(q.x, q.y + 0.2) / scale; // shift and scale
    // Flip: bottom round part near tq.y=0, tip near tq.y=1 (but our y increases down)
    // Use tq.y going from -0.5 (tip) to 0.6 (bottom)
    // Remap to [0,1]: t = (tq.y + 0.5) / 1.1
    float t = saturate((tq.y + 0.55) / 1.1);
    // At t=1 (bottom): half-width = sqrt(something round)
    // At t=0 (tip): half-width = 0
    // Teardrop half-width: w(t) = t * sqrt(1 - t) * k
    float k = 1.35;
    float halfW = k * t * sqrt(max(1.0 - t * 0.85, 0.0));
    // SDF to the teardrop outline (approximate)
    float insideX = ax - halfW * scale;
    // Combine: inside the teardrop when insideX < 0 and t in [0,1]
    float dTeardrop;
    if (t <= 0.0) {
        // Above the tip
        dTeardrop = length(tq - float2(0.0, -0.55)) * scale;
    } else if (t >= 1.0) {
        // Below the bottom
        dTeardrop = dCircle;
    } else {
        // Use smooth combination
        float dLateral = (ax - halfW * scale);
        float dBottom = length(q - circleC) - circleR;
        // Smooth min between lateral wall and circle bottom
        float h = saturate(0.5 + 0.5 * (dBottom - dLateral) / 0.15);
        dTeardrop = lerp(dBottom, dLateral, h) - 0.15 * h * (1.0 - h);
    }

    // Final smooth combination of circle bottom and teardrop body
    float blendK = 0.12;
    float h2 = saturate(0.5 + 0.5 * (dCircle - dTeardrop) / blendK);
    float dist = lerp(dCircle, dTeardrop, h2) - blendK * h2 * (1.0 - h2);

    // Anti-aliased fill
    float aa = fwidth(dist) * 1.2;
    float edge = smoothstep(aa, -aa, dist);

    outColor = float4(Color.rgb, Color.a * edge);
}