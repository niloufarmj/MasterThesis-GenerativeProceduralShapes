#ifndef PI
#define PI 3.14159265359
#endif

// User request: A mechanical gear shape with adjustable teeth count, tooth depth, size, and separate colors for gear body and inner hole.

// Basic 2D rotation helper
float2 rotate2D(float2 p, float angle)
{
    float c = cos(angle);
    float s = sin(angle);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

// SDF: circle centered at origin, radius r (negative inside)
float sdCircle(float2 p, float r)
{
    return length(p) - r;
}

// Repeat angle around circle into a single wedge of fullAngle
float angleRepeat(float angle, float fullAngle)
{
    // Map angle to [-PI, PI]
    float a = angle;
    // Wrap by subtracting multiples of fullAngle
    float k = round(a / fullAngle);
    a -= k * fullAngle;
    return a;
}

// PLAN:
// 1) Map UV to centered coordinates around (0.5, 0.5) and scale by GearSize.
// 2) Compute base outer circle SDF for the gear body.
// 3) Build tooth SDF by angular repetition of a small radial box-like wedge.
// 4) Combine base circle and tooth shape using union to form outer gear profile.
// 5) Subtract an inner circle SDF to create the gear's central hole.
// 6) Use SDF sign to choose GearColor outside the hole and HoleColor inside.
// 7) Use smoothstep for anti-aliasing and output color with alpha as coverage.

void GearShape_float(
    float2 UV,
    float GearSize,          // overall gear radius in UV units
    float TeethCount,        // number of teeth (treated as float, rounded in use)
    float ToothDepth,        // how far teeth extend radially beyond base radius
    float InnerHoleRadius,   // radius of inner hole (0..GearSize)
    float4 GearColor,        // color of gear body
    float4 HoleColor,        // color of inner hole
    out float4 outColor)
{
    // Safety clamps
    float teeth = max(1.0, TeethCount);
    float toothDepth = max(0.0, ToothDepth);
    float outerRadius = max(0.001, GearSize + toothDepth); // include teeth in max radius
    float baseRadius = max(0.0, GearSize);
    float holeRadius = clamp(InnerHoleRadius, 0.0, baseRadius * 0.9);

    // 1) Center and scale UV to local space (UV 0..1 -> centered -GearSize..GearSize roughly)
    float2 centered = UV - float2(0.5, 0.5);
    // To keep SDF uniform, normalize by GearSize scale; if GearSize is 0, use small fallback
    float scale = max(outerRadius, 0.001);
    float2 p = centered / scale; // p is approximately in units of outerRadius

    float r = length(p);
    float angle = atan2(p.y, p.x);

    // 2) Base gear circle (without teeth): radius = baseRadius / outerRadius in this space
    float baseR = baseRadius / scale;
    float dBase = r - baseR; // same as sdCircle(p, baseR)

    // 3) Tooth SDF using angular repetition
    // Each tooth covers 2*halfAngle in radians
    float n = teeth;
    float fullAngle = 2.0 * PI / n;
    float halfAngle = 0.5 * fullAngle;

    // Repeat angle into [-halfAngle, halfAngle]
    float localAngle = angleRepeat(angle, fullAngle);

    // Local coordinates in tooth wedge frame
    float2 pw = float2(r, localAngle);

    // Define tooth as a radial "box" in (radius, angle) space:
    // radial range: [baseR, baseR + toothDepth/scale]
    float toothOuterR = (baseRadius + toothDepth) / scale;
    float toothInnerR = baseR;
    float radialCenter = 0.5 * (toothOuterR + toothInnerR);
    float radialHalf = 0.5 * (toothOuterR - toothInnerR);

    // angular half-width: slightly narrower than halfAngle to leave gaps
    float angHalf = halfAngle * 0.6;

    // Convert to box distance in (r, angle) with extents (radialHalf, angHalf)
    float2 dBox = float2(abs(pw.x - radialCenter), abs(pw.y)) - float2(radialHalf, angHalf);
    float outside = length(max(dBox, 0.0));
    float inside = min(max(dBox.x, dBox.y), 0.0);
    float dToothBox = outside + inside; // negative inside, positive outside

    // Convert this box SDF back to radial SDF by approximating along radius
    // We want teeth to exist only outside base circle, so union with base by radial min
    // Combine tooth box SDF with circle SDF by taking min in actual distance sense.
    // Map dToothBox from (radius,angle) box to approximate radial offset:
    float dTooth = dToothBox; // already a distance field in our (r,angle) metric

    // Outer gear profile: union of base circle and tooth region
    float dOuter = min(dBase, dTooth);

    // 5) Inner hole SDF
    float holeR = holeRadius / scale;
    float dHole = r - holeR; // sdCircle(p, holeR)

    // Subtract hole from gear: gearSDF = max(dOuter, -dHole)
    float dGear = max(dOuter, -dHole);

    // 6) Choose color based on being inside gear or inside hole
    // For pixels inside gear (dGear < 0), check if also inside hole (dHole < 0)
    float inGear = saturate(1.0 - step(0.0, dGear)); // 1 if inside gear
    float inHole = saturate(1.0 - step(0.0, dHole)); // 1 if inside inner circle

    // Color mix: where inHole=1 and inGear=1 → HoleColor; where inGear=1 & inHole=0 → GearColor
    float useHole = inGear * inHole;
    float useGear = inGear * (1.0 - inHole);

    float3 finalColorRGB = GearColor.rgb * useGear + HoleColor.rgb * useHole;

    // 7) Anti-aliasing on outer silhouette using SDF of final gear body (dGear)
    float aa = fwidth(dGear);
    float mask = 1.0 - smoothstep(0.0, aa, dGear);

    // Multiply color by mask for smooth edges
    outColor = float4(finalColorRGB * mask, mask);
}
