#ifndef PI
#define PI 3.14159265359
#endif

// Rotate a 2D vector by an angle in radians
float2 rotate(float2 p, float angle) {
    float s = sin(angle);
    float c = cos(angle);
    return float2(p.x * c - p.y * s, p.x * s + p.y * c);
}

// Signed Distance to a 2D Arc (Symmetric about Y axis)
// p: point, sc: sin/cos of aperture half-angle, ra: radius, rb: thickness
float sdArc(float2 p, float2 sc, float ra, float rb) {
    p.x = abs(p.x);
    return ((sc.y * p.x > sc.x * p.y) ? length(p - sc * ra) : 
           abs(length(p) - ra)) - rb;
}

// Signed Distance to an Isosceles Triangle
// p: point, q: dimensions (width/2, height)
// Triangle tip is at (0,0), pointing in -Y direction if q.y > 0
float sdIsosceles(float2 p, float2 q) {
    p.x = abs(p.x);
    float2 a = p - q * clamp(dot(p, q) / dot(q, q), 0.0, 1.0);
    float2 b = p - q * float2(clamp(p.x / q.x, 0.0, 1.0), 1.0);
    float k = sign(q.y);
    float d = min(dot(a, a), dot(b, b));
    float s = max(k * (p.x * q.y - p.y * q.x), k * (p.y - q.y));
    return sqrt(d) * sign(s);
}

