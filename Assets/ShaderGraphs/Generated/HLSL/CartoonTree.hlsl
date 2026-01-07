#ifndef PI
#define PI 3.14159265359
#endif

// --- Helper Functions ---

// 2D Box SDF
float sdBox(float2 p, float2 b) {
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// 2D Rounded Box SDF
float sdRoundedBox(float2 p, float2 b, float r) {
    float2 q = abs(p) - b + r;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

// Pseudo-random hash
float2 hash22(float2 p) {
    float3 p3 = frac(float3(p.xyx) * float3(.1031, .1030, .0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return frac((p3.xx+p3.yz)*p3.zy);
}

// Leaf scatter pattern
// Returns a 0..1 mask where leaves are present
float GetLeafMask(float2 uv, float density, float2 leafSize) {
    float2 st = uv * density;
    float2 id = floor(st);
    float mask = 0.0;
    
    // Check 3x3 neighbor grid to handle overlaps
    for(int y = -1; y <= 1; y++) {
        for(int x = -1; x <= 1; x++) {
            float2 offs = float2(x, y);
            float2 n = id + offs;
            
            // Random seed for this cell
            float2 seed = hash22(n);
            
            // Random position within the cell
            // Center the leaf in the cell + jitter
            float2 cellCenter = offs + seed;
            
            // Local coordinate relative to the leaf center
            float2 localPos = frac(st) - cellCenter;
            
            // Random rotation
            float ang = (seed.x * 2.0 - 1.0) * 2.0; // +/- 2 radians
            float s = sin(ang);
            float c = cos(ang);
            localPos = float2(c * localPos.x - s * localPos.y, s * localPos.x + c * localPos.y);
            
            // Leaf SDF (simple box)
            // Randomize size slightly based on seed.y
            float2 size = leafSize * (0.8 + 0.4 * seed.y);
            float d = sdBox(localPos, size);
            
            // Accumulate mask
            float edge = smoothstep(0.05, -0.05, d);
            mask = max(mask, edge);
        }
    }
    return mask;
}

// --- Main Function ---
// Generates a cartoon tree with a dynamic trunk and 3 stacked foliage blocks
void CartoonTree_float(
    float2 UV,
    float4 TrunkColor,
    float4 BotRect,      // x:Width, y:Height, z:Roundness, w:CenterXOffset
    float4 BotColor,
    float4 MidRect,      // x:Width, y:Height, z:Roundness, w:CenterXOffset
    float4 MidColor,
    float4 TopRect,      // x:Width, y:Height, z:Roundness, w:CenterXOffset
    float4 TopColor,
    float4 Spacings,     // x:GapBotMid, y:GapMidTop, z:BaseY, w:TrunkWidth
    float4 Visibilities, // x:Bot(0/1), y:Mid(0/1), z:Top(0/1), w:LeafDensity
    float2 LeafShape,    // x:Width, y:Height (relative to cell size)
    float4 LeafColor,
    out float4 outColor
) {
    // PLAN:
    // 1. Unpack parameters and calculate geometry (Y positions of blocks).
    // 2. Determine Trunk Height (max Y of visible blocks).
    // 3. Compute SDFs for Trunk and 3 Foliage Blocks.
    // 4. Compute Leaf Pattern Mask.
    // 5. Composite layers: Trunk (bottom) -> Bot -> Mid -> Top (painter's algo).

    float2 p = UV;
    
    // --- 1. Geometry Calculations ---
    float baseY = Spacings.z;
    float trunkWidth = Spacings.w;
    
    // Dimensions (Half-sizes for SDF)
    float2 botSize = BotRect.xy * 0.5;
    float2 midSize = MidRect.xy * 0.5;
    float2 topSize = TopRect.xy * 0.5;
    
    // Center Y positions (Stacking logic)
    // Bottom block sits on BaseY
    float cyBot = baseY + botSize.y;
    // Mid block sits on Bottom block top + Gap1
    float cyMid = (baseY + BotRect.y) + Spacings.x + midSize.y;
    // Top block sits on Mid block top + Gap2
    float cyTop = (baseY + BotRect.y + Spacings.x + MidRect.y) + Spacings.y + topSize.y;

    // Center X positions (0.5 + Offset)
    float cxBot = 0.5 + BotRect.w;
    float cxMid = 0.5 + MidRect.w;
    float cxTop = 0.5 + TopRect.w;

    // Visibility Flags (Binary 0 or 1)
    float visBot = step(0.5, Visibilities.x);
    float visMid = step(0.5, Visibilities.y);
    float visTop = step(0.5, Visibilities.z);

    // --- 2. Trunk Logic ---
    // Calculate the top Y coordinate of the highest visible block
    float trunkTopY = baseY;
    if (visBot > 0.5) trunkTopY = max(trunkTopY, cyBot + botSize.y);
    if (visMid > 0.5) trunkTopY = max(trunkTopY, cyMid + midSize.y);
    if (visTop > 0.5) trunkTopY = max(trunkTopY, cyTop + topSize.y);
    
    // Trunk Geometry
    // Center Y is halfway between base and calculated top
    float trunkHeight = trunkTopY - baseY;
    float2 trunkCenter = float2(0.5, baseY + trunkHeight * 0.5);
    float2 trunkHalfSize = float2(trunkWidth * 0.5, trunkHeight * 0.5);

    // --- 3. SDF Calculations ---
    float aa = fwidth(p.y);
    
    // Trunk SDF
    float dTrunk = sdBox(p - trunkCenter, trunkHalfSize);
    float alphaTrunk = smoothstep(aa, -aa, dTrunk);
    
    // Foliage SDFs
    float dBot = sdRoundedBox(p - float2(cxBot, cyBot), botSize, BotRect.z);
    float alphaBot = smoothstep(aa, -aa, dBot) * visBot;
    
    float dMid = sdRoundedBox(p - float2(cxMid, cyMid), midSize, MidRect.z);
    float alphaMid = smoothstep(aa, -aa, dMid) * visMid;
    
    float dTop = sdRoundedBox(p - float2(cxTop, cyTop), topSize, TopRect.z);
    float alphaTop = smoothstep(aa, -aa, dTop) * visTop;

    // --- 4. Leaf Details ---
    // Compute leaf mask pattern based on world UV
    float leafMask = GetLeafMask(UV, Visibilities.w, LeafShape);
    
    // --- 5. Composition ---
    // Start with transparent background
    float4 col = float4(0.0, 0.0, 0.0, 0.0);
    
    // Layer 1: Trunk
    // Premultiplied alpha blending
    float3 trunkRGB = TrunkColor.rgb * alphaTrunk;
    col = float4(trunkRGB, alphaTrunk);
    
    // Helper for Over Operator: src over dst
    // color = src.rgb + dst.rgb * (1 - src.a)
    // alpha = src.a + dst.a * (1 - src.a)
    
    // Layer 2: Bottom Block
    // Apply leaf pattern color to the block surface
    float3 colBotFill = lerp(BotColor.rgb, LeafColor.rgb, leafMask);
    float4 srcBot = float4(colBotFill * alphaBot, alphaBot);
    col.rgb = srcBot.rgb + col.rgb * (1.0 - srcBot.a);
    col.a = srcBot.a + col.a * (1.0 - srcBot.a);
    
    // Layer 3: Middle Block
    float3 colMidFill = lerp(MidColor.rgb, LeafColor.rgb, leafMask);
    float4 srcMid = float4(colMidFill * alphaMid, alphaMid);
    col.rgb = srcMid.rgb + col.rgb * (1.0 - srcMid.a);
    col.a = srcMid.a + col.a * (1.0 - srcMid.a);
    
    // Layer 4: Top Block
    float3 colTopFill = lerp(TopColor.rgb, LeafColor.rgb, leafMask);
    float4 srcTop = float4(colTopFill * alphaTop, alphaTop);
    col.rgb = srcTop.rgb + col.rgb * (1.0 - srcTop.a);
    col.a = srcTop.a + col.a * (1.0 - srcTop.a);
    
    outColor = col;
}