#ifndef PI
#define PI 3.14159265359
#endif

// Smooth Minimum for organic blending (metaballs effect)
// k = blend smoothness (0.0 = hard edge, 1.0 = blob)
float cloud_smin(float a, float b, float k)
{
    float h = clamp(0.5 + 0.5 * (b - a) / max(k, 0.0001), 0.0, 1.0);
    return lerp(b, a, h) - k * h * (1.0 - h);
}

// Alpha compositing helper (Source Over Destination)
float4 cloud_over(float4 src, float4 dst)
{
    float a = src.a + dst.a * (1.0 - src.a);
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-8);
    return float4(c, a);
}

void CloudCartoon_float(float2 UV, float Scale, float PuffCount, float PuffRadius, float PuffBlend, float4 FillColor, float4 StrokeColor, float StrokeWidth, out float4 outColor)
{
    // PLAN:
    // 1) Center and scale UV coordinates to create a local space.
    // 2) Loop to create N circles (puffs) arranged in a cluster.
    //    - Use a golden-angle spiral to pack them organically.
    //    - Squash the Y-axis position to make the cloud wider/flatter.
    // 3) Combine circle SDFs using a smooth minimum function (smin).
    // 4) Compute Fill and Stroke masks using the final SDF.
    // 5) Composite Stroke over Fill for the final cartoon look.

    // 1) Coordinates
    float2 p = (UV - 0.5) * 2.0;
    p /= max(Scale, 0.001); // Handle scale, prevent div/0

    // 2) SDF Accumulation
    float d = 1e5; // Initialize with a large distance
    
    int count = clamp((int)PuffCount, 1, 20); // Limit loop for safety
    float phi = 2.39996; // Golden angle (approx) for efficient packing
    
    for(int i = 0; i < 20; i++)
    {
        if(i >= count) break;
        
        // Spiral positioning: r = c * sqrt(n), theta = n * 137.5 deg
        float r_pos = 0.3 * sqrt((float)i); 
        float theta = (float)i * phi;
        
        float2 offset = float2(cos(theta), sin(theta)) * r_pos;
        
        // Make the cloud flatter (wider) by squashing Y offsets
        offset.y *= 0.65;
        
        // Calculate simple circle SDF
        // Vary radius slightly based on index to avoid perfect uniformity
        float r_var = PuffRadius * (1.0 - 0.1 * sin((float)i * 13.0));
        float d_puff = length(p - offset) - r_var;
        
        // 3) Smooth Blend
        if(i == 0) d = d_puff;
        else d = cloud_smin(d, d_puff, PuffBlend);
    }

    // 4) Rendering (AA and Stroke)
    float aa = fwidth(d);
    
    // Fill: Inside the shape (d < 0)
    float fillMask = 1.0 - smoothstep(0.0, aa, d);
    float4 fillLayer = float4(FillColor.rgb, saturate(FillColor.a) * fillMask);

    // Stroke: Band around the edge
    // Stroke is centered on the boundary d=0. Total width = StrokeWidth.
    float halfStroke = max(StrokeWidth, 0.0) * 0.5;
    float strokeDist = abs(d) - halfStroke;
    float strokeMask = 1.0 - smoothstep(0.0, aa, strokeDist);
    float4 strokeLayer = float4(StrokeColor.rgb, saturate(StrokeColor.a) * strokeMask);

    // 5) Composite
    outColor = cloud_over(strokeLayer, fillLayer);
}

// ------------------------------------------------------------------------
//  Visual Result (High-level, parameter-invariant description)
// ------------------------------------------------------------------------
//  This function generates a **stylized 2D cloud-like primitive** using
//  Signed Distance Functions (SDFs).
//
//  The shape is formed by smoothly blending multiple rounded elements into
//  a single soft silhouette, producing an organic, cloud-inspired form.
//  The exact structure, smoothness, proportions, and visual styling are
//  controlled by input parameters and are not fixed by the function itself.
//
//  The output is an anti-aliased RGBA color suitable for icons,
//  decorative graphics, and expressive procedural 2D visuals.
// ------------------------------------------------------------------------