void CartoonCycleIcon_float(float2 UV, float Size, float Radius, float Thickness, float GapDistance, float HeadSize, float HeadWidth, float OutlineWidth, float4 Color, float4 OutlineColor, float GlossStrength, out float4 outColor) {
    // PLAN:
    // 1) Center and scale UVs. Apply rotational symmetry for the two segments.
    // 2) Calculate geometric properties (angles, lengths) based on Gap and Head size.
    // 3) Construct the Arc Body using sdArc, shifted to accommodate the head.
    // 4) Construct the Arrow Head using sdIsosceles, positioned at the arc tip.
    // 5) Combine Body and Head with min() for the base shape.
    // 6) Compute Gloss/Highlight mask.
    // 7) Apply AA and compositing for Fill, Outline, and Gloss.

    // 1) Normalized coordinates centered at 0
    float2 p = UV - 0.5;
    // Scale by Size (avoid divide by zero)
    p /= max(Size, 0.001);

    // Symmetry: The shape consists of two identical arrows rotated 180 degrees.
    // We calculate distance to one arrow (top) and the other (bottom) and take the min.
    // Or simply min(d(p), d(-p)).

    // --- Single Arrow Construction (Top Arrow, CCW flow) ---
    // Geometric Setup
    float R = max(Radius, 0.01);
    float halfThick = Thickness * 0.5;
    
    // Gap is defined as linear distance along the circle? Or direct gap?
    // Approximating gap angle from linear gap distance: theta = arcLen / radius
    float gapAngle = GapDistance / R;
    
    // Total available angle for one arrow is PI (180 deg) minus the gap.
    // Symmetrical gap means we subtract half gap from each end.
    // So the arrow spans from Angle = -PI/2 + Gap/2 to +PI/2 - Gap/2? 
    // Let's stick to the Y-axis symmetry of sdArc. 
    // Angle 0 is Y-axis (Top). Right is -90 (-PI/2), Left is +90 (+PI/2).
    // Total span of the sector is PI. We remove gapAngle from the total.
    // Half-span (Aperture) = (PI - gapAngle) / 2.0
    float totalAperture = (PI - gapAngle) * 0.5;
    totalAperture = max(totalAperture, 0.001);

    // Head Geometry
    // The head sits at the 'tip' end of the arc (Positive angle side for CCW flow).
    // We need to shorten the arc body by the length of the head so they join cleanly.
    float headLenAng = HeadSize / R;
    float bodyAperture = totalAperture - headLenAng * 0.5;
    // Shift the arc center so the tail stays at -totalAperture
    float arcShiftAngle = headLenAng * 0.5;
    
    // 1. Arc Body SDF
    // We evaluate the arc for both p and -p to get the full cycle.
    // Helper function for the single arrow shape SDF:
    float d_shape = 1e9;
    
    // We iterate 2 times for the two symmetric segments
    for(int i=0; i<2; i++) {
        float2 q = (i==0) ? p : -p;
        
        // A) Arc Body
        // Rotate q to align the shifted arc center with Y axis
        float2 q_body = rotate(q, -arcShiftAngle);
        float2 sc = float2(sin(bodyAperture), cos(bodyAperture));
        float d_body = sdArc(q_body, sc, R, halfThick);
        
        // B) Arrow Head
        // Tip is located at the end of the full aperture (Positive angle side)
        float tipAngle = totalAperture;
        // Position of the tip (Angle 0 is Y-axis)
        // CCW flow: Tip is at Left (+Angle)
        float2 tipPos = float2(-sin(tipAngle), cos(tipAngle)) * R;
        
        // Orientation: Tangent to circle at tip.
        // Tangent direction for CCW flow at angle theta is (-cos theta, -sin theta)
        float2 tipDir = float2(-cos(tipAngle), -sin(tipAngle));
        
        // Transform q into Head Space
        // Translate to tip
        float2 q_head = q - tipPos;
        // Rotate so tipDir points down (-Y) to match sdIsosceles default
        // Angle of tipDir:
        float headRotAng = atan2(tipDir.y, tipDir.x) + PI/2.0;
        q_head = rotate(q_head, -headRotAng);
        
        // Calculate Triangle SDF
        // Width/2 and Height
        float d_head = sdIsosceles(q_head, float2(HeadWidth * 0.5, HeadSize));
        
        // Union of Body and Head
        float d_arrow = min(d_body, d_head);
        
        // Union with the other arrow
        d_shape = min(d_shape, d_arrow);
    }

    // 3) Gloss / Highlight
    // A simpler, thinner arc segment on the top-right of the upper arrow
    float2 p_gloss = rotate(p, PI/4.0); // Rotate 45 deg
    float2 sc_gloss = float2(sin(0.4), cos(0.4)); // Fixed small aperture
    float d_gloss = sdArc(p_gloss - float2(0, 0.02), sc_gloss, R, halfThick * 0.3);
    float glossMask = smoothstep(0.02, 0.0, d_gloss);
    
    // 4) Compositing
    float aa = fwidth(d_shape);
    
    // Fill Mask
    float fillMask = smoothstep(aa, -aa, d_shape);
    
    // Outline Mask
    // Outline is drawn outside the shape (d > 0) and slightly inside?
    // Let's do a centered stroke or exterior. Usually exterior for icons.
    // Distance to edge is abs(d_shape) if centered, or d_shape - width if exterior.
    // Standard: Outline is a border around the fill.
    float d_outline = d_shape - OutlineWidth;
    float outlineMask = smoothstep(aa, -aa, d_outline);
    
    // Composite Colors
    // Start with Outline
    float4 finalColor = OutlineColor;
    // Blend Fill over Outline
    finalColor = lerp(finalColor, Color, fillMask);
    // Mask the whole shape (outline + fill)
    float shapeAlpha = outlineMask;
    
    // Apply Gloss (Screen blend or additive)
    // Only visible on the Fill area
    float3 glossCol = float3(1.0, 1.0, 1.0) * glossMask * GlossStrength * fillMask;
    finalColor.rgb += glossCol;

    // Apply total alpha
    outColor = float4(finalColor.rgb * shapeAlpha, finalColor.a * shapeAlpha);
}

// ------------------------------------------------------------------------
//  Visual Result (High-level, parameter-invariant description)
// ------------------------------------------------------------------------
//  This function generates a **stylized 2D cycle icon** (recycle/sync style)
//  using Signed Distance Functions (SDFs).
//
//  The visual result is composed of:
//  - Two symmetric curved arrow segments arranged in a circular loop.
//  - Each segment consists of an arc body terminating in a pointed triangular
//    arrowhead.
//  - The gap between the head of one arrow and the tail of the next is
//    fully adjustable.
//
//  The shape features a consistent outline and optional glossy highlights
//  on the arrow bodies. All geometric properties (radius, thickness,
//  head size, gap distance) are parameterized.
//
//  The output is an anti-aliased RGBA color suitable for refresh buttons,
//  recycling symbols, and loading indicators.
// ------------------------------------------------------------------------