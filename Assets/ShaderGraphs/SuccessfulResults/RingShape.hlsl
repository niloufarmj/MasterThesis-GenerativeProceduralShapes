void RingShape_float(float2 UV, float2 Center, float Radius, float Thickness, float4 Color, out float4 outColor)
{
    // User Request: a ring shape with a hole in the middle that I can adjust in size and thickness
    // PLAN:
    // 1) Offset UV by Center.
    // 2) Calculate Euclidean distance from center.
    // 3) Compute SDF: abs(distance - Radius) - (Thickness * 0.5).
    // 4) Compute AA mask using fwidth.
    // 5) Output color using straight alpha blending.

    float2 p = UV - Center;
    float d = length(p);
    
    // Convert total thickness to half-width for SDF calculation
    // Thickness represents the total visual width of the ring
    float halfWidth = Thickness * 0.5;
    
    // SDF: Distance from the ring's spine (Radius) minus half-width
    // Result is negative inside the ring body, positive outside
    float sdf = abs(d - Radius) - halfWidth;
    
    // Analytic anti-aliasing
    // Use fwidth for screen-space consistent softness
    float delta = fwidth(sdf);
    float mask = 1.0 - smoothstep(0.0, max(delta, 0.000001), sdf);
    
    // Output straight alpha (RGB unmultiplied, Alpha multiplied by mask)
    // This works best with Unity ShaderGraph's "Transparent" surface type
    outColor = float4(Color.rgb, Color.a * mask);
}

// ------------------------------------------------------------------------
//  Visual Result (High-level, parameter-invariant description)
// ------------------------------------------------------------------------
//  This function generates a **minimalist 2D ring (annulus)** using
//  Signed Distance Functions (SDFs).
//
//  The visual result is composed of:
//  - A circular band defined by a central spine and a set width.
//  - A completely hollow, transparent center.
//
//  The geometry features adjustable **Radius** (overall size) and 
//  **Thickness** (width of the band), allowing for variations ranging 
//  from thin wireframe circles to thick washer-like shapes.
//
//  The output is an anti-aliased RGBA color suitable for selection cursors,
//  target reticles, and decorative circular UI elements.
// ------------------------------------------------------------------------