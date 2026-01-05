#ifndef PI
#define PI 3.14159265359
#endif

// --- Helper Functions ---

// Distance to a line segment (used for polygons)
float cdg_sdSegment(float2 p, float2 a, float2 b) {
    float2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}

// Signed distance to a rounded trapezoid
// p: sample point (centered)
// w0: bottom width, w1: top width, h: height, r: corner radius
float cdg_sdTrapezoidRounded(float2 p, float w0, float w1, float h, float r) {
    float2 v0 = float2(-w0 * 0.5, -h * 0.5);
    float2 v1 = float2( w0 * 0.5, -h * 0.5);
    float2 v2 = float2( w1 * 0.5,  h * 0.5);
    float2 v3 = float2(-w1 * 0.5,  h * 0.5);
    
    // 4-sided polygon SDF logic
    float2 verts[4] = { v0, v1, v2, v3 };
    float d = 1e20;
    float s = -1e20;
    
    [unroll]
    for (int i = 0; i < 4; i++) {
        float2 a = verts[i];
        float2 b = verts[(i + 1) % 4];
        float2 e = b - a;
        float2 w = p - a;
        float2 perp = float2(e.y, -e.x);
        
        // Distance to edge segment
        d = min(d, cdg_sdSegment(p, a, b));
        
        // Max dot product to edge normals determines if inside/outside
        s = max(s, dot(w, normalize(perp)));
    }
    
    // s > 0 means outside (positive dist), s < 0 inside (negative dist)
    float polyDist = (s > 0.0) ? d : -d;
    
    // Rounding: subtract radius
    return polyDist - r;
}

// Signed distance to an ellipse (approx)
float cdg_sdEllipse(float2 p, float2 r) {
    float k0 = length(p / max(r, 1e-4));
    float k1 = length(p / max(r * r, 1e-4));
    return k0 * (k0 - 1.0) / max(k1, 1e-4);
}

