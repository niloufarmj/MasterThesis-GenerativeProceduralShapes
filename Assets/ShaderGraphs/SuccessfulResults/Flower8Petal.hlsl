#ifndef PI
#define PI 3.14159265359
#endif

void Flower8Petal_float(float2 UV, float2 Center, float Radius, float PetalLength, float PetalWidth, float Rotation, float4 Color, out float4 outColor) {
    // PLAN:
    // 1) Translate UVs to center and apply rotation.
    // 2) Convert to polar coordinates (radius and angle).
    // 3) Create an 8-petal shape function using cos(8*angle).
    // 4) Apply 'PetalWidth' as an exponent to shape the petals (thinner vs fatter).
    // 5) define the boundary radius = BaseRadius + PetalLength * shape.
    // 6) Compute signed distance approx (dist = r - boundary).
    // 7) Apply anti-aliasing and output color.

    // 1. Center and Rotate
    float2 p = UV - Center;
    
    // Rotate point by -Rotation to rotate the shape by +Rotation
    float c = cos(Rotation);
    float s = sin(Rotation);
    p = float2(c * p.x + s * p.y, -s * p.x + c * p.y);
    
    // 2. Polar Coordinates
    float r = length(p);
    float a = atan2(p.y, p.x);
    
    // 3. Petal Shape Calculation
    // Base wave for 8 petals: cos(8*a) ranges from -1 to 1
    // Map to 0..1 range: 0.5 + 0.5 * cos(8*a)
    float wave = 0.5 + 0.5 * cos(8.0 * a);
    
    // 4. Adjust Petal Width
    // Use power function to control 'fatness'.
    // PetalWidth = 1.0 -> Standard sine wave petals
    // PetalWidth > 1.0 -> Thinner, spikier petals
    // PetalWidth < 1.0 -> Fatter, rounder petals
    // Clamp width to avoid negative exponents or divide by zero issues
    float shape = pow(max(0.0, wave), max(0.01, PetalWidth));
    
    // 5. Define Variable Radius
    // The radius of the flower edge at angle 'a'
    float boundary = max(0.0, Radius) + PetalLength * shape;
    
    // 6. Approximate Signed Distance
    // Positive outside, negative inside
    float dist = r - boundary;
    
    // 7. Anti-aliasing
    // Use fwidth for screen-space derivative AA
    float edgeAA = fwidth(dist);
    // Fallback for very small derivatives to prevent hard aliasing if fwidth is zero
    edgeAA = max(edgeAA, 0.001);
    
    float mask = 1.0 - smoothstep(0.0, edgeAA, dist);
    
    // 8. Output
    outColor = float4(Color.rgb * mask, mask);
}

// ------------------------------------------------------------------------
//  Visual Result (High-level, parameter-invariant description)
// ------------------------------------------------------------------------
//  This function generates a **radial, flower-like 2D primitive** using
//  a polar-coordinate Signed Distance formulation.
//
//  The shape consists of multiple elongated lobes (petals) distributed
//  evenly around a central region, forming a symmetric floral silhouette.
//  The number, length, width, orientation, scale, and placement of the
//  petals are fully controlled by input parameters and are not fixed by
//  the function itself.
//
//  The output is an anti-aliased RGBA color suitable for decorative,
//  symbolic, and expressive procedural 2D graphics.
// ------------------------------------------------------------------------
