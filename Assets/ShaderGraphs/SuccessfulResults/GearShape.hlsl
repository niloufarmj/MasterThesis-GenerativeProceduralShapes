// PLAN:
// 1) Define standard math constants (PI, TAU) if missing.
// 2) Define helper function sdBox for the gear teeth.
// 3) In main function, center UVs to (-1,1) range based on Size.
// 4) Apply rotation to the coordinate system.
// 5) Use polar domain repetition to replicate a single tooth N times (Teeth count).
// 6) Compute SDF: Union of central disk and the repeated tooth box.
// 7) Subtract an inner circle for the gear hole.
// 8) Compute anti-aliased edge mask and output final color.

#ifndef PI
#define PI 3.14159265359
#endif

#ifndef TAU
#define TAU 6.28318530718
#endif

// Signed distance to a 2D box
// p: position relative to box center
// b: half-dimensions (width/2, height/2)
float sdBox(float2 p, float2 b) {
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

void GearShape_float(float2 UV, float Size, float Teeth, float ToothLength, float ToothWidth, float HoleRadius, float Rotation, float4 Color, out float4 outColor) {
    // 1. Centering and adjusting coordinates
    // Map UV (0..1) to centered space. We do NOT pre-scale by Size here 
    // because we want Size to represent the radius directly in UV units.
    float2 p = UV - 0.5;

    // 2. Apply global Rotation
    float cosR = cos(Rotation);
    float sinR = sin(Rotation);
    p = float2(cosR * p.x - sinR * p.y, sinR * p.x + cosR * p.y);

    // 3. Polar Domain Repetition for Teeth
    // Ensure safe tooth count
    float n = max(Teeth, 3.0);
    float sectorAngle = TAU / n;
    
    // Calculate the polar angle of the current pixel
    float angle = atan2(p.y, p.x);
    
    // Determine which sector (tooth) we are in
    // floor(x + 0.5) rounds to nearest integer sector index
    float sectorID = floor(angle / sectorAngle + 0.5);
    
    // Compute the center angle of this sector
    float centerAngle = sectorID * sectorAngle;
    
    // Rotate p into the local coordinate system of the sector
    // We rotate by -centerAngle so the tooth aligns with the +X axis
    float c = cos(centerAngle);
    float s = sin(centerAngle);
    // Inverse rotation: x' = x*c + y*s, y' = -x*s + y*c
    float2 pLocal = float2(p.x * c + p.y * s, -p.x * s + p.y * c);

    // 4. Construct Gear SDF
    // A gear is a central disk (root) + N teeth (boxes)
    
    // A) Central Disk (Root Circle)
    float dRoot = length(p) - Size;
    
    // B) Tooth Shape (Box)
    // The tooth sits on the rim. Center X = Size + HalfLength.
    float2 toothBoxSize = float2(ToothLength * 0.5, ToothWidth * 0.5);
    float2 toothCenter = float2(Size + toothBoxSize.x - 0.005, 0.0); // 0.005 overlap to merge smoothly
    float dTooth = sdBox(pLocal - toothCenter, toothBoxSize);
    
    // Union: min(Disk, Tooth)
    // We use a smooth min or simple min. A simple min is sharper.
    float dShape = min(dRoot, dTooth);
    
    // C) Inner Hole
    // We subtract the hole. Subtraction in SDF is max(d, -dHole)
    if (HoleRadius > 0.001) {
        float dHole = length(p) - HoleRadius;
        dShape = max(dShape, -dHole);
    }

    // 5. Anti-aliasing
    // Compute soft edge based on screen-space derivatives
    float aa = fwidth(dShape);
    float mask = smoothstep(aa, -aa, dShape);

    // 6. Output Color
    // Apply mask to Alpha. Multiply RGB by mask for premultiplied-like blending or just masking.
    // Standard transparent output:
    outColor = float4(Color.rgb, Color.a * mask);
}

// ------------------------------------------------------------------------
//  Visual Result (High-level, parameter-invariant description)
// ------------------------------------------------------------------------
//  This function generates a **2D gear- or cog-like primitive** using
//  Signed Distance Functions (SDFs).
//
//  The shape consists of a circular base with multiple evenly distributed
//  protruding elements around its perimeter, and an optional circular
//  cutout at the center. The number, size, spacing, orientation, and
//  proportions of these elements are fully controlled by input parameters
//  and are not fixed by the function itself.
//
//  The output is an anti-aliased RGBA color suitable for icons,
//  technical symbols, and analytic procedural 2D graphics.
// ------------------------------------------------------------------------
