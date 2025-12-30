void CartoonRainbow_float(
    float2 UV,
    float2 Center,
    float Radius,
    float BandCount,
    float CutoffY,
    float4 Color1, float Width1,
    float4 Color2, float Width2,
    float4 Color3, float Width3,
    float4 Color4, float Width4,
    float4 Color5, float Width5,
    float4 Color6, float Width6,
    float4 Color7, float Width7,
    out float4 outColor
)
{
    // PLAN:
    // 1. Calculate distance from Center.
    // 2. Define an accumulation color.
    // 3. Unroll a loop for up to 7 bands (since ShaderGraph doesn't support arrays).
    // 4. For each band, calculate a ring mask using smoothstep for AA.
    // 5. Accumulate color (bands are concentric and meet exactly, so additive weights work for AA).
    // 6. Apply a vertical clipping mask for the semi-circle (Arc Height).
    // 7. Output final color.

    float2 p = UV - Center;
    float dist = length(p);
    
    // Calculate Anti-Aliasing width based on screen derivatives
    // Fallback to small value if derivatives are zero
    float aa = fwidth(dist);
    aa = max(aa, 0.0005);

    float4 totalColor = float4(0, 0, 0, 0);
    float currentOuter = Radius;
    int count = (int)clamp(BandCount, 0.0, 7.0);

    // Band 1 (Outermost)
    if (count >= 1) {
        float w = max(Width1, 0.0);
        float currentInner = currentOuter - w;
        // Mask: 1.0 inside outer edge, 0.0 inside inner edge
        // The intersection of "inside outer" and "outside inner"
        float alpha = (1.0 - smoothstep(currentOuter - aa, currentOuter + aa, dist)) * smoothstep(currentInner - aa, currentInner + aa, dist);
        totalColor += Color1 * alpha;
        currentOuter -= w;
    }

    // Band 2
    if (count >= 2) {
        float w = max(Width2, 0.0);
        float currentInner = currentOuter - w;
        float alpha = (1.0 - smoothstep(currentOuter - aa, currentOuter + aa, dist)) * smoothstep(currentInner - aa, currentInner + aa, dist);
        totalColor += Color2 * alpha;
        currentOuter -= w;
    }

    // Band 3
    if (count >= 3) {
        float w = max(Width3, 0.0);
        float currentInner = currentOuter - w;
        float alpha = (1.0 - smoothstep(currentOuter - aa, currentOuter + aa, dist)) * smoothstep(currentInner - aa, currentInner + aa, dist);
        totalColor += Color3 * alpha;
        currentOuter -= w;
    }

    // Band 4
    if (count >= 4) {
        float w = max(Width4, 0.0);
        float currentInner = currentOuter - w;
        float alpha = (1.0 - smoothstep(currentOuter - aa, currentOuter + aa, dist)) * smoothstep(currentInner - aa, currentInner + aa, dist);
        totalColor += Color4 * alpha;
        currentOuter -= w;
    }

    // Band 5
    if (count >= 5) {
        float w = max(Width5, 0.0);
        float currentInner = currentOuter - w;
        float alpha = (1.0 - smoothstep(currentOuter - aa, currentOuter + aa, dist)) * smoothstep(currentInner - aa, currentInner + aa, dist);
        totalColor += Color5 * alpha;
        currentOuter -= w;
    }

    // Band 6
    if (count >= 6) {
        float w = max(Width6, 0.0);
        float currentInner = currentOuter - w;
        float alpha = (1.0 - smoothstep(currentOuter - aa, currentOuter + aa, dist)) * smoothstep(currentInner - aa, currentInner + aa, dist);
        totalColor += Color6 * alpha;
        currentOuter -= w;
    }

    // Band 7 (Innermost)
    if (count >= 7) {
        float w = max(Width7, 0.0);
        float currentInner = currentOuter - w;
        float alpha = (1.0 - smoothstep(currentOuter - aa, currentOuter + aa, dist)) * smoothstep(currentInner - aa, currentInner + aa, dist);
        totalColor += Color7 * alpha;
        currentOuter -= w;
    }

    // Vertical Clipping (Semi-Circle)
    // p.y must be > CutoffY. CutoffY is relative to Center.y
    // Typically 0.0 for a half-circle.
    float clipMask = smoothstep(CutoffY - aa, CutoffY + aa, p.y);

    // Apply clip and output
    outColor = totalColor * clipMask;
}