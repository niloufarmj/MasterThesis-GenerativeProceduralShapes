#ifndef PI
#define PI 3.14159265359
#endif

// --- Helpers ---

// Straight-alpha "src over dst" composite
inline float4 nm_over(float4 src, float4 dst)
{
    float a = src.a + dst.a * (1.0 - src.a);
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-8);
    return float4(c, a);
}

// SDF for a Pie Slice (Wedge) symmetric about the Y-axis
// p: point in sector space
// c: aperture vector (sin(halfAngle), cos(halfAngle))
// r: radius of the sector
float nm_sdPie(float2 p, float2 c, float r)
{
    p.x = abs(p.x); // Symmetry across Y
    float l = length(p) - r;
    // c is the normal to the side edge (pointing outward from the wedge center)
    // We project p onto the edge line segment from (0,0) to c*r
    float m = length(p - c * clamp(dot(p, c), 0.0, r));
    return max(l, m * sign(c.y * p.x - c.x * p.y));
}

// --- Main Function ---
// Radiation Warning Symbol: Circular background + Trefoil (3 blades) + Central Dot
void RadiationSymbol_float(
    float2 UV,
    float2 Center,
    float Size,
    float Rotation,
    float CoreRadiusProp,      // Radius of the central dot (relative to Size)
    float BladeInnerProp,      // Start radius of blades (relative to Size)
    float BladeOuterProp,      // End radius of blades (relative to Size)
    float BladeAngleRad,       // Width of each blade in radians (e.g. PI/3 for 60 degrees)
    float BackgroundRadiusProp,// Radius of the yellow background (relative to Size)
    float4 SymbolColor,
    float4 BackgroundColor,
    out float4 outColor)
{
    // PLAN:
    // 1) Center UV coordinates.
    // 2) Compute Polar Coordinates (radius, angle).
    // 3) Apply 3-way domain folding (modulo arithmetic) to map all 3 sectors to a single canonical sector centered on +Y.
    // 4) Compute SDF for the blade in this canonical sector (Pie slice minus inner hole).
    // 5) Compute SDF for the central dot and background circle.
    // 6) Combine SDFs using min/max operations.
    // 7) Render with smoothstep AA and composite layers.

    // 1) Center Coordinates
    float2 p = UV - Center;
    
    // 2) Polar Coordinates
    float r = length(p);
    // atan2(x, y) gives angle from +Y axis (0 at North, PI/2 at East)
    // We subtract Rotation to spin the whole symbol
    float angle = atan2(p.x, p.y) - Rotation;

    // 3) Domain Repetition (3 Blades)
    // Map the angle to the domain [-PI/3, PI/3] centered around 0 (which corresponds to +Y in our local space)
    // This effectively folds the 3 sectors (0, 120, 240 deg) onto one.
    float sectorSize = 2.0 * PI / 3.0;
    
    // Normalize angle to [0, 1]
    // adding PI ensures we start from a positive range before modulo
    float normalizedAngle = (angle + PI) / (2.0 * PI);
    // Frac gives us 0..1 wrapping 3 times per circle
    float localSector01 = frac(normalizedAngle * 3.0);
    // Map back to radians [-PI/3, PI/3]
    float localAngle = (localSector01 - 0.5) * sectorSize;
    
    // Reconstruct the point in the canonical sector (aligned with +Y)
    // sin(a) is x, cos(a) is y because our angle is from Y-axis
    float2 pBlade = float2(sin(localAngle), cos(localAngle)) * r;

    // 4) Scale all radii by the global Size parameter
    float rCore = CoreRadiusProp * Size;
    float rIn = BladeInnerProp * Size;
    float rOut = BladeOuterProp * Size;
    float rBg = BackgroundRadiusProp * Size;

    // 5) Calculate SDFs
    
    // A. Background Circle
    float dBg = r - rBg;

    // B. Central Dot
    float dDot = r - rCore;

    // C. Blade (Pie Slice)
    float halfBladeAngle = max(BladeAngleRad, 0.0) * 0.5;
    float2 aperture = float2(sin(halfBladeAngle), cos(halfBladeAngle));
    
    // Wedge shape
    float dWedge = nm_sdPie(pBlade, aperture, rOut);
    
    // Subtract inner hole (Intersection with NOT hole => max(Wedge, -dHole))
    // Inner hole is a circle of radius rIn
    float dHole = r - rIn;
    float dBlade = max(dWedge, -dHole);

    // D. Combine Dot and Blades (Union)
    float dSymbol = min(dDot, dBlade);

    // 6) Anti-Aliasing
    // Use fwidth for screen-space consistent edge softness
    float aa = fwidth(dSymbol);
    aa = max(aa, 0.0001); // Prevent div-by-zero

    // 7) Rendering
    // Background alpha mask (inverted SDF: inside is 1)
    float bgMask = 1.0 - smoothstep(-aa, aa, dBg);
    float4 bgLayer = float4(BackgroundColor.rgb, saturate(BackgroundColor.a) * bgMask);

    // Symbol alpha mask
    float symMask = 1.0 - smoothstep(-aa, aa, dSymbol);
    float4 symLayer = float4(SymbolColor.rgb, saturate(SymbolColor.a) * symMask);

    // Composite Symbol OVER Background
    outColor = nm_over(symLayer, bgLayer);
}

// ------------------------------------------------------------------------
//  Visual Result (High-level, parameter-invariant description)
// ------------------------------------------------------------------------
//  This function generates a **standard radiation warning symbol (trefoil)**
//  using Signed Distance Functions (SDFs).
//
//  The visual result is composed of:
//  - A large circular **background field** (typically yellow).
//  - A central **circular core** (dot).
//  - Three equally spaced **wedge-shaped blades** radiating from the center,
//    separated by 120 degrees.
//
//  The geometry features adjustable blade width (angle), inner/outer radii,
//  and core size, allowing the symbol to be tuned to specific safety standards
//  or stylized variations.
//
//  The output is an anti-aliased RGBA color suitable for hazard signage,
//  sci-fi environment decals, and UI indicators for toxicity or danger.
// ------------------------------------------------------------------------