#ifndef PI
#define PI 3.14159265359
#endif

// Helper function for a beveled rectangle SDF
float sdBeveledRect(float2 p, float2 size, float bevel) {
    p = abs(p);
    float2 d = p - size * 0.5;
    float dBox = length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
    float validBevel = min(bevel, min(size.x, size.y) * 0.5);
    float dBevel = (p.x + p.y - (size.x * 0.5 + size.y * 0.5 - validBevel)) * 0.70710678;
    return max(dBox, dBevel);
}

// Helper for standard rectangle SDF
float sdRect(float2 p, float2 size) {
    float2 d = abs(p) - size * 0.5;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

void SDFColumn_float(
    float2 UV,
    float totalHeight,
    float totalWidth,
    float columnDepth,
    float bandCount,
    float bandHeight,
    float recessDepth,
    float grooveThickness,
    float featureDensity,
    float panelLineDepth,
    float cornerBevelSize,
    float surfaceGloss,
    float reflectionIntensity,
    float4 baseColor,
    float4 grooveColor,
    out float4 outColor
) {
    float2 p = UV - 0.5;
    float aa = max(fwidth(p.x), 0.001) * 1.5;

    float safeWidth = max(totalWidth, 0.001);
    float bCount = max(1.0, round(bandCount));

    // 1. Base / Background Groove Plane
    float base_width = safeWidth - 2.0 * recessDepth;
    float2 base_size = float2(base_width, totalHeight);
    float d_base = sdRect(p, base_size);

    // 2. Main Bands Stack
    float stack_height = bCount * bandHeight + max(0.0, bCount - 1.0) * grooveThickness;
    float pitch = bandHeight + grooveThickness;
    
    // Determine which band we are currently in or closest to
    float band_offset_y = p.y + stack_height * 0.5;
    float id_band = floor(band_offset_y / pitch);
    id_band = clamp(id_band, 0.0, max(0.0, bCount - 1.0));
    
    // Calculate local coordinates for the closest band
    float band_center_y = -stack_height * 0.5 + id_band * pitch + bandHeight * 0.5;
    float2 local_band_p = float2(p.x, p.y - band_center_y);
    float d_band = sdBeveledRect(local_band_p, float2(safeWidth, bandHeight), cornerBevelSize);

    // 3. Cap and Footer
    // If totalHeight > stack_height, we use the remaining space for top/bottom caps
    float cap_height = max(0.0, (totalHeight - stack_height) * 0.5);
    float cap_width = safeWidth + 0.04; // Caps are slightly wider than main face
    
    // Top cap SDF
    float cap_center_y = totalHeight * 0.5 - cap_height * 0.5;
    float2 local_cap_p = float2(p.x, p.y - cap_center_y);
    float d_cap = sdBeveledRect(local_cap_p, float2(cap_width, cap_height), cornerBevelSize);
    
    // Bottom footer SDF
    float footer_center_y = -totalHeight * 0.5 + cap_height * 0.5;
    float2 local_footer_p = float2(p.x, p.y - footer_center_y);
    float d_footer = sdBeveledRect(local_footer_p, float2(cap_width, cap_height), cornerBevelSize);

    float d_cap_footer = min(d_cap, d_footer);
    if (cap_height < 0.001) {
        d_cap_footer = 1e9; // Hide if no space allocated for caps
    }

    // Front structure consists of the bands and the caps
    float d_front = min(d_band, d_cap_footer);

    // 4. Shading & Colors
    // --- Background (Groove) Color ---
    float groove_shade = smoothstep(1.0, 0.0, abs(p.x) / (base_width * 0.5));
    float3 currentGrooveColor = grooveColor.rgb * (0.6 + 0.4 * groove_shade);

    // --- Front (Bands/Caps) Color ---
    float norm_x = p.x / (safeWidth * 0.5); // Ranges from -1 to 1 across the column face

    // Reflection Highlight & Shadow (simulated metallic/glass gradient)
    float exp_factor = lerp(2.0, 30.0, surfaceGloss);
    float hl = exp(-pow(norm_x + 0.3, 2.0) * exp_factor) * surfaceGloss;
    float sh = exp(-pow(norm_x - 0.4, 2.0) * exp_factor * 0.5) * surfaceGloss;

    float3 bColor = baseColor.rgb;
    bColor = lerp(bColor, float3(0.9, 0.95, 1.0), hl * reflectionIntensity * 0.8);
    bColor = lerp(bColor, grooveColor.rgb * 0.3, sh * reflectionIntensity * 0.8);

    // Side shading simulating 3D column depth rounding
    float sideShade = smoothstep(1.0 - columnDepth * 2.0, 1.0, abs(norm_x));
    bColor = lerp(bColor, grooveColor.rgb * 0.4, sideShade);

    // Top/Bottom bevel edge highlight for individual band segments
    float band_norm_y = local_band_p.y / max(bandHeight * 0.5, 0.001);
    float bevel_hl = smoothstep(0.7, 1.0, band_norm_y) * 0.2 * surfaceGloss;
    float bevel_sh = smoothstep(-0.7, -1.0, band_norm_y) * 0.3 * surfaceGloss;
    bColor += bevel_hl * reflectionIntensity;
    bColor -= bevel_sh * reflectionIntensity;

    // Vertical Panel Subdivisions
    float line_mask = 0.0;
    if (featureDensity > 0.5) {
        float fDensity = round(featureDensity);
        float panelWidth = safeWidth / (fDensity + 1.0);
        float x_offset = p.x + safeWidth * 0.5;
        float line_id = round(x_offset / panelWidth);
        if (line_id > 0.0 && line_id < fDensity + 1.0) {
            float dist_line = abs(x_offset - line_id * panelWidth);
            line_mask = 1.0 - smoothstep(0.0, aa * 2.0, dist_line - 0.002);
        }
    }
    bColor = lerp(bColor, grooveColor.rgb * 0.6, line_mask * panelLineDepth);

    // Structural Corner Rivets (only rendered on main bands, not caps)
    float is_band = 1.0 - smoothstep(-aa, aa, d_band);
    float rivet_margin_x = safeWidth * 0.5 - max(0.015, cornerBevelSize + 0.01);
    float rivet_margin_y = bandHeight * 0.5 - max(0.015, cornerBevelSize + 0.01);
    float2 p_rivet = float2(abs(p.x) - rivet_margin_x, abs(local_band_p.y) - rivet_margin_y);
    float rivet_dist = length(p_rivet) - 0.005;
    float rivet_mask = 1.0 - smoothstep(0.0, aa * 2.0, rivet_dist);
    bColor = lerp(bColor, grooveColor.rgb * 0.2, rivet_mask * is_band);

    bColor = saturate(bColor);

    // 5. Compositing using SDF Masks
    float base_mask = 1.0 - smoothstep(0.0, aa, d_base);
    float front_mask = 1.0 - smoothstep(0.0, aa, d_front);

    float total_mask = max(base_mask, front_mask);
    float3 color_mix = lerp(currentGrooveColor, bColor, front_mask);
    
    outColor = float4(color_mix, baseColor.a * total_mask);
}