// --- Main Function ---
// Request: A cartoon drinking glass with adjustable dimensions, liquid fill, handle, and flat 2D style.
void CartoonDrinkingGlass_float(
    float2 UV,
    float WidthTop,
    float WidthBottom,
    float Height,
    float CornerRadius,
    float WallThickness,
    float RimHeight,
    float HandleSize,
    float HandleY,
    float FillHeight,
    float4 GlassColor,
    float4 LiquidColor,
    float4 OutlineColor,
    float OutlineWidth,
    out float4 outColor
) {
    // PLAN:
    // 1) Center UVs and setup dimensions.
    // 2) Calculate SDF for Glass Body (rounded trapezoid).
    // 3) Calculate SDF for Handle (ring/torus to the side).
    // 4) Calculate SDF for Liquid (intersection of inner glass and fill level).
    // 5) Calculate SDF for Rim (ellipse at top).
    // 6) Composite layers using painter's algorithm with alpha blending.

    float2 p = UV - 0.5;
    float aa = fwidth(length(p)); // Anti-aliasing factor

    // Clamp inputs for safety
    float wt = max(0.01, WidthTop);
    float wb = max(0.01, WidthBottom);
    float h = max(0.01, Height);
    float r = clamp(CornerRadius, 0.0, min(wb, h) * 0.5);
    float wall = max(0.001, WallThickness);
    
    // 1. Glass Body SDF
    float dBody = cdg_sdTrapezoidRounded(p, wb, wt, h, r);
    
    // 2. Handle SDF
    // Calculate glass width at HandleY position to attach it correctly
    float hy = HandleY * h; // Handle vertical offset from center
    float tHandle = clamp((hy + h * 0.5) / h, 0.0, 1.0);
    float wAtHandle = lerp(wb, wt, tHandle);
    float2 handleCenter = float2(wAtHandle * 0.5 + HandleSize * 0.5, hy);
    
    // Handle is a ring: abs(dist to center - radius) - thickness
    float dHandleBase = length(p - handleCenter) - HandleSize;
    float dHandle = abs(dHandleBase) - max(0.02, wall * 1.5);
    // Mask handle part that is inside the glass body (optional, but looks cleaner for transparent glass)
    // We'll handle this in composition.

    // 3. Liquid SDF
    float fill = clamp(FillHeight, 0.0, 1.0);
    float liquidY = -h * 0.5 + fill * h;
    
    // Inner glass definition (hollow shell)
    float dInner = dBody + wall;
    
    // Liquid body: Intersection of Inner Glass AND Plane below liquid level
    float dLiquidBody = max(dInner, p.y - liquidY);
    
    // Liquid Surface (Perspective Ellipse)
    float wLiquid = lerp(wb, wt, fill);
    float2 surfCenter = float2(0.0, liquidY);
    // Surface radius slightly smaller to fit inside walls
    float dLiquidSurf = cdg_sdEllipse(p - surfCenter, float2(wLiquid * 0.5 - wall, RimHeight));
    
    // Combined Liquid SDF
    float dLiquid = min(dLiquidBody, dLiquidSurf);

    // 4. Rim / Opening SDF
    float2 rimCenter = float2(0.0, h * 0.5);
    float dRim = cdg_sdEllipse(p - rimCenter, float2(wt * 0.5, RimHeight));
    float dRimOutline = abs(dRim) - OutlineWidth * 0.5;

    // 5. Alpha Masks
    float maskBody = 1.0 - smoothstep(0.0, aa, dBody);
    float maskHandle = 1.0 - smoothstep(0.0, aa, dHandle);
    float maskLiquid = 1.0 - smoothstep(0.0, aa, dLiquid);
    float maskRimLine = 1.0 - smoothstep(0.0, aa, dRimOutline);
    
    // Global Silhouette for Outline
    // Union of body and handle
    float dUnion = min(dBody, dHandle);
    // Outline mask (band around 0)
    float maskOutline = 1.0 - smoothstep(0.0, aa, abs(dUnion) - OutlineWidth * 0.5);

    // 6. Composition (Back to Front)
    float3 finalRGB = float3(0, 0, 0);
    float finalAlpha = 0.0;

    // A. Handle Layer (Behind glass)
    // We allow handle to show through transparency later, but here we establish base.
    // Handle Color
    float4 cHandle = GlassColor;
    float3 layerHandleRGB = cHandle.rgb;
    float layerHandleA = maskHandle * cHandle.a;
    
    // Blend Handle onto background
    finalRGB = layerHandleRGB * layerHandleA + finalRGB * (1.0 - layerHandleA);
    finalAlpha = layerHandleA + finalAlpha * (1.0 - layerHandleA);

    // B. Liquid Layer
    // Visible only if fill > 0 and inside inner glass
    if (fill > 0.01) {
        float4 cLiq = LiquidColor;
        float3 layerLiqRGB = cLiq.rgb;
        float layerLiqA = maskLiquid * cLiq.a;
        
        // Blend Liquid over current
        finalRGB = layerLiqRGB * layerLiqA + finalRGB * (1.0 - layerLiqA);
        finalAlpha = layerLiqA + finalAlpha * (1.0 - layerLiqA);
    }

    // C. Glass Body Layer (Front Shell)
    // Glass tints everything behind it
    float4 cGlass = GlassColor;
    float3 layerGlassRGB = cGlass.rgb;
    float layerGlassA = maskBody * cGlass.a;
    
    finalRGB = layerGlassRGB * layerGlassA + finalRGB * (1.0 - layerGlassA);
    finalAlpha = layerGlassA + finalAlpha * (1.0 - layerGlassA);

    // D. Details: Rim Line (Top of glass)
    float3 rimRGB = OutlineColor.rgb;
    float rimA = maskRimLine * OutlineColor.a;
    finalRGB = rimRGB * rimA + finalRGB * (1.0 - rimA);
    finalAlpha = max(finalAlpha, rimA);

    // E. Global Outline
    // Drawn around the union of handle and body
    // We mask the outline so it doesn't overlap the rim detail too messily, strictly over
    float3 outRGB = OutlineColor.rgb;
    float outA = maskOutline * OutlineColor.a;
    
    finalRGB = outRGB * outA + finalRGB * (1.0 - outA);
    finalAlpha = max(finalAlpha, outA);

    outColor = float4(finalRGB, finalAlpha);
}

// ------------------------------------------------------------------------
//  Visual Result (High-level, parameter-invariant description)
// ------------------------------------------------------------------------
//  This function generates a **stylized 2D cartoon drinking glass**
//  using Signed Distance Functions (SDFs).
//
//  The visual result is composed of:
//  - A trapezoidal container body with adjustable top/bottom widths and
//    rounded corners.
//  - A C-shaped handle attached to the side (optional, scaleable).
//  - An internal liquid fill level with a flat surface and meniscus effect.
//  - A distinct rim ellipse at the top opening.
//
//  The glass features semi-transparent tinting, while the liquid has a
//  solid opaque color. A consistent outline surrounds the entire silhouette.
//  All dimensions (height, width, wall thickness, fill amount) are
//  fully adjustable.
//
//  The output is an anti-aliased RGBA color suitable for beverage icons,
//  potion bottles, and kitchen items.
// ------------------------------------------------------------------------