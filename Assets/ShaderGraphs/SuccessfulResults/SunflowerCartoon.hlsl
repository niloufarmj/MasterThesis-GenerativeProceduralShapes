/* 
  Cartoon Sunflower Generator
  A procedural sunflower with adjustable petals, stem, leaves, and outlines.
  Uses Signed Distance Fields (SDF) for clean, resolution-independent rendering.
*/

#ifndef PI
#define PI 3.14159265359
#endif

// --- Helper Functions ---

// Rotate a 2D vector by an angle (radians)
float2 Rotate(float2 p, float a) {
    float c = cos(a);
    float s = sin(a);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

// Box SDF
float sdBox(float2 p, float2 b) {
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// Circle SDF
float sdCircle(float2 p, float r) {
    return length(p) - r;
}

// Vesica SDF (Pointed Lens shape)
// r = radius of circles, d = shift from center
// Used for petals and leaves
float sdVesica(float2 p, float r, float d) {
    p = abs(p);
    float b = sqrt(r*r - d*d);
    return ((p.y - b) * d > p.x * b) ? length(p - float2(0.0, b))
                                     : length(p - float2(-d, 0.0)) - r;
}

// Alpha blending helper (Src Over Dst)
float4 blend(float4 src, float4 dst) {
    float outA = src.a + dst.a * (1.0 - src.a);
    float3 outRGB = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(outA, 1e-6);
    return float4(outRGB, outA);
}

// Render a single shape layer with Fill and Outline
float4 RenderLayer(float d, float4 fillColor, float4 outlineColor, float outlineWidth) {
    float aa = fwidth(d);
    
    // Outline mask (band around d=0)
    float halfW = 0.5 * outlineWidth;
    float edgeDist = abs(d) - halfW;
    float strokeMask = 1.0 - smoothstep(0.0, aa, edgeDist);
    
    // Fill mask (inside d=0)
    float fillMask = 1.0 - smoothstep(0.0, aa, d);
    
    float4 sColor = float4(outlineColor.rgb, outlineColor.a * strokeMask);
    float4 fColor = float4(fillColor.rgb, fillColor.a * fillMask);
    
    // Composite Stroke OVER Fill
    return blend(sColor, fColor);
}

// --- Main Function ---
void SunflowerCartoon_float(
    float2 UV,
    float Size,
    float CenterRadius,
    float4 CenterColor,
    float PetalCount,
    float2 PetalSize, // x: Length, y: Width
    float PetalOffset,
    float4 PetalColor,
    float StemWidth,
    float4 StemColor,
    float LeafSize,
    float LeafPos,
    float LeafAngle,
    float OutlineWidth,
    float4 OutlineColor,
    out float4 outColor)
{
    // 1) Center and Scale UVs
    // Use a large scaling factor logic so Size=1 fills screen comfortably
    float2 p = (UV - 0.5);
    p /= max(Size, 0.001);

    // --- SDF Calculations ---

    // 2) Stem SDF
    // Infinite vertical box starting near center and going down
    // Offset y so it connects behind the flower head
    float stemHeight = 2.0; // Arbitrary long length
    float2 pStem = p - float2(0.0, -stemHeight * 0.5 - 0.1);
    float dStem = sdBox(pStem, float2(StemWidth * 0.5, stemHeight * 0.5));

    // 3) Leaves SDF
    // Calculate parameters for Vesica based on Size input
    // Use LeafSize as length, and Width as a ratio (e.g. 40% of length)
    float lLen = LeafSize;
    float lWid = LeafSize * 0.4;
    // Map Width/Length to Radius/Offset for Vesica
    float l_d = (lLen*lLen - lWid*lWid) / (4.0 * max(lWid, 0.001));
    float l_r = l_d + lWid * 0.5;
    
    // Leaf 1 (Left)
    float2 pL1 = p - float2(0.0, LeafPos);
    pL1 = Rotate(pL1, -LeafAngle + PI/2.0); // +90 to orient horizontal
    float dLeaf1 = sdVesica(pL1 - float2(0.0, lLen*0.5), l_r, l_d);
    
    // Leaf 2 (Right)
    float2 pL2 = p - float2(0.0, LeafPos);
    pL2 = Rotate(pL2, LeafAngle - PI/2.0);
    float dLeaf2 = sdVesica(pL2 - float2(0.0, lLen*0.5), l_r, l_d);
    
    float dLeaves = min(dLeaf1, dLeaf2);
    float dStemGroup = min(dStem, dLeaves);

    // 4) Petals SDF (Radial Repetition)
    // Polar Coordinates
    float angle = atan2(p.y, p.x);
    float r = length(p);
    
    float count = max(3.0, PetalCount);
    float sectorSize = 2.0 * PI / count;
    
    // Repeat domain
    float sectorID = floor(angle / sectorSize + 0.5);
    float angleLocal = angle - sectorID * sectorSize;
    
    // Convert back to cartesian in the rotated sector
    float2 pPetal = float2(cos(angleLocal), sin(angleLocal)) * r;
    // Orient so petal points along X axis
    // Offset petal from center
    pPetal = pPetal - float2(PetalOffset, 0.0);
    
    // Petal Shape (Vesica)
    float pLen = PetalSize.x;
    float pWid = min(PetalSize.y, pLen - 0.01); // Width must be < Length
    float p_d = (pLen*pLen - pWid*pWid) / (4.0 * max(pWid, 0.001));
    float p_r = p_d + pWid * 0.5;
    
    // sdVesica is vertical (y-axis aligned), our pPetal is x-axis aligned
    // So we pass pPetal.yx
    float dPetals = sdVesica(pPetal.yx, p_r, p_d);

    // 5) Central Disk SDF
    float dDisk = sdCircle(p, CenterRadius);

    // --- Rendering (Painter's Algorithm) ---
    
    // Initialize color (Background)
    float4 col = float4(0, 0, 0, 0);
    
    // Layer 1: Stem & Leaves
    float4 layStem = RenderLayer(dStemGroup, StemColor, OutlineColor, OutlineWidth);
    col = blend(layStem, col); // Stem over Background
    
    // Layer 2: Petals
    float4 layPetal = RenderLayer(dPetals, PetalColor, OutlineColor, OutlineWidth);
    col = blend(layPetal, col); // Petals over Stem
    
    // Layer 3: Center Disk
    float4 layDisk = RenderLayer(dDisk, CenterColor, OutlineColor, OutlineWidth);
    col = blend(layDisk, col); // Disk over Petals

    // Final Output
    outColor = col;
}

// ------------------------------------------------------------------------
//  Visual Result (High-level, parameter-invariant description)
// ------------------------------------------------------------------------
//  This function generates a **stylized cartoon sunflower** using
//  Signed Distance Functions (SDFs).
//
//  The visual result is composed of:
//  - A large **central circular disk** representing the seed head.
//  - A radial array of **pointed (vesica-shaped) petals** surrounding the center.
//  - A vertical **stem** with two attached **leaves** extending from the bottom.
//
//  The geometry features adjustable **petal count/shape**, **leaf positioning**,
//  and **outline thickness**, rendered in layers (Center over Petals over Stem)
//  to create a clean, sticker-like aesthetic.
//
//  The output is an anti-aliased RGBA color suitable for farming games,
//  nature icons, and decorative floral assets.
// ------------------------------------------------------------------------