#ifndef PI
#define PI 3.14159265359
#endif

// --- Helper Functions ---

float BC_hash21(float2 p) {
    p = frac(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return frac(p.x * p.y);
}

float BC_noise(float2 p) {
    float2 i = floor(p);
    float2 f = frac(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    return lerp(
        lerp(BC_hash21(i + float2(0.0, 0.0)), BC_hash21(i + float2(1.0, 0.0)), u.x),
        lerp(BC_hash21(i + float2(0.0, 1.0)), BC_hash21(i + float2(1.0, 1.0)), u.x),
        u.y
    );
}

float BC_fbm(float2 p) {
    float v = 0.0;
    float a = 0.5;
    float2 shift = float2(100.0, 100.0);
    for (int i = 0; i < 3; ++i) {
        v += a * BC_noise(p);
        p = p * 2.0 + shift;
        a *= 0.5;
    }
    return v;
}

float BC_sdBox(float2 p, float2 b) {
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// --- Main Function ---

void BrickColumn_float(
    float2 UV,
    float totalHeight,
    float totalWidth,
    float columnDepth,
    float brickRowCount,
    float brickHeight,
    float brickLength,
    float brickOffsetAmount,
    float mortarThickness,
    float4 mortarColor,
    float featureDensity,
    float brickColorVariation,
    float surfaceRoughness,
    float cornerChipAmount,
    float4 brickColor,
    out float4 outColor
) {
    float2 p = UV - 0.5;
    
    // 1. Column Proportions & Bounding Masks
    float safeBrickRowCount = max(1.0, brickRowCount);
    float activeHeight = min(totalHeight, safeBrickRowCount * brickHeight);
    float halfH = activeHeight * 0.5;
    float halfW = totalWidth * 0.5;

    // Calculate vertical metrics
    float yOffset = p.y + halfH;
    float rowIndex = floor(yOffset / brickHeight);
    
    // Determine the topmost visible row to act as the cap
    float maxRow = min(floor(safeBrickRowCount) - 1.0, floor((activeHeight - 1e-4) / brickHeight));
    float isCapRegion = step(abs(rowIndex - maxRow), 0.1);
    
    // Base Body Distance
    float bodyDist = BC_sdBox(p, float2(halfW, halfH));
    
    // Cap Distance (slightly wider for the overhang effect based on columnDepth)
    float capYPos = maxRow * brickHeight + brickHeight * 0.5 - halfH;
    float capDist = BC_sdBox(p - float2(0.0, capYPos), float2(halfW + columnDepth * 0.5, brickHeight * 0.5));
    
    // Composite Column Distance
    float colMaskDist = min(bodyDist, capDist);
    
    // Add subtle structural imperfections to the overall column silhouette
    float chipNoise = BC_fbm(p * (10.0 + featureDensity * 80.0));
    colMaskDist += (chipNoise - 0.5) * cornerChipAmount * 0.005;
    
    float colMask = smoothstep(0.005, -0.005, colMaskDist);
    
    // Hard clip outside of defined row counts to ensure clean bounds
    colMask *= step(rowIndex, maxRow + 0.5) * step(-0.5, rowIndex);

    // 2. Brick Pattern Domain Repetition (Running Bond)
    float rowOffset = 0.0;
    if (isCapRegion > 0.5) {
        // The top cap bricks are usually symmetrically aligned, not shifted
        rowOffset = 0.0;
    } else {
        // Alternate rows are shifted
        rowOffset = fmod(abs(rowIndex), 2.0) * brickOffsetAmount;
    }
    
    float xPos = p.x + rowOffset;
    
    // Floor-based tiling to prevent negative mirroring issues
    float xOffsetP = xPos + brickLength * 0.5;
    float localX = (xOffsetP - brickLength * floor(xOffsetP / brickLength)) - brickLength * 0.5;
    float yOffsetP = yOffset;
    float localY = (yOffsetP - brickHeight * floor(yOffsetP / brickHeight)) - brickHeight * 0.5;
    
    float colIndex = floor(xOffsetP / brickLength);

    // 3. Individual Brick SDF generation
    float2 bExtents = float2(brickLength * 0.5 - mortarThickness * 0.5, brickHeight * 0.5 - mortarThickness * 0.5);
    float bDist = BC_sdBox(float2(localX, localY), bExtents);
    
    // Add micro-chipping specific to the brick edges
    bDist += (chipNoise - 0.5) * cornerChipAmount * 0.02;
    float brickMask = smoothstep(0.005, -0.005, bDist);

    // 4. Brick Texturing & Color Variation
    float randomBrickSeed = BC_hash21(float2(rowIndex, colIndex));
    float colorVar = (randomBrickSeed - 0.5) * brickColorVariation;
    
    float3 currentColor = brickColor.rgb + colorVar;
    
    // Lighter highlight for the topmost cap bricks
    if (isCapRegion > 0.5) {
        currentColor += 0.12;
    }

    // Apply gritty surface texture roughness
    float texNoise = BC_fbm(p * (50.0 + surfaceRoughness * 200.0));
    currentColor -= texNoise * surfaceRoughness * 0.25;
    
    // Internal ambient occlusion / bevel effect on brick edges
    float innerEdge = smoothstep(-0.005, -0.04, bDist);
    currentColor = lerp(currentColor * 0.75, currentColor, innerEdge);

    // Overall column edge darkening to give the full column a 3D bevel appearance
    float colInnerEdge = smoothstep(-0.005, -0.03, colMaskDist);
    currentColor = lerp(currentColor * 0.8, currentColor, colInnerEdge);

    // 5. Mortar blending
    float3 finalColor = lerp(mortarColor.rgb, currentColor, brickMask);
    
    // Add grime and texture variations to the mortar
    float mNoise = BC_noise(p * 200.0);
    finalColor -= mNoise * 0.08 * (1.0 - brickMask);

    // Output with crisp anti-aliased column boundaries
    outColor = float4(finalColor, colMask);
}

// ------------------------------------------------------------------------
//  Visual Result (High-level, parameter-invariant description)
// ------------------------------------------------------------------------
//  This function produces a **2D representation of a brick column** in a front-facing view. The resulting shape features:
//
//  - A central rectangular column section composed of a grid-like pattern of bricks.
//  - A running bond pattern is observed, with alternating rows of bricks horizontally offset.
//  - Uniform grey-white mortar lines separate each brick, defining the grid structure.
//  - The column ends with a slightly wider top cap, giving it a finished look.
//  - Bricks exhibit subtle textural details and occasional small chips at the edges, adding realism.
//  - The overall appearance is sharply defined with clean edges around each brick and the column perimeters.
// ------------------------------------------------------------------------
