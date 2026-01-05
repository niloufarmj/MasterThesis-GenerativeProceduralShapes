#ifndef PI
#define PI 3.14159265359
#endif

// SDF for an Ellipse
float sdEllipse(float2 p, float2 r) {
    float k0 = length(p/r);
    float k1 = length(p/(r*r));
    return k0*(k0-1.0)/k1;
}

// SDF for an Equilateral Triangle
float sdEquilateralTriangle(float2 p, float r) {
    const float k = 1.7320508;
    p.x = abs(p.x) - r;
    p.y = p.y + r/k;
    if(p.x+k*p.y > 0.0) p = float2(p.x-k*p.y, -k*p.x-p.y)/2.0;
    p.x -= clamp( p.x, -2.0*r, 0.0 );
    return -length(p)*sign(p.y);
}

// Smooth Minimum for organic blending
float smin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5*(b-a)/k, 0.0, 1.0);
    return lerp(b, a, h) - k*h*(1.0-h);
}

// Main Function: Bat Silhouette
// Request: Central body, small ears, adjustable symmetric scalloped wings, pointed tips, stroke.
void BatSilhouette_float(
    float2 UV,
    float Width,            // Body width
    float Height,           // Body height
    float EarSize,          // Size of ears
    float EarSpacing,       // Distance between ears
    float WingSpan,         // Length of wings
    float WingCurvature,    // Top curvature of wings
    float ScallopCount,     // Number of scallops on bottom
    float ScallopDepth,     // Depth of scallop cuts
    float2 Center,          // Position
    float Rotation,         // Rotation in radians
    float Size,             // Global scale
    float4 FillColor,       // Fill color
    float4 StrokeColor,     // Outline color
    float StrokeWidth,      // Outline thickness
    out float4 outColor
)
{
    // PLAN:
    // 1. Center and Rotate UVs, apply global Scale.
    // 2. Apply symmetry (abs(x)) since the bat is symmetric.
    // 3. Calculate Body SDF using Ellipse.
    // 4. Calculate Ears SDF using Triangles.
    // 5. Calculate Wing SDF using implicit curves (Top Parabola, Bottom Scalloped Wave).
    // 6. Combine all shapes using Smooth Union.
    // 7. Correct distance field for uniform stroke.
    // 8. Render Fill and Stroke with Anti-Aliasing.

    // 1. Transform Coordinates
    float2 p = UV - Center;
    
    // Rotation
    float s = sin(Rotation);
    float c = cos(Rotation);
    p = float2(p.x*c - p.y*s, p.x*s + p.y*c);
    
    // Global Scale (protect against div by zero)
    p /= max(Size, 0.0001);

    // Symmetry: Work in positive X half-space
    float2 q = p;
    q.x = abs(q.x);

    // 2. Body SDF
    float2 bodyRadii = float2(Width, Height) * 0.5;
    float dBody = sdEllipse(q, bodyRadii);

    // 3. Ears SDF
    // Position ears on top of the body
    float2 earPos = float2(EarSpacing, bodyRadii.y * 0.85);
    // Rotate ears slightly outwards could be cool, but keeping upright for simplicity
    // Invert Y for triangle to point up
    float dEars = sdEquilateralTriangle(float2(q.x - earPos.x, -(q.y - earPos.y)), EarSize);

    // 4. Wing SDF
    // Define wing coordinate space starting from shoulder
    float shoulderX = bodyRadii.x * 0.6;
    float wingLen = max(WingSpan, 0.001);
    
    // Normalized wing progress t (0 at shoulder, 1 at tip)
    float t = (q.x - shoulderX) / wingLen;
    
    // Clamp t for curve calculations to avoid wild values outside wing range
    float t_clamped = clamp(t, 0.0, 1.0);
    
    // Top Edge: Parabolic arch scaling with Curvature
    // Formula: y = Curvature * t * (1.0 - t) * 4.0 creates an arch
    // Modified: Rise then fall slightly to tip
    float yTop = WingCurvature * sin(t_clamped * PI * 0.8);
    
    // Bottom Edge: Tapering thickness + Scallops
    // Taper: Thickness goes from 0.25 to 0.0
    float taper = 1.0 - t_clamped;
    float baseThickness = 0.25 * taper;
    
    // Scallops: Sine wave on bottom edge
    // We use abs(sin) to create the "bites"
    float scallopWave = abs(sin(t_clamped * PI * max(ScallopCount, 1.0)));
    // Fade scallops at the very tip to keep it sharp
    scallopWave *= taper;
    
    float yBot = yTop - baseThickness + scallopWave * ScallopDepth;
    
    // Implicit 2D Distance: Max(y - Top, Bot - y)
    // This defines the region BETWEEN the top and bottom curves
    float dWingV = max(q.y - yTop, yBot - q.y);
    
    // Horizontal bounds: Cut off before shoulder and after tip
    // (Soft blend at shoulder is handled by smin later, hard cut at tip)
    float dWingH = max(shoulderX - q.x, q.x - (shoulderX + wingLen));
    
    // Combine vertical and horizontal constraints
    // Note: This is an approximate distance, not Euclidean
    float dWings = max(dWingV, dWingH);
    
    // 5. Combine Shapes
    // Smooth union body and ears
    float dShape = smin(dBody, dEars, 0.02);
    // Smooth union result with wings
    dShape = smin(dShape, dWings, 0.04);

    // 6. Stroke Correction
    // Normalize the SDF gradient to screen space for consistent stroke width
    // (Standard trick for implicit/distorted SDFs)
    float2 grad = float2(ddx(dShape), ddy(dShape));
    float distCorrected = dShape / (length(grad) + 0.0001);

    // 7. Rendering
    // Anti-aliasing width
    float aa = fwidth(distCorrected);
    
    // Fill Mask (Inner shape)
    float fillMask = 1.0 - smoothstep(-aa, aa, distCorrected);
    
    // Stroke Mask (Border)
    float strokeMask = smoothstep(StrokeWidth + aa, StrokeWidth, abs(distCorrected));
    
    // Composite
    // Draw Stroke on top of Fill
    float4 finalColor = lerp(float4(0,0,0,0), FillColor, fillMask);
    finalColor = lerp(finalColor, StrokeColor, strokeMask);
    
    // Alpha for output
    float finalAlpha = max(fillMask, strokeMask);
    
    outColor = float4(finalColor.rgb * finalAlpha, finalAlpha);
}

// ------------------------------------------------------------------------
//  Visual Result (High-level, parameter-invariant description)
// ------------------------------------------------------------------------
//  This function produces a **2D bat silhouette** constructed from
//  analytic Signed Distance Functions (SDFs).
//
//  The resulting shape is composed of:
//  - A central elliptical segment (body)
//  - Two triangular segments (ears) positioned on top
//  - Two symmetric wing segments defined by arched upper curves and scalloped (wavy) bottom edges
//
//  These parts are combined using smooth unions to create a single continuous,
//  organic silhouette that visually represents a flying bat. The final appearance 
//  (wing span, scallop density, ear size, and styling) is fully controlled by 
//  input parameters and is not fixed by the function itself.
//
//  The output is an anti-aliased RGBA color suitable for procedural UI,
//  icons, and symbolic 2D graphics.
// ------------------------------------------------------------------------