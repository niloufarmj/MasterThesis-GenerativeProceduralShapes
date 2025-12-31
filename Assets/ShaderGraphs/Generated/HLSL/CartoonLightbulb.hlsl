// PLAN:
// 1. Define standard SDF primitives (Circle, Box, Segment, smin).
// 2. Setup UVs centered at (0,0) in range [-1,1].
// 3. Compute SDF for Light Rays (radial array of capsules).
// 4. Compute SDF for Glass Body (Smooth union of Circle and Box).
// 5. Compute SDF for Base (Box with sine-wave displacement for ribs).
// 6. Compute SDF for Filament (Curved arc with thickness).
// 7. Composite layers using Painter's Algorithm with smooth alpha blending and clean strokes.

#ifndef PI
#define PI 3.14159265359
#endif

// --- Helpers ---

float sdCircle(float2 p, float r) {
    return length(p) - r;
}

float sdBox(float2 p, float2 b) {
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

float sdSegment(float2 p, float2 a, float2 b) {
    float2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}

// Smooth Min (Polynomial) for organic blending
float smin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return lerp(b, a, h) - k * h * (1.0 - h);
}

float2 rotate(float2 p, float angle) {
    float c = cos(angle);
    float s = sin(angle);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

// --- Main Function ---
void CartoonLightbulb_float(
    float2 UV,
    float2 BodySize,      // Width, Height of glass body
    float4 BodyColor,
    float2 BaseSize,      // Width, Height of metal base
    float BaseRibs,       // Frequency of ribs
    float4 BaseColor,
    float FilamentSize,   // Thickness/Scale
    float4 FilamentColor,
    float RayCount,
    float RayLength,
    float RayOffset,
    float4 RayColor,
    float StrokeWidth,
    float4 StrokeColor,
    out float4 outColor)
{
    // 1. Coordinates: Center UV to [-1, 1] relative to unit size
    float2 p = (UV - 0.5) * 2.0;
    float aa = length(fwidth(p)) * 0.707; // Analytic anti-aliasing width

    // 2. Light Rays SDF (Background Layer)
    float dRays = 100.0;
    if (RayCount > 0.5)
    {
        // Radial domain repetition
        float n = max(floor(RayCount), 1.0);
        float angleSector = (2.0 * PI) / n;
        float currentAngle = atan2(p.y, p.x);
        float r = length(p);
        
        // Get sector ID and local angle
        float id = floor(currentAngle / angleSector + 0.5);
        float centerAngle = id * angleSector;
        
        // Rotate p into the local coordinate of the nearest ray
        float2 pRay = rotate(p, -centerAngle);
        
        // Ray shape: Capsule along X axis
        float2 rayStart = float2(RayOffset, 0.0);
        float2 rayEnd = float2(RayOffset + RayLength, 0.0);
        // Ray thickness derived from FilamentSize for consistency, or fixed
        float rayThickness = 0.05;
        dRays = sdSegment(pRay, rayStart, rayEnd) - rayThickness;
    }

    // 3. Glass Body SDF (Pear Shape)
    // Combine top circle and bottom rounded box/circle
    // Parameters
    float bodyW = max(BodySize.x, 0.05);
    float bodyH = max(BodySize.y, 0.05);
    
    // Top bulb part
    float2 topCenter = float2(0.0, bodyH * 0.2);
    float dTop = sdCircle(p - topCenter, bodyW);
    
    // Bottom neck part
    float2 neckSize = float2(bodyW * 0.6, bodyH * 0.5);
    float2 neckCenter = float2(0.0, -bodyH * 0.6);
    float dNeck = sdBox(p - neckCenter, neckSize);
    
    // Smooth union to make it pear-shaped
    float dBody = smin(dTop, dNeck, 0.15);

    // 4. Metal Base SDF
    // Placed at the bottom of the neck
    float baseW = max(BaseSize.x, 0.05);
    float baseH = max(BaseSize.y, 0.05);
    float2 baseCenter = float2(0.0, neckCenter.y - neckSize.y + baseH * 0.5);
    // Adjust base position to sit nicely on the pear bottom
    baseCenter = float2(0.0, -bodyH * 0.95);
    
    float2 pBase = p - baseCenter;
    float dBaseBox = sdBox(pBase, float2(baseW, baseH));
    
    // Add Ribs (Sine wave displacement on Y axis)
    // Only apply displacement to the side edges implies modulating distance
    float ribs = sin(pBase.y * BaseRibs * 20.0) * 0.02;
    float dBase = dBaseBox + ribs;

    // 5. Filament SDF
    // A curved wire inside the bulb
    float2 pFil = p - topCenter; // Center relative to top bulb
    // Simple arch: Circle outline, cut off bottom
    float filRadius = bodyW * 0.5;
    float dFilCurve = abs(sdCircle(pFil, filRadius)) - FilamentSize * 0.1;
    // Cut off the bottom part of the circle to make an arch
    float dFilCut = pFil.y + filRadius * 0.2; // Cut plane
    float dFilament = max(dFilCurve, -dFilCut);
    // Add 'loop shape' wiggle
    dFilament += sin(pFil.x * 10.0) * 0.01;

    // --- Rendering / Composition ---
    // Initialize color (transparent)
    outColor = float4(0, 0, 0, 0);

    // A. Draw Rays
    if (RayCount > 0.5) {
        float rayMask = smoothstep(aa, -aa, dRays);
        outColor = lerp(outColor, RayColor, rayMask);
    }

    // B. Draw Glass Body Fill
    float bodyMask = smoothstep(aa, -aa, dBody);
    outColor = lerp(outColor, BodyColor, bodyMask);

    // C. Draw Filament (masked to be inside body)
    // Only visible where body is visible
    float filMask = smoothstep(aa, -aa, dFilament);
    filMask *= bodyMask;
    outColor = lerp(outColor, FilamentColor, filMask);

    // D. Draw Glass Outline
    // Outline is a band around the zero-distance isosurface
    float bodyOutlineMask = smoothstep(0.0, aa, abs(dBody) - StrokeWidth);
    // Invert to get the stroke line
    bodyOutlineMask = 1.0 - bodyOutlineMask;
    outColor = lerp(outColor, StrokeColor, bodyOutlineMask);

    // E. Draw Base Fill (sits on top of glass bottom)
    float baseMask = smoothstep(aa, -aa, dBase);
    outColor = lerp(outColor, BaseColor, baseMask);

    // F. Draw Base Outline
    float baseOutlineMask = 1.0 - smoothstep(0.0, aa, abs(dBase) - StrokeWidth);
    outColor = lerp(outColor, StrokeColor, baseOutlineMask);
    
    // Final clamping to ensure valid color
    outColor = saturate(outColor);
}