/* 
  Cartoon Ribbon Bow
  - A central round knot
  - Two symmetric side loops (rounded)
  - Two ribbon tails extending downward
  - Flat 2D style with adjustable stroke and layering
*/

#ifndef PI
#define PI 3.14159265359
#endif

// --- Helper Functions ---

// 2D Rotation
float2 r_rotate(float2 p, float angle) {
    float c = cos(angle);
    float s = sin(angle);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

// SDF: Box
float r_sdBox(float2 p, float2 b) {
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// SDF: Rounded Box
float r_sdRoundBox(float2 p, float2 b, float r) {
    return r_sdBox(p, b - r) - r;
}

// SDF: Circle
float r_sdCircle(float2 p, float r) {
    return length(p) - r;
}

// Alpha Blending: src over dst
float4 r_over(float4 src, float4 dst) {
    float outA = src.a + dst.a * (1.0 - src.a);
    float3 outRGB = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(outA, 0.0001);
    return float4(outRGB, outA);
}

// Layer Composition Helper
// Composites a shape (fill + stroke) over the existing background buffer
float4 r_composeLayer(float4 bg, float dist, float4 fillColor, float4 strokeColor, float strokeWidth) {
    // Anti-aliasing width
    float aa = fwidth(dist);
    aa = max(aa, 0.001); // Safety clamp

    // Stroke Mask (band around edge)
    float halfStroke = strokeWidth * 0.5;
    float strokeDist = abs(dist) - halfStroke;
    float strokeAlpha = 1.0 - smoothstep(-aa, aa, strokeDist);
    
    // Fill Mask (inside edge)
    float fillAlpha = 1.0 - smoothstep(-aa, aa, dist);
    
    // Create Layers
    // Stroke Layer
    float4 sLayer = float4(strokeColor.rgb, strokeColor.a * strokeAlpha);
    
    // Fill Layer (masked by stroke to avoid double-blending if transparent, though over() handles alpha)
    // A simple painter's model: Fill is below Stroke.
    float4 fLayer = float4(fillColor.rgb, fillColor.a * fillAlpha);
    
    // Composite Stroke OVER Fill
    float4 shapeColor = r_over(sLayer, fLayer);
    
    // Composite Shape OVER Background
    return r_over(shapeColor, bg);
}

// --- Main Function ---
void CartoonRibbonBow_float(
    float2 UV,
    float2 Center,
    float Size,
    float KnotRadius,
    float2 LoopSize,
    float LoopAngle,
    float2 TailSize,
    float TailSpread,
    float StrokeThickness,
    float4 KnotColor,
    float4 RibbonColor,
    float4 StrokeColor,
    out float4 outColor)
{
    // PLAN:
    // 1. Normalize UVs centered at 'Center' and scaled by 'Size'.
    // 2. Compute SDF for Tails (Bottom layer).
    // 3. Compute SDF for Loops (Middle layer).
    // 4. Compute SDF for Knot (Top layer).
    // 5. Composite layers sequentially using painter's algorithm.
    
    // 1. Coordinate Setup
    float2 p = (UV - Center);
    // Avoid divide by zero
    float scale = max(Size, 0.0001);
    p /= scale;
    
    // Adjust Stroke Thickness to be relative to scale (so it doesn't get huge when zooming out)
    // However, usually stroke is defined in UV space. Let's keep it relative to shape.
    // Since p is scaled, the distance field is in "Size" units. We need to scale stroke too?
    // No, if d is in scaled space, stroke width should be in scaled space.
    // Let's assume StrokeThickness is in UV units. So we scale it up by 1/Size.
    float localStroke = StrokeThickness / scale;

    // Initialize Output
    float4 accumColor = float4(0.0, 0.0, 0.0, 0.0);
    
    // --- Layer 1: Tails (Bottom) ---
    {
        float2 pT = p;
        // Move start point down slightly so it emerges from behind the knot
        pT.y -= -KnotRadius * 0.5;
        
        // Symmetry: Mirror X
        pT.x = abs(pT.x);
        
        // Rotate "outwards" by TailSpread
        // Since we are in +x (mirrored), rotating negative moves it right/down
        pT = r_rotate(pT, -TailSpread);
        
        // Shift so the top of the tail box is at the pivot
        // Box center is at (0, -TailSize.y)
        float2 offsetT = float2(0.0, -TailSize.y);
        
        float dTail = r_sdBox(pT - offsetT, TailSize);
        
        accumColor = r_composeLayer(accumColor, dTail, RibbonColor, StrokeColor, localStroke);
    }
    
    // --- Layer 2: Loops (Middle) ---
    {
        float2 pL = p;
        
        // Symmetry
        pL.x = abs(pL.x);
        
        // Shift start point to the side of the knot
        pL.x -= KnotRadius * 0.8;
        
        // Rotate "upwards" by LoopAngle
        pL = r_rotate(pL, LoopAngle);
        
        // Define Loop Shape
        // We use a Rounded Box (Pill shape) for the loop
        // Center it such that it attaches at the pivot
        float2 offsetL = float2(LoopSize.x, 0.0);
        
        // Rounding radius: fully rounded ends (capsule-like)
        float rounding = min(LoopSize.x, LoopSize.y);
        
        float dLoop = r_sdRoundBox(pL - offsetL, LoopSize, rounding);
        
        accumColor = r_composeLayer(accumColor, dLoop, RibbonColor, StrokeColor, localStroke);
    }
    
    // --- Layer 3: Knot (Top) ---
    {
        float dKnot = r_sdCircle(p, KnotRadius);
        accumColor = r_composeLayer(accumColor, dKnot, KnotColor, StrokeColor, localStroke);
    }
    
    // Output final color
    outColor = accumColor;
}

// ------------------------------------------------------------------------
//  Visual Result
// ------------------------------------------------------------------------
//  This function generates a **stylized cartoon ribbon bow** using 
//  Signed Distance Functions (SDFs).
//
//  The visual result is composed of three layered sections:
//  - Two angular **tails** extending downwards from the center, forming the 
//    base layer.
//  - Two rounded **loops** extending outwards and slightly upwards, creating
//    the main body of the bow.
//  - A central circular **knot** that sits on top of all other layers, 
//    hiding the junction points.
//
//  The shape features adjustable parameters for the size and angle of the 
//  loops, the length and spread of the tails, and the radius of the knot.
//  The knot and the ribbon body can be colored independently.
//
//  The output renders with a thick, cohesive outline around each individual 
//  part, creating a segmented "sticker" look suitable for gift wrap icons,
//  character accessories, or UI decorations.
// ------------------------------------------------------------------------