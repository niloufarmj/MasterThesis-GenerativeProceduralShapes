void DNAHelixShape_float(float2 UV, float Amplitude, float LoopHeight, float StrandThickness, float RungSpacing, float RungThickness, float4 BackboneColor, float4 RungColor, float4 OutlineColor, float OutlineWidth, out float4 outColor) {
    // PLAN:
    // 1) Center UVs at (0,0) and handle spacing/frequency inputs.
    // 2) Define SDF for the two sine wave strands (Backbones).
    // 3) Define SDF for the horizontal rungs using domain repetition on Y.
    // 4) Combine SDFs to create the base shape and the outline.
    // 5) Layer the colors: Outline -> Rungs -> Backbones.
    // 6) Output final color with anti-aliasing.

    // 1. Setup Coordinates and Constants
    float2 p = UV - 0.5;
    
    // Clamp inputs to prevent division by zero or artifacts
    LoopHeight = max(LoopHeight, 0.001);
    RungSpacing = max(RungSpacing, 0.001);
    float freq = 6.28318530718 / LoopHeight; // 2*PI / LoopHeight

    // 2. Strand SDF (Backbones)
    // Approximated distance to x = A*sin(ky) and x = -A*sin(ky)
    // Formula: d = |x - f(y)| / sqrt(1 + f'(y)^2)
    float sineVal = Amplitude * sin(freq * p.y);
    float cosVal = Amplitude * freq * cos(freq * p.y);
    float normFactor = sqrt(1.0 + cosVal * cosVal);
    
    // Two strands: one at +sineVal, one at -sineVal
    // We calculate distance to both and take the min
    float dStrand1 = abs(p.x - sineVal) / normFactor;
    float dStrand2 = abs(p.x + sineVal) / normFactor;
    
    // Final strand distance (subtracting radius = half thickness)
    float distStrands = min(dStrand1, dStrand2) - (StrandThickness * 0.5);

    // 3. Rung SDF (Base Pairs)
    // Identify the closest rung index based on Y position
    float rungID = round(p.y / RungSpacing);
    float rungY = rungID * RungSpacing;
    
    // Calculate the horizontal span of the helix at this rung's height
    // The rung connects the two strands at y = rungY
    float rungHalfWidth = abs(Amplitude * sin(freq * rungY));
    
    // Calculate distance to the rung segment
    // Transform p to be relative to the rung's center Y
    float2 localP = p;
    localP.y -= rungY;
    
    // SDF for a horizontal segment of length 2*rungHalfWidth centered at 0
    // dist = length(vec2(distX, distY))
    float distToRungSegment = length(float2(max(abs(localP.x) - rungHalfWidth, 0.0), localP.y));
    float distRungs = distToRungSegment - (RungThickness * 0.5);

    // 4. Composition
    // Combine shapes: Union of Strands and Rungs
    float distShape = min(distStrands, distRungs);
    
    // 5. Coloring & Anti-aliasing
    // Smoothstep values for AA (using constant width for stability)
    float aa = 0.005;
    
    // Calculate masks for each layer
    // Outer Mask: Everything within the outline width
    float outlineDist = distShape - OutlineWidth;
    float maskOutline = 1.0 - smoothstep(-aa, aa, outlineDist);
    
    // Rung Mask: Inside the rung shapes
    float maskRungs = 1.0 - smoothstep(-aa, aa, distRungs);
    
    // Strand Mask: Inside the strand shapes
    float maskStrands = 1.0 - smoothstep(-aa, aa, distStrands);
    
    // Layering using Painter's Algorithm (Back to Front)
    // Base: Transparent -> Outline -> Rungs -> Strands
    float3 finalRGB = OutlineColor.rgb;
    
    // Blend Rung Color over Outline
    finalRGB = lerp(finalRGB, RungColor.rgb, maskRungs);
    
    // Blend Backbone Color over Rungs (Strands appear on top/front)
    finalRGB = lerp(finalRGB, BackboneColor.rgb, maskStrands);
    
    // Apply total opacity based on the outline mask
    outColor = float4(finalRGB * maskOutline, maskOutline);
}

// ------------------------------------------------------------------------
//  Visual Result
// ------------------------------------------------------------------------
//  This function generates a **stylized cartoon DNA helix** using 
//  Signed Distance Functions (SDFs).
//
//  The visual result is composed of:
//  - Two sinusoidal **backbone strands** that weave back and forth vertically,
//    forming the classic double-helix structure.
//  - A series of horizontal **rungs** (base pairs) connecting the two strands.
//    The width of each rung dynamically adjusts to match the distance 
//    between the strands at that specific height.
//
//  The shape features adjustable parameters for the wave amplitude and 
//  frequency (loop height), the thickness of the strands and rungs, and the 
//  vertical spacing between rungs.
//
//  The output is a flat-shaded graphic with a thick, cohesive outline. The
//  rendering layers the strands visually on top of the rungs, making it 
//  ideal for biology icons, educational games, or medical UI elements.
// ------------------------------------------------------------------------