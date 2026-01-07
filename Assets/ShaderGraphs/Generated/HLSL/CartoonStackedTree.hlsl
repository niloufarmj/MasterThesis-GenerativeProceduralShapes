#ifndef PI
#define PI 3.14159265359
#endif

// --- Helper Functions ---

// Pseudo-random hash
float2 hash22(float2 p) {
    float3 p3 = frac(float3(p.xyx) * float3(.1031, .1030, .0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return frac((p3.xx+p3.yz)*p3.zy);
}

// Box Signed Distance Field
float sdBox(float2 p, float2 b) {
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// Rounded Box Signed Distance Field
float sdRoundedBox(float2 p, float2 b, float r) {
    float2 q = abs(p) - b + r;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

// Leaf Pattern SDF (Scattered rectangles in a grid)
float sdLeafPattern(float2 p, float density, float size) {
    // Ensure density is valid to avoid divide by zero
    float dScale = max(density, 1.0);
    
    // Create grid space
    float2 gridUV = p * dScale;
    float2 cellID = floor(gridUV);
    float2 localUV = frac(gridUV) - 0.5;
    
    // Randomize per cell
    float2 rnd = hash22(cellID);
    
    // Random position offset within cell
    localUV += (rnd - 0.5) * 0.6;
    
    // Random leaf existence threshold (40% chance of leaf)
    if (rnd.x > 0.4) return 1.0; // Return positive distance (empty space)
    
    // Leaf dimensions (randomized slightly)
    // Base size is relative to cell size. Input 'size' should be 0..1 range typically.
    float2 leafDims = float2(size, size * 0.6) * (0.8 + 0.4 * rnd.y);
    
    // Compute SDF in grid space then scale back to world space
    float d = sdBox(localUV, leafDims);
    return d / dScale;
}

// Helper to blend layers (Source Over Destination)
// Expects straight RGB and Alpha inputs. Returns straight RGB and Alpha.
float4 blendLayers(float4 dest, float4 src) {
    float outA = src.a + dest.a * (1.0 - src.a);
    float3 outRGB = (src.rgb * src.a + dest.rgb * dest.a * (1.0 - src.a));
    if (outA > 0.0001) outRGB /= outA;
    else outRGB = dest.rgb;
    return float4(outRGB, outA);
}

void CartoonStackedTree_float(
    float2 UV,
    float TrunkWidth,
    float4 TrunkColor,
    float BaseHeight,
    float BlockGap,
    float LeafDensity,
    float LeafSize,
    float4 LeafColor,
    float BotActive, float2 BotSize, float BotRound, float BotOffset, float4 BotColor,
    float MidActive, float2 MidSize, float MidRound, float MidOffset, float4 MidColor,
    float TopActive, float2 TopSize, float TopRound, float TopOffset, float4 TopColor,
    out float4 outColor
) {
    // PLAN:
    // 1) Normalize coordinates to center X at 0.0 and start Y near 0.0.
    // 2) Calculate the vertical stacking positions of the foliage blocks based on inputs.
    // 3) Determine total trunk height (from ground to top of highest active block).
    // 4) Compute Trunk SDF and Base Color Layer.
    // 5) Compute Global Leaf Pattern SDF.
    // 6) Iterate through Bottom, Middle, Top blocks: Compute SDF, Mask, Mix Leaf Color, Blend Layer.
    // 7) Output final composite with premultiplied alpha.

    // 1. Coordinate Setup
    float2 p = UV;
    p.x -= 0.5; // Center horizontally
    p.y -= 0.05; // Offset ground slightly up
    
    // Anti-aliasing factor
    float aa = fwidth(p.y);
    if (aa == 0.0) aa = 0.002;

    // 2. Height & Position Calculation
    float currentY = BaseHeight; // Start stacking above the visible trunk base
    float trunkMaxY = BaseHeight; // Trunk must reach at least here
    
    // Calculate centers and update stack height
    float2 cBot = float2(0,0);
    float2 cMid = float2(0,0);
    float2 cTop = float2(0,0);
    
    // Bottom Block Logic
    if (BotActive > 0.5) {
        cBot = float2(BotOffset, currentY + BotSize.y * 0.5);
        trunkMaxY = max(trunkMaxY, currentY + BotSize.y);
        currentY += BotSize.y + BlockGap;
    }
    
    // Middle Block Logic
    if (MidActive > 0.5) {
        cMid = float2(MidOffset, currentY + MidSize.y * 0.5);
        trunkMaxY = max(trunkMaxY, currentY + MidSize.y);
        currentY += MidSize.y + BlockGap;
    }
    
    // Top Block Logic
    if (TopActive > 0.5) {
        cTop = float2(TopOffset, currentY + TopSize.y * 0.5);
        trunkMaxY = max(trunkMaxY, currentY + TopSize.y);
    }
    
    // 3. Trunk SDF
    // Trunk is a box from Y=0 to Y=trunkMaxY
    float trunkCenterY = trunkMaxY * 0.5;
    float2 trunkPos = p - float2(0.0, trunkCenterY);
    float dTrunk = sdBox(trunkPos, float2(TrunkWidth * 0.5, trunkMaxY * 0.5));
    float maskTrunk = 1.0 - smoothstep(0.0, aa, dTrunk);
    
    // Initialize final color with Trunk Layer
    // We use a straight-alpha accumulation buffer
    float4 finalColor = float4(TrunkColor.rgb, maskTrunk * TrunkColor.a);
    // For blendLayers to work cleanly, convert initial state to straight alpha if a > 0
    if (finalColor.a > 0.0) finalColor.rgb /= finalColor.a;
    
    // 4. Global Leaf Pattern SDF
    float dLeaf = sdLeafPattern(UV, LeafDensity, LeafSize);
    float maskLeaf = 1.0 - smoothstep(0.0, aa, dLeaf);
    
    // 5. Foliage Layers Composition
    
    // --- Bottom Block ---
    if (BotActive > 0.5) {
        float d = sdRoundedBox(p - cBot, BotSize * 0.5, BotRound);
        float mask = 1.0 - smoothstep(0.0, aa, d);
        
        // Leaf detail: Mix leaf color if inside leaf shape
        float3 blockRGB = lerp(BotColor.rgb, LeafColor.rgb, maskLeaf * LeafColor.a);
        float4 layer = float4(blockRGB, mask * BotColor.a);
        
        finalColor = blendLayers(finalColor, layer);
    }
    
    // --- Middle Block ---
    if (MidActive > 0.5) {
        float d = sdRoundedBox(p - cMid, MidSize * 0.5, MidRound);
        float mask = 1.0 - smoothstep(0.0, aa, d);
        
        float3 blockRGB = lerp(MidColor.rgb, LeafColor.rgb, maskLeaf * LeafColor.a);
        float4 layer = float4(blockRGB, mask * MidColor.a);
        
        finalColor = blendLayers(finalColor, layer);
    }
    
    // --- Top Block ---
    if (TopActive > 0.5) {
        float d = sdRoundedBox(p - cTop, TopSize * 0.5, TopRound);
        float mask = 1.0 - smoothstep(0.0, aa, d);
        
        float3 blockRGB = lerp(TopColor.rgb, LeafColor.rgb, maskLeaf * LeafColor.a);
        float4 layer = float4(blockRGB, mask * TopColor.a);
        
        finalColor = blendLayers(finalColor, layer);
    }
    
    // 6. Final Output
    // Convert to Premultiplied Alpha for rendering
    outColor = float4(finalColor.rgb * finalColor.a, finalColor.a);
}