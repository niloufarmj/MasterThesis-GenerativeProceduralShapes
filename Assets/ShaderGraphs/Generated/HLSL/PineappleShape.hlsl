/* 
  Cartoon Pineapple Shape
  - Oval/Rounded body with adjustable curvature
  - Diagonal crisscross diamond grid pattern
  - Cluster of pointed leaves on top
  - Clean outlines and adjustable stroke
*/

#ifndef PI
#define PI 3.14159265359
#endif

// Rotate a 2D vector by an angle (radians)
float2 rotate2D(float2 p, float angle) {
    float c = cos(angle);
    float s = sin(angle);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

// Signed Distance to a Box with Rounded Corners
// p: point, b: half-extents, r: corner radius
float sdRoundBox(float2 p, float2 b, float r) {
    float2 q = abs(p) - b + r;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

// Signed Distance to a Vesica (Pointed Leaf Shape)
// r: radius of circles, d: distance from center to circle centers
float sdVesica(float2 p, float r, float d) {
    p = abs(p);
    float b = sqrt(r*r - d*d);
    return ((p.y - b) * d > p.x * b) ? length(p - float2(0.0, b)) : length(p - float2(-d, 0.0)) - r;
}

// Blend two Premultiplied Alpha colors (src over dst)
float4 blendPM(float4 src, float4 dst) {
    return src + dst * (1.0 - src.a);
}

void PineappleShape_float(
    float2 UV,
    float BodyWidth,
    float BodyHeight,
    float BodyCurvature,
    float GridDensity,
    float GridLineThickness,
    float LeavesCount,
    float LeafLength,
    float LeafSpread,
    float StrokeWidth,
    float4 BodyColor,
    float4 LeafColor,
    float4 GridColor,
    out float4 outColor
) {
    // Center UVs to (0,0) range [-0.5, 0.5]
    float2 p = UV - 0.5;
    // float aa = fwidth(length(p)); // این خط را غیرفعال کنید
    float aa = 0.001; // یک مقدار ثابت بسیار کوچک برای جلوگیری از تقسیم بر صفر
    
    // --- 1. BODY SDF ---
    // Use a Rounded Box to simulate the fruit body (Oval to Rectangle adjustable)
    float2 bodySize = float2(BodyWidth, BodyHeight) * 0.5;
    float maxRadius = min(bodySize.x, bodySize.y);
    float radius = maxRadius * clamp(BodyCurvature, 0.0, 1.0);
    
    // Offset body slightly down so leaves fit on top
    float2 bodyPos = p - float2(0.0, -0.05);
    float dBody = sdRoundBox(bodyPos, bodySize, radius);
    
    // --- 2. LEAVES SDF ---
    float dLeaves = 1e9;
    int leafCount = clamp((int)LeavesCount, 0, 12);
    
    // Attachment point at the top of the body
    float2 leafBase = float2(0.0, bodySize.y * 0.9 - 0.05);
    
    // Calculate Vesica parameters from Length
    // Width is proportional to length for a nice leaf shape
    float leafWidth = LeafLength * 0.35;
    // Math to derive circle radius (r) and offset (d) for a vesica of given length/width
    float rV = (LeafLength*LeafLength + leafWidth*leafWidth) / (2.0 * leafWidth);
    float dV = sqrt(max(0.0, rV*rV - (LeafLength * 0.5) * (LeafLength * 0.5)));
    
    // Distribute leaves
    float angleStep = (leafCount > 1) ? LeafSpread / float(leafCount - 1) : 0.0;
    float startAngle = -LeafSpread * 0.5;
    
    for (int i = 0; i < leafCount; i++) {
        float angle = startAngle + float(i) * angleStep;
        // Rotate point around the base
        float2 lp = rotate2D(p - leafBase, -angle);
        // Shift up so the leaf starts at the base
        lp.y -= LeafLength * 0.5;
        float dLeaf = sdVesica(lp, rV, dV);
        dLeaves = min(dLeaves, dLeaf);
    }
    
    // --- 3. PATTERN GENERATION (Grid) ---
    // Rotate UVs 45 degrees for diagonal grid
    float2 patUV = rotate2D(bodyPos, PI * 0.25) * GridDensity;
    // Calc distance to nearest grid line
    float2 gridDist2 = abs(frac(patUV) - 0.5);
    float distToLine = min(gridDist2.x, gridDist2.y);
    // Create grid mask (1.0 = line, 0.0 = cell)
    // Line thickness is relative to the scaled UV space
    float thick = GridLineThickness * GridDensity * 0.5;
    float gridMask = 1.0 - smoothstep(thick, thick + aa * GridDensity, distToLine);
    
    // --- 4. COMPOSITING LAYERS ---
    float4 colOutline = float4(0.0, 0.0, 0.0, 1.0);
    
    // -- Layer: Leaves --
    float leafMask = smoothstep(StrokeWidth + aa, StrokeWidth, dLeaves);
    float leafFillMask = smoothstep(0.0, -aa, dLeaves);
    
    float4 leafFill = LeafColor;
    float4 leafVisual = lerp(colOutline, leafFill, leafFillMask);
    // Convert to Premultiplied Alpha
    float4 pmLeaves = float4(leafVisual.rgb * leafMask, leafVisual.a * leafMask);
    
    // -- Layer: Body --
    float bodyMask = smoothstep(StrokeWidth + aa, StrokeWidth, dBody);
    float bodyFillMask = smoothstep(0.0, -aa, dBody);
    
    // Body fill color blends base color with grid color
    float4 bodyFillCol = lerp(BodyColor, GridColor, gridMask);
    float4 bodyVisual = lerp(colOutline, bodyFillCol, bodyFillMask);
    // Convert to Premultiplied Alpha
    float4 pmBody = float4(bodyVisual.rgb * bodyMask, bodyVisual.a * bodyMask);
    
    // Combine: Body OVER Leaves (standard for pineapple where tuft grows from top-center)
    // Wait, visually, the leaves often look like they are behind the rounded top edge.
    // Let's composite Body OVER Leaves to hide the leaf roots cleanly.
    outColor = blendPM(pmBody, pmLeaves);
}