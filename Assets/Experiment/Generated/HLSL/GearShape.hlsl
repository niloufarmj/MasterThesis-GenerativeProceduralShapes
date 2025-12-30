/*
  User Request: Mechanical gear shape with evenly spaced teeth, adjustable teeth count, depth, size, and separate colors for body and hole.
*/

#ifndef PI
#define PI 3.14159265359
#endif

// Helper: 2D Rotation
float2 Rotate2D(float2 p, float angle) {
    float c = cos(angle);
    float s = sin(angle);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

// Helper: Box SDF
// p: position relative to box center
// b: half-extents (width/2, height/2)
float sdBox(float2 p, float2 b) {
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

void GearShape_float(float2 UV, float TeethCount, float Size, float ToothDepth, float HoleRadius, float Rotation, float4 BodyColor, float4 HoleColor, out float4 outColor) {
    // PLAN:
    // 1) Center UVs and apply overall rotation.
    // 2) Divide space into angular sectors based on TeethCount.
    // 3) Rotate local coordinates to align each tooth with the X-axis.
    // 4) Construct the Gear Body (Disk) and Tooth (Box) SDFs.
    // 5) Union them to form the solid gear shape.
    // 6) Calculate the Hole SDF.
    // 7) Generate anti-aliased masks for Gear and Hole.
    // 8) Composite BodyColor and HoleColor (Hole visually punches through or sits on top).

    float2 p = UV - 0.5;
    
    // 1) Apply Rotation
    p = Rotate2D(p, -Rotation); // Rotate world opposite to rotate shape

    // Safe geometric parameters
    float N = max(3.0, round(TeethCount));
    float rOuter = Size;
    float rInner = max(0.001, Size - ToothDepth);
    
    // 2) Angular Repetition (Polar Coordinates)
    float angleStep = 2.0 * PI / N;
    float currentAngle = atan2(p.y, p.x);
    
    // Determine which sector we are in (round to nearest index)
    float sector = floor(currentAngle / angleStep + 0.5);
    
    // 3) Local Rotate to Sector
    // We rotate p by -sectorAngle to bring the current sector's center to the X-axis (angle 0)
    float sectorAngle = sector * angleStep;
    float2 pLocal = Rotate2D(p, -sectorAngle);
    
    // 4) Shape Definition
    // TOOTH: A box located at the rim
    // Center X: midpoint between inner and outer radius
    float toothCenterX = rInner + ToothDepth * 0.5;
    // Width (X): half the depth
    float toothHalfDepth = ToothDepth * 0.5;
    // Height (Y): approximate arc length at the inner radius for 50% duty cycle
    // Arc = radius * angle. Sector angle is angleStep. Tooth is half of sector. Half-extent is half of that.
    float toothHalfWidth = (rInner * angleStep) * 0.25;
    
    float dTooth = sdBox(pLocal - float2(toothCenterX, 0.0), float2(toothHalfDepth, toothHalfWidth));
    
    // BODY: A circle at the inner radius
    float dBody = length(p) - rInner;
    
    // GEAR: Union of Body and Tooth
    float dGear = min(dBody, dTooth);
    
    // HOLE: Circle at center
    float dHole = length(p) - HoleRadius;
    
    // 5) Anti-aliasing
    // fwidth gives the change in value per pixel, perfect for smoothstep range
    float aa = fwidth(length(p));
    // Ensure a minimum AA width to prevent artifacts when zooming far out
    aa = max(aa, 0.0001);
    
    // Masks (0 = outside, 1 = inside)
    float gearMask = smoothstep(aa, -aa, dGear);
    float holeMask = smoothstep(aa, -aa, dHole);
    
    // 6) Composition
    // The gear body exists where the Gear is solid AND the Hole is empty.
    // We calculate a mask strictly for the body part.
    // saturate(gearMask - holeMask) handles the subtraction cleanly.
    float bodyAlpha = saturate(gearMask - holeMask);
    
    // The hole layer is just the hole mask.
    float holeAlpha = holeMask;
    
    // Pre-multiply alpha for correct blending
    float4 bodyLayer = float4(BodyColor.rgb * bodyAlpha, BodyColor.a * bodyAlpha);
    float4 holeLayer = float4(HoleColor.rgb * holeAlpha, HoleColor.a * holeAlpha);
    
    // Final Combine: Since body and hole regions are non-overlapping (due to subtraction),
    // we can simply add the layers.
    outColor = bodyLayer + holeLayer;
}