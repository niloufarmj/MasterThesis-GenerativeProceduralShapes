#ifndef PI
#define PI 3.14159265359
#endif

// --- Helpers ---

// Alpha Blending: SRC over DST
inline float4 cup_over(float4 src, float4 dst) {
    float a = src.a + dst.a * (1.0 - src.a);
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-8);
    return float4(c, a);
}

// SDF: Trapezoid (Isosceles)
// widthBottom, widthTop, height are full dimensions
inline float cup_sdTrapezoid(float2 p, float widthBottom, float widthTop, float height) {
    float2 k1 = float2(widthTop, height);
    float2 k2 = float2(widthTop - widthBottom, 2.0 * height);
    p.x = abs(p.x);
    float2 p_mod = p - 0.5 * k1;
    
    // Edge distance
    float2 CA = float2(k2.x, -k2.y);
    float2 PA = float2(p_mod.x - 0.5*k2.x, p_mod.y + 0.5*k2.y);
    float h = clamp( dot(PA,CA)/dot(CA,CA), 0.0, 1.0 );
    float s = sign(CA.x*PA.y - CA.y*PA.x);
    float dEdge = length(PA - CA*h);
    
    // Top/Bottom distance
    float dBase = length(max(float2(p_mod.x, abs(p_mod.y) - 0.5*height), 0.0));
    
    // Combine logic (interior vs exterior)
    // Simplified interior check for isosceles trapezoid:
    // Distance to side line
    return (s > 0.0) ? dEdge : -min(dEdge, abs(p.y) < 0.5*height ? (0.5*widthTop - p.x) : 1.0);
}

// Simplified/Robust Trapezoid using segment distance
inline float cup_sdTrapezoidRobust(float2 p, float wb, float wt, float h) {
    float halfH = h * 0.5;
    float halfWB = wb * 0.5;
    float halfWT = wt * 0.5;
    
    // Vertices
    float2 v0 = float2(-halfWB, -halfH); // Bottom Left
    float2 v1 = float2( halfWB, -halfH); // Bottom Right
    float2 v2 = float2( halfWT,  halfH); // Top Right
    float2 v3 = float2(-halfWT,  halfH); // Top Left
    
    // We only need right side due to symmetry
    float2 pSym = float2(abs(p.x), p.y);
    
    // Distance to right segment (v1 to v2)
    float2 pa = pSym - v1;
    float2 ba = v2 - v1;
    float t = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    float dEdge = length(pa - ba * t);
    
    // Exterior/Interior sign
    // Right normal (outward)
    float2 n = normalize(float2(ba.y, -ba.x));
    float s = dot(pa, n);
    
    // Vertical bounds
    float dy = max(abs(p.y) - halfH, 0.0);
    float dx = max(pSym.x - max(halfWB, halfWT), 0.0); // Rough bound
    
    // Combine: Exact is complex, approximate for 2D icon is sufficient
    // Let's use IQ's implementation logic explicitly adapted:
    p.x = abs(p.x);
    float H = h;
    float Wb = wb * 0.5;
    float Wt = wt * 0.5;
    
    float k1 = Wb;
    float k2 = Wt - Wb;
    float k3 = H;
    
    // Remap to bottom-center relative
    float2 pb = p;
    pb.y += H * 0.5;
    
    // Side line
    float2 e = float2(k2, k3);
    float2 q = pb - float2(k1, 0.0);
    float val = dot(q, e) / dot(e, e);
    val = clamp(val, 0.0, 1.0);
    float2 closest = float2(k1, 0.0) + val * e;
    float dSide = length(pb - closest);
    
    // Sign
    // Cross product z-comp of (e) and (pb - (k1,0))
    float cp = e.x * q.y - e.y * q.x;
    float sideSign = sign(cp);
    
    // Top/Bottom caps
    float dVertical = abs(pb.y - H * 0.5) - H * 0.5;
    
    // Combined Distance (Approximate signed)
    if (pb.y < 0.0) return length(max(float2(abs(pb.x) - Wb, -pb.y), 0.0));
    if (pb.y > H)   return length(max(float2(abs(pb.x) - Wt, pb.y - H), 0.0));
    
    return dSide * sideSign;
}

// SDF: Ellipse
inline float cup_sdEllipse(float2 p, float2 r) {
    float k0 = length(p/r);
    float k1 = length(p/(r*r));
    return k0*(k0-1.0)/k1;
}

// SDF: Heart (Inigo Quilez)
inline float cup_sdHeart(float2 p) {
    p.x = abs(p.x);
    if(p.y + p.x > 1.0)
        return sqrt(dot(p - float2(0.25, 0.75), p - float2(0.25, 0.75))) - sqrt(2.0)/4.0;
    return sqrt(min(dot(p - float2(0.00, 1.00), p - float2(0.00, 1.00)),
                    dot(p - 0.5 * max(p.x + p.y, 0.0), p - 0.5 * max(p.x + p.y, 0.0)))) * sign(p.x - p.y);
}

