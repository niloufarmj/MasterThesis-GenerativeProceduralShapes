/* 
  PLAN:
  1. Define SDF helpers: sdRoundedBox for body, sdBox for wick, sdVesica for flame.
  2. Center the coordinate system (UV - 0.5).
  3. Position elements vertically:
     - Body centered at a lower offset to make room for flame.
     - Wick on top of body.
     - Flame on top of wick.
  4. Calculate SDFs for each part based on width/height inputs.
  5. For the flame, convert width/height to Vesica parameters (radius and offset).
  6. Compute anti-aliased masks using smoothstep.
  7. Composite layers: Body (bottom), Wick (middle), Flame (top) using alpha blending logic.
  8. Output final color.
*/

#ifndef PI
#define PI 3.14159265359
#endif

// Helper: Signed Distance to a Box with rounded corners
float sdRoundedBox_Candle(float2 p, float2 b, float r) {
    float2 q = abs(p) - b + r;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

// Helper: Signed Distance to a Box (sharp corners)
float sdBox_Candle(float2 p, float2 b) {
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// Helper: Signed Distance to a Vesica (Shape intersection of two circles) - Perfect for flames
// r = radius of circles, d = offset of circle centers from axis
float sdVesica_Candle(float2 p, float r, float d) {
    p = abs(p);
    float b = sqrt(r*r - d*d);
    return ((p.y - b) * d > p.x * b) ? length(p - float2(0.0, b))
                                     : length(p - float2(-d, 0.0)) - r;
}

void CartoonCandle_float(float2 UV, float BodyWidth, float BodyHeight, float4 BodyColor, float WickWidth, float WickHeight, float4 WickColor, float FlameWidth, float FlameHeight, float4 FlameColor, out float4 outColor) {
    // Center coordinates
    float2 p = UV - 0.5;
    
    // --- Positioning ---
    // We want the whole assembly to look centered. 
    // Let's anchor the Body's center. 
    // To keep the visual center reasonable, we place the body slightly lower.
    float2 bodyPos = float2(0.0, -0.15);
    
    // Wick sits on top of body
    // Body top Y = bodyPos.y + BodyHeight/2
    // Wick center Y = BodyTop + WickHeight/2
    float2 wickPos = float2(0.0, bodyPos.y + BodyHeight * 0.5 + WickHeight * 0.5);
    
    // Flame sits on top of wick
    // Wick top Y = wickPos.y + WickHeight/2
    // Flame center Y: Vesica logic is centered at 0. 
    // The Vesica flame goes from -FlameHeight/2 to +FlameHeight/2 relative to its center.
    // We want Flame Bottom to overlap Wick Top slightly.
    float overlap = 0.02;
    float2 flamePos = float2(0.0, wickPos.y + WickHeight * 0.5 + FlameHeight * 0.5 - overlap);

    // --- SDF Calculations ---
    
    // 1. Body SDF
    // Use a small rounding radius for soft cartoon feel
    float bodyRound = 0.02;
    float dBody = sdRoundedBox_Candle(p - bodyPos, float2(BodyWidth * 0.5, BodyHeight * 0.5), bodyRound);
    
    // 2. Wick SDF
    float dWick = sdBox_Candle(p - wickPos, float2(WickWidth * 0.5, WickHeight * 0.5));
    
    // 3. Flame SDF (Vesica)
    // Convert Width/Height to Vesica parameters r and d
    // Math: r = (W^2 + H^2) / (4H), d = r - H/2
    // Ensure safe division
    float fH = max(FlameHeight, 0.001);
    float fW = max(FlameWidth, 0.001);
    float rVesica = (fW*fW + fH*fH) / (4.0 * fH);
    float dVesica = rVesica - fH * 0.5;
    float dFlame = sdVesica_Candle(p - flamePos, rVesica, dVesica);
    
    // --- Rendering ---
    // Smoothstep for anti-aliasing
    float aa = 0.005;
    
    float maskBody = 1.0 - smoothstep(-aa, aa, dBody);
    float maskWick = 1.0 - smoothstep(-aa, aa, dWick);
    float maskFlame = 1.0 - smoothstep(-aa, aa, dFlame);
    
    // Composite Layers (Painters Algorithm)
    // Order: Body -> Wick -> Flame
    
    float3 colorAccum = float3(0.0, 0.0, 0.0);
    float alphaAccum = 0.0;
    
    // Layer 1: Body
    colorAccum = lerp(colorAccum, BodyColor.rgb, maskBody);
    alphaAccum = max(alphaAccum, maskBody);
    
    // Layer 2: Wick (on top of body)
    colorAccum = lerp(colorAccum, WickColor.rgb, maskWick);
    alphaAccum = max(alphaAccum, maskWick);
    
    // Layer 3: Flame (on top of wick)
    colorAccum = lerp(colorAccum, FlameColor.rgb, maskFlame);
    alphaAccum = max(alphaAccum, maskFlame);
    
    // Final Output
    outColor = float4(colorAccum * alphaAccum, alphaAccum);
}

// ------------------------------------------------------------------------
//  Visual Result (High-level, parameter-invariant description)
// ------------------------------------------------------------------------
//  This function generates a **stylized 2D cartoon candle**
//  using Signed Distance Functions (SDFs).
//
//  The visual result is composed of three distinct stacked elements:
//  - A vertical rectangular body with rounded corners (the wax).
//  - A thin vertical segment sitting on top of the body (the wick).
//  - A pointed oval "Vesica" shape hovering above the wick (the flame).
//
//  The elements are vertically aligned and composited using a "Painter's Algorithm"
//  approach (Body -> Wick -> Flame) to ensure correct layering.
//  The dimensions and colors of each component are fully adjustable, allowing
//  for tall tapers, short votives, or distinct flame styles.
//
//  The output is an anti-aliased RGBA color suitable for game props,
//  UI icons, and ambient lighting effects.
// ------------------------------------------------------------------------