/*
  User Request: A cartoon toast slice with squarish body, rounded bottom corners, double-hump top,
  distinct thick crust, scattered porous holes, and clean outlines.
*/

#ifndef PI
#define PI 3.14159265359
#endif

// --- Helper Functions ---

// 2D Rotation
float2 rotate2D(float2 p, float angle) {
    float s = sin(angle);
    float c = cos(angle);
    return float2(p.x * c - p.y * s, p.x * s + p.y * c);
}

// Smooth Min (Polynomial) - for blending shapes
float smin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return lerp(b, a, h) - k * h * (1.0 - h);
}

// Signed Distance to a Box
float sdBox(float2 p, float2 b) {
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// Signed Distance to a Circle
float sdCircle(float2 p, float r) {
    return length(p) - r;
}

// Pseudo-random 2D from 2D
float2 hash22(float2 p) {
    float3 p3 = frac(float3(p.xyx) * float3(.1031, .1030, .0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return frac((p3.xx+p3.yz)*p3.zy);
}

// Pseudo-random 1D from 1D
float hash11(float n) {
    return frac(sin(n) * 43758.5453123);
}

// --- Main Toast Function ---
void CartoonToastSlice_float(
    float2 UV,
    float2 Center,
    float Rotation,
    float Width,
    float Height,
    float TopCurvature,
    float BottomCornerRadius,
    float CrustThickness,
    float4 BreadColor,
    float4 CrustColor,
    float4 HoleColor,
    float HoleCount,
    float HoleSize,
    float HoleSeed,
    float StrokeWidth,
    float4 StrokeColor,
    out float4 outColor)
{
    // PLAN:
    // 1. Center and rotate UVs.
    // 2. Construct Toast Shape SDF:
    //    - Base: A rectangle with rounded corners (biased to bottom).
    //    - Top: Two circles smoothly blended with the base to form the "double hump".
    // 3. Construct Holes SDF:
    //    - Loop (fixed max iterations) using hash functions to place scattered circles.
    // 4. Compute Masks:
    //    - AA edges using smoothstep and fwidth.
    //    - Separate regions: Stroke, Crust, Bread, Holes.
    // 5. Composite Colors in order: Bread -> Holes -> Crust -> Stroke.

    // 1. Coordinates
    float2 p = UV - Center;
    p = rotate2D(p, Rotation);

    // Clamp inputs for safety
    float w = max(Width, 0.01) * 0.5; // Half-width
    float h = max(Height, 0.01) * 0.5; // Half-height
    float r_corner = min(BottomCornerRadius, min(w, h));
    float r_hump = w * 0.5 * max(TopCurvature, 0.1);
    
    // 2. Toast SDF Construction
    
    // A. Main Body (Box with rounded bottom)
    // Shift box down slightly so the humps sit on top
    float bodyHeight = h * 1.0;
    float2 boxPos = p - float2(0.0, -h * 0.1); 
    
    // Rounded Box (approximated by shrinking box and subtracting radius)
    // We want mainly bottom corners rounded. 
    // Let's use a standard rounded box for the base, positioned lower.
    float2 bodySize = float2(w, h * 0.7);
    float d_body = sdBox(boxPos, bodySize - r_corner) - r_corner;

    // B. Top Humps
    // Two circles positioned at top-left and top-right of the body
    float humpOffsetY = h * 0.5 - r_hump * 0.5;
    float humpOffsetX = w * 0.5;
    
    float2 leftHumpPos = p - float2(-humpOffsetX, humpOffsetY);
    float2 rightHumpPos = p - float2(humpOffsetX, humpOffsetY);
    
    float d_humpLeft = sdCircle(leftHumpPos, r_hump);
    float d_humpRight = sdCircle(rightHumpPos, r_hump);
    
    float d_humps = min(d_humpLeft, d_humpRight);
    
    // Combine body and humps smoothly to get that soft bread look
    // smin factor k determines how "melty" the join is
    float d_shape = smin(d_body, d_humps, 0.05 * min(w,h));

    // 3. Holes SDF
    float d_holes = 100.0;
    // Limit iterations to a fixed number for shader compatibility
    // We use 'HoleCount' to scale probability or radius, effectively showing fewer holes
    int maxHoles = 10;
    float safeHoleCount = clamp(HoleCount, 0.0, 10.0);
    
    for(int i = 0; i < maxHoles; i++) {
        if (float(i) >= safeHoleCount) break;
        
        // Random position based on seed + index
        float2 seed2 = float2(HoleSeed, float(i) * 13.5);
        float2 rndPos = (hash22(seed2) - 0.5) * 2.0; // -1 to 1
        
        // Constrain holes to be somewhat inside the toast
        rndPos.x *= w * 0.6;
        rndPos.y *= h * 0.6;
        
        // Random radius
        float rndRad = hash11(float(i) * 7.7 + HoleSeed) * 0.5 + 0.5;
        float currentHoleSize = HoleSize * rndRad;
        
        float dist = length(p - rndPos) - currentHoleSize;
        d_holes = smin(d_holes, dist, 0.02); // Soft blend holes slightly for organic look
    }

    // 4. Rendering / Compositing
    
    // Anti-aliasing width
    float aa = fwidth(d_shape);
    // Fallback if fwidth is zero (e.g. static preview)
    aa = max(aa, 0.001);
    
    // Masks
    // Outline Mask: where abs(dist) < strokeWidth/2
    float halfStroke = StrokeWidth * 0.5;
    float strokeAlpha = 1.0 - smoothstep(halfStroke, halfStroke + aa, abs(d_shape));
    
    // Shape Coverage: Inside the shape (d < 0)
    // We expand slightly by halfStroke to ensure outline sits on edge
    float shapeAlpha = 1.0 - smoothstep(0.0, aa, d_shape - halfStroke);
    
    // Crust Region: Inside shape, but close to edge
    // Bread is where d < -CrustThickness
    float breadMask = 1.0 - smoothstep(-CrustThickness, -CrustThickness + aa, d_shape);
    
    // Holes Mask: Inside bread region AND inside hole SDF
    // Holes are subtracted from Bread color
    float holeMask = 1.0 - smoothstep(0.0, aa, d_holes);
    // Ensure holes only appear on bread part, not crust or stroke
    holeMask *= breadMask;

    // 5. Final Color Mixing
    
    // Start with Crust Color (base of the shape)
    float3 finalRGB = CrustColor.rgb;
    
    // Blend Bread Color on top (inner part)
    finalRGB = lerp(finalRGB, BreadColor.rgb, breadMask);
    
    // Blend Holes on top of Bread
    finalRGB = lerp(finalRGB, HoleColor.rgb, holeMask);
    
    // Blend Stroke on top of everything
    // Note: Standard stroking logic usually puts stroke on the boundary
    // Here, we interpolate based on strokeAlpha. 
    // Since strokeAlpha is for the boundary line, we mix it last.
    // However, we must ensure the stroke is opaque.
    finalRGB = lerp(finalRGB, StrokeColor.rgb, strokeAlpha);
    
    // Final Alpha channel
    // The shape is visible if inside stroke or inside shape
    float finalAlpha = max(strokeAlpha, 1.0 - smoothstep(halfStroke, halfStroke + aa, d_shape));
    
    // Pre-multiply alpha for transparency if needed, or just output
    outColor = float4(finalRGB * finalAlpha, finalAlpha);
}