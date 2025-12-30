#ifndef PI
#define PI 3.14159265359
#endif

// SDF Helper: Triangle (Inigo Quilez)
float sdTriangle(float2 p, float2 p0, float2 p1, float2 p2) {
    float2 e0 = p1 - p0;
    float2 e1 = p2 - p1;
    float2 e2 = p0 - p2;

    float2 v0 = p - p0;
    float2 v1 = p - p1;
    float2 v2 = p - p2;

    float2 pq0 = v0 - e0*clamp( dot(v0,e0)/dot(e0,e0), 0.0, 1.0 );
    float2 pq1 = v1 - e1*clamp( dot(v1,e1)/dot(e1,e1), 0.0, 1.0 );
    float2 pq2 = v2 - e2*clamp( dot(v2,e2)/dot(e2,e2), 0.0, 1.0 );

    float s = sign( e0.x*e2.y - e0.y*e2.x );
    float2 d = min( min( float2( dot( pq0, pq0 ), s*(v0.x*e0.y-v0.y*e0.x) ),
                         float2( dot( pq1, pq1 ), s*(v1.x*e1.y-v1.y*e1.x) )),
                         float2( dot( pq2, pq2 ), s*(v2.x*e2.y-v2.y*e2.x) ));

    return -sqrt(d.x)*sign(d.y);
}

// SDF Helper: Circle
float sdCircle(float2 p, float r) {
    return length(p) - r;
}

// Helper: Blend two layers (Straight Alpha)
float4 layerBlend(float4 top, float4 bottom) {
    float a = top.a + bottom.a * (1.0 - top.a);
    if (a < 1e-6) return float4(0,0,0,0);
    float3 c = (top.rgb * top.a + bottom.rgb * bottom.a * (1.0 - top.a)) / a;
    return float4(c, a);
}

void CartoonPartyHat_float(
    float2 UV,
    float2 Center,
    float Width,
    float Height,
    float4 HatColor,
    float StripeCount,
    float StripeThickness,
    float4 StripeColor,
    float PomSize,
    float4 PomColor,
    float Rotation,
    out float4 outColor
) {
    // PLAN:
    // 1. Center and rotate UV coordinates.
    // 2. Define geometry for hat body (triangle) and pom-pom (circle).
    // 3. Compute Hat SDF and apply horizontal stripe pattern masked by the hat.
    // 4. Compute Pom-Pom SDF.
    // 5. Composite Pom-Pom over Hat Body with anti-aliasing.

    // 1. Coordinate Transform
    float2 p = UV - Center;
    float c = cos(Rotation);
    float s = sin(Rotation);
    p = float2(p.x * c - p.y * s, p.x * s + p.y * c);

    // 2. Geometry Definitions
    // Triangle vertices relative to center
    float hHalf = Height * 0.5;
    float wHalf = Width * 0.5;
    float2 tip = float2(0.0, hHalf);
    float2 baseR = float2(wHalf, -hHalf);
    float2 baseL = float2(-wHalf, -hHalf);

    // 3. Hat Body (Conical Shape -> Triangle in 2D)
    float dHat = sdTriangle(p, tip, baseR, baseL);
    float aa = fwidth(dHat);
    float hatMask = 1.0 - smoothstep(0.0, aa, dHat);

    // Stripe Pattern
    // Normalized Y from 0 (bottom) to 1 (top)
    float yNorm = (p.y + hHalf) / max(Height, 0.0001);
    float stripePhase = yNorm * StripeCount;
    // Fraction creates the repeating band
    // abs(frac - 0.5) centers the stripe within the band
    float dStripe = abs(frac(stripePhase) - 0.5) - (StripeThickness * 0.5);
    float stripeAA = fwidth(stripePhase);
    // Stripe factor: 1.0 inside stripe, 0.0 outside
    float stripeFactor = 1.0 - smoothstep(0.0, stripeAA, dStripe);

    // Mix Hat Base and Stripe Color
    float4 bodyFill = lerp(HatColor, StripeColor, stripeFactor);
    float4 hatLayer = float4(bodyFill.rgb, clamp(bodyFill.a, 0.0, 1.0) * hatMask);

    // 4. Pom-Pom (Circle at tip)
    float dPom = sdCircle(p - tip, PomSize);
    float pomAA = fwidth(dPom);
    float pomMask = 1.0 - smoothstep(0.0, pomAA, dPom);
    float4 pomLayer = float4(PomColor.rgb, clamp(PomColor.a, 0.0, 1.0) * pomMask);

    // 5. Composite Layers
    // Pom-pom sits on top of the hat
    outColor = layerBlend(pomLayer, hatLayer);
}