// --- Main Function ---
// User Request: A cartoon cupcake with trapezoidal wrapper, pleats, rounded frosting, heart topper.
void CartoonCupcake_float(
    float2 UV,
    float WrapperBottomWidth,
    float WrapperTopWidth,
    float WrapperHeight,
    float4 WrapperColor,
    float PleatSpacing,
    float PleatThickness,
    float FrostingHeight,
    float FrostingSpread,
    float4 FrostingColor,
    float HeartSize,
    float4 HeartColor,
    float StrokeThickness,
    float4 StrokeColor,
    out float4 outColor)
{
    // PLAN:
    // 1) Normalize UV to centered coordinates.
    // 2) Define positions for Wrapper, Frosting, and Heart.
    // 3) Calculate SDFs for each shape.
    // 4) Apply Pleats logic to Wrapper mask.
    // 5) Composite layers back-to-front (Wrapper -> Frosting -> Heart) with outlines.

    float2 p = UV - 0.5;
    float aa = fwidth(length(p));
    float halfStroke = StrokeThickness * 0.5;
    
    // --- 1. GEOMETRY SETUP ---
    // Shift everything down slightly to center visual mass
    float totalH = WrapperHeight + FrostingHeight + HeartSize;
    float yOffset = -totalH * 0.35;
    p.y -= yOffset;
    
    // Wrapper Center
    float2 pWrap = p;
    // Wrapper is drawn from center, so move p so wrapper base is at desired Y
    // Let wrapper center be at (0, 0) relative to pWrap
    
    // Frosting Center (sits on top of wrapper)
    // Wrapper top is at +WrapperHeight/2
    float2 pFrost = p - float2(0.0, WrapperHeight * 0.5);
    
    // Heart Center (sits on top of frosting)
    // Heart bottom tip should be embedded in frosting
    float2 pHeart = p - float2(0.0, WrapperHeight * 0.5 + FrostingHeight * 0.6);

    // --- 2. SDF CALCULATION ---
    
    // WRAPPER SDF
    float dWrap = cup_sdTrapezoidRobust(pWrap, WrapperBottomWidth, WrapperTopWidth, WrapperHeight);
    
    // FROSTING SDF (Ellipse)
    // Flatten bottom of ellipse slightly to sit better? Standard ellipse is fine.
    float dFrost = cup_sdEllipse(pFrost, float2(FrostingSpread * 0.5, FrostingHeight * 0.5));
    
    // HEART SDF
    // Scale heart space. The SDF assumes a specific size approx 1.0 height.
    float2 heartSpace = pHeart / max(HeartSize, 0.001);
    // Offset Y because Heart SDF is centered around top lobes usually
    heartSpace.y -= 0.5;
    float dHeartRaw = cup_sdHeart(heartSpace);
    float dHeart = dHeartRaw * HeartSize; // Restore scale

    // --- 3. RENDERING LAYERS ---
    
    // Initialize Output
    outColor = float4(0, 0, 0, 0);

    // --- LAYER 1: WRAPPER ---
    {
        // Fill
        float fillMask = 1.0 - smoothstep(-aa, aa, dWrap);
        
        // Pleats (Vertical Stripes)
        // Only calculate where wrapper exists
        float4 baseColor = WrapperColor;
        if (fillMask > 0.01) {
            // Stripe pattern
            float stripeX = pWrap.x;
            // Map x to 0..1 range across width for cleaner distribution? 
            // Or just screen space stripes. Screen space is easier for "vertical lines".
            float stripeDist = abs(frac(stripeX * (1.0/max(PleatSpacing, 0.001))) - 0.5) * max(PleatSpacing, 0.001);
            float stripeMask = 1.0 - smoothstep(0.0, aa, stripeDist - PleatThickness * 0.5 * PleatSpacing);
            
            // Darken wrapper color for pleats
            float3 pleatRGB = baseColor.rgb * 0.8;
            baseColor.rgb = lerp(baseColor.rgb, pleatRGB, stripeMask * 0.5);
        }

        // Outline
        float strokeMask = 1.0 - smoothstep(-aa, aa, abs(dWrap) - halfStroke);
        
        // Composite Wrapper
        float4 layerCol = cup_over(float4(StrokeColor.rgb, StrokeColor.a * strokeMask), float4(baseColor.rgb, baseColor.a * fillMask));
        outColor = cup_over(layerCol, outColor);
    }

    // --- LAYER 2: FROSTING ---
    {
        float fillMask = 1.0 - smoothstep(-aa, aa, dFrost);
        float strokeMask = 1.0 - smoothstep(-aa, aa, abs(dFrost) - halfStroke);
        
        float4 layerCol = cup_over(float4(StrokeColor.rgb, StrokeColor.a * strokeMask), float4(FrostingColor.rgb, FrostingColor.a * fillMask));
        outColor = cup_over(layerCol, outColor);
    }

    // --- LAYER 3: HEART ---
    {
        float fillMask = 1.0 - smoothstep(-aa, aa, dHeart);
        float strokeMask = 1.0 - smoothstep(-aa, aa, abs(dHeart) - halfStroke);
        
        float4 layerCol = cup_over(float4(StrokeColor.rgb, StrokeColor.a * strokeMask), float4(HeartColor.rgb, HeartColor.a * fillMask));
        outColor = cup_over(layerCol, outColor);
    }
}