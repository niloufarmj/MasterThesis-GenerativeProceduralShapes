/*
  User Request: Cartoon letter T shape with adjustable width of top crossbar, height of stem, and stroke thickness.
  Implementation: Uses Signed Distance Fields (SDF) for a vertical box (stem) and horizontal box (crossbar), combined with min() for union.
  Includes parameters for outline width and color for the cartoon style.
*/

// --- Helper Functions ---

// Box SDF: calculates distance to an axis-aligned box of size 'b' (half-extents)
#ifndef SDF_BOX
#define SDF_BOX
float sdBox_T(float2 p, float2 b) {
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}
#endif

// Alpha Blending Helper: Puts 'src' over 'dst' (standard SrcOver)
#ifndef BLEND_OVER
#define BLEND_OVER
float4 blend_over_T(float4 src, float4 dst) {
    float a = src.a + dst.a * (1.0 - src.a);
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-8);
    return float4(c, a);
}
#endif

// --- Main Function ---

void LetterTShape_float(float2 UV, float CrossbarWidth, float StemHeight, float BarThickness, float2 Center, float Angle, float4 Color, float4 OutlineColor, float OutlineWidth, out float4 outColor) {
    // PLAN:
    // 1) Center the UV coordinates based on the input Center.
    // 2) Rotate the coordinates by Angle.
    // 3) Calculate dimensions and positions for Crossbar and Stem to center the T shape.
    // 4) Compute SDF for the Crossbar (horizontal box).
    // 5) Compute SDF for the Stem (vertical box).
    // 6) Combine SDFs using min() (Union).
    // 7) Apply anti-aliasing and outline using smoothstep and fwidth.
    // 8) Output final composite color.

    // 1) Center UVs
    float2 p = UV - Center;

    // 2) Rotate space
    float c = cos(Angle);
    float s = sin(Angle);
    p = float2(c * p.x + s * p.y, -s * p.x + c * p.y);

    // 3) Dimensions & Offsets
    // Ensure valid positive dimensions
    float wTop = max(CrossbarWidth, 0.0);
    float hStem = max(StemHeight, 0.0);
    float tBar = max(BarThickness, 0.0);

    // Centering Logic:
    // The total height of the shape is (hStem + tBar).
    // We want the bounding box centered at (0,0).
    // Top Y boundary = (hStem + tBar) * 0.5
    // Bottom Y boundary = -(hStem + tBar) * 0.5
    
    // Crossbar Center Y = Top Boundary - (tBar / 2)
    // = (hStem * 0.5 + tBar * 0.5) - tBar * 0.5 = hStem * 0.5
    float crossbarCenterY = hStem * 0.5;
    
    // Stem Center Y = Bottom Boundary + (hStem / 2)
    // = -(hStem * 0.5 + tBar * 0.5) + hStem * 0.5 = -tBar * 0.5
    float stemCenterY = -tBar * 0.5;

    // 4) & 5) SDF Calculation
    // Crossbar: Width = wTop, Height = tBar
    float dCrossbar = sdBox_T(p - float2(0.0, crossbarCenterY), float2(wTop * 0.5, tBar * 0.5));
    
    // Stem: Width = tBar, Height = hStem
    float dStem = sdBox_T(p - float2(0.0, stemCenterY), float2(tBar * 0.5, hStem * 0.5));

    // 6) Union (min distance)
    float dist = min(dCrossbar, dStem);

    // 7) Rendering / Anti-aliasing
    float aa = fwidth(dist);
    
    // Fill Mask (inside the shape, dist < 0)
    float fillAlpha = 1.0 - smoothstep(-aa, aa, dist);
    float4 fillLayer = float4(Color.rgb, Color.a * fillAlpha);

    // Outline Mask (band around edge)
    float halfOutline = max(OutlineWidth, 0.0) * 0.5;
    float outlineDist = abs(dist) - halfOutline;
    float outlineAlpha = 1.0 - smoothstep(-aa, aa, outlineDist);
    float4 outlineLayer = float4(OutlineColor.rgb, OutlineColor.a * outlineAlpha);

    // 8) Composite: Stroke over Fill
    outColor = blend_over_T(outlineLayer, fillLayer);
}