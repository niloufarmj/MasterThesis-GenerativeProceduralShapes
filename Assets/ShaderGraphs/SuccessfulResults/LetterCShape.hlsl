#ifndef PI
#define PI 3.14159265359
#endif

// Guarded straight-alpha composite helper (Source Over Destination)
#ifndef NM_OVER_HELPER
#define NM_OVER_HELPER
inline float4 nm_over(float4 src, float4 dst) {
    float a = src.a + dst.a * (1.0 - src.a);
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-8);
    return float4(c, a);
}
#endif

void LetterCShape_float(float2 UV, float Width, float Height, float Thickness, float ApertureDeg, float CapStyle, float4 FillColor, float4 OutlineColor, float OutlineWidth, out float4 outColor) {
    // PLAN:
    // 1) Center UV at (0.5, 0.5) and normalize domain by Width/Height to support resizing.
    // 2) Define the C-shape in this normalized space (approx. unit circle).
    // 3) Compute SDF for both Round and Flat cap styles using a radial gap logic.
    // 4) Combine SDFs and scale distance back to world units to preserve correct AA and stroke size.
    // 5) Generate Fill and Outline layers and composite them (Fill over Outline).

    // 1. Setup Coordinates
    float2 center = float2(0.5, 0.5);
    float2 p = UV - center;
    
    // Handle dimensions (avoid divide by zero)
    float2 dims = max(float2(Width, Height), 0.0001);
    
    // Normalized space: -0.5 to 0.5 within the bounding box
    // This maps the elliptical/rectangular bounds to a square domain
    float2 q = p / dims;
    
    // Scale factor to convert normalized distance back to world units
    // Using the minimum dimension ensures the stroke isn't overly thinned if one side is squashed
    float distScale = min(dims.x, dims.y);
    
    // 2. Shape Parameters
    // Normalized Thickness (relative to the normalized domain)
    float thNorm = Thickness / distScale;
    float halfTh = thNorm * 0.5;
    
    // Centerline Radius (Rc)
    // We position the ring such that its outer edge touches the bounds (0.5 in q-space)
    float Rc = 0.5 - halfTh;
    
    // Aperture (Gap) geometry
    // aperture is the total gap angle in degrees. We need the half-angle in radians.
    float halfApRad = radians(max(ApertureDeg, 0.0)) * 0.5;
    
    // 3. SDF Calculation
    // Apply symmetry for the C shape (gap is centered at angle 0, i.e., +X axis)
    float2 qs = q;
    qs.y = abs(qs.y);
    
    // Calculate angle in symmetric space [0, PI]
    // atan2(y, x) returns 0..PI since y is positive due to symmetry
    float ang = atan2(qs.y, qs.x);
    
    // --- Round Caps Logic ---
    // Find closest point on the centerline arc
    // We clamp the angle to the solid region [halfApRad, PI]
    float clampAng = max(ang, halfApRad);
    float2 pRound = Rc * float2(cos(clampAng), sin(clampAng));
    float dRound = length(qs - pRound) - halfTh;
    
    // --- Flat Caps Logic (Radial Cut) ---
    // 1. Ring SDF (infinite ring)
    float dRing = abs(length(qs) - Rc) - halfTh;
    
    // 2. Wedge/Gap Plane SDF
    // We define a plane that cuts off the gap.
    // The boundary is at angle 'halfApRad'. The normal should point INTO the gap.
    // Boundary vector: v = (cos(a), sin(a))
    // Normal rotated 90 deg towards gap (angle < a): (sin(a), -cos(a))
    // dot(qs, n) > 0 means we are inside the gap (cut region)
    float2 nGap = float2(sin(halfApRad), -cos(halfApRad));
    float dGap = dot(qs, nGap);
    
    // Intersection: Max of Ring and Gap (cutting away the gap)
    float dFlat = max(dRing, dGap);
    
    // Blend SDFs based on CapStyle (0=Round, 1=Flat)
    float d = lerp(dRound, dFlat, clamp(CapStyle, 0.0, 1.0));
    
    // Convert distance back to world units for correct AA/Stroke
    d *= distScale;
    
    // 4. Rendering
    // Anti-aliasing width
    float aa = fwidth(d);
    
    // Fill Mask (d < 0 is inside the shape)
    float fillAlpha = 1.0 - smoothstep(-aa, aa, d);
    
    // Outline Mask
    // We render the outline as a larger shape behind the fill (Outer Stroke)
    // dOutline < 0 means inside the inflated shape
    float dOutline = d - OutlineWidth;
    float outlineAlpha = 1.0 - smoothstep(-aa, aa, dOutline);
    
    // Composite Layers
    // Layer 1: Outline (Background)
    float4 colLayer = float4(OutlineColor.rgb, OutlineColor.a * outlineAlpha);
    // Layer 2: Fill (Foreground)
    float4 fillLayer = float4(FillColor.rgb, FillColor.a * fillAlpha);
    
    // Put Fill OVER Outline
    outColor = nm_over(fillLayer, colLayer);
}