#ifndef PI
#define PI 3.14159265359
#endif

// --- Helper Functions ---
float RCol_sdBox(float2 p, float2 b) {
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

float RCol_sdRoundBox(float2 p, float2 b, float r) {
    return RCol_sdBox(p, b - r) - r;
}

// --- Main Shape Function ---
void RectangularColumn_float(
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
    // 1. Coordinate Setup
    float2 p = UV - 0.5;
    
    // 2. Proportions and Layout Calculation
    float actualHeight = totalHeight;
    float safeBandCount = max(bandCount, 1.0);
    float bandInterval = actualHeight / safeBandCount;
    
    // Allow bandHeight to dynamically influence the actual visual groove if it shrinks the band
    float actualGroove = max(grooveThickness, bandInterval - bandHeight);

    // 3. Base Body Geometry
    float dBody = RCol_sdRoundBox(p, float2(totalWidth/2.0, actualHeight/2.0), cornerBevelSize);

    // 4. Horizontal Grooves Geometry Cutout
    float rY = p.y + actualHeight/2.0;
    float id = round(rY / bandInterval);
    // Clamp so grooves only appear *between* bands, not at the absolute top or bottom
    id = clamp(id, 1.0, max(safeBandCount - 1.0, 1.0)); 
    float localY = rY - id * bandInterval;

    // Box representing the side recesses to cut into the main body
    float dGrooveCut = RCol_sdBox(float2(abs(p.x) - totalWidth/2.0, localY), float2(recessDepth, actualGroove/2.0));
    float dBodyIndented = max(dBody, -dGrooveCut);

    // 5. Top Cap Geometry (Stacked rectangles)
    float cap1Height = totalWidth * 0.15;
    float cap1Width = totalWidth * 1.15;
    float cap2Height = totalWidth * 0.08;
    float cap2Width = totalWidth * 1.25;

    float dCap1 = RCol_sdRoundBox(p - float2(0.0, actualHeight/2.0 + cap1Height/2.0), float2(cap1Width/2.0, cap1Height/2.0), cornerBevelSize);
    float dCap2 = RCol_sdRoundBox(p - float2(0.0, actualHeight/2.0 + cap1Height + cap2Height/2.0), float2(cap2Width/2.0, cap2Height/2.0), cornerBevelSize);
    
    // Final Shape SDF
    float dShape = min(dBodyIndented, min(dCap1, dCap2));

    // 6. Anti-aliasing
    float aa = max(fwidth(dShape) * 1.5, 0.001);
    float alpha = 1.0 - smoothstep(-aa, aa, dShape);

    // --- Shading & Texturing ---
    
    // Simulated Cylindrical Normals (X-axis only for 2D faux 3D effect)
    float nx = clamp(p.x / (totalWidth / 2.0), -1.0, 1.0);
    
    float3 highlightColor = lerp(baseColor.rgb, float3(1.0, 1.0, 1.0), 0.7);
    float3 shadowColor = baseColor.rgb * 0.35;
    float3 col = baseColor.rgb;
    
    // A. Cylindrical Metallic Gradient Shading
    // Far left shadow edge
    col = lerp(col, shadowColor, smoothstep(-0.6, -1.0, nx));
    
    // Primary reflection highlight (left-center)
    float glossSpread = lerp(0.5, 0.05, surfaceGloss);
    float highlightMask = smoothstep(glossSpread, 0.0, abs(nx + 0.4));
    col = lerp(col, highlightColor, highlightMask * reflectionIntensity);
    
    // Right side core shadow
    col = lerp(col, shadowColor, smoothstep(0.0, 0.8, nx));
    
    // Deep edge shadow controlled by columnDepth to simulate thickness
    float depthRim = smoothstep(1.0 - max(columnDepth, 0.01), 1.0, nx);
    col = lerp(col, shadowColor * 0.6, depthRim);
    
    // Right edge rim light bounce
    col = lerp(col, baseColor.rgb, smoothstep(0.85, 1.0, nx) * 0.6);

    // B. Masking Areas
    float isBodyArea = step(p.y, actualHeight/2.0);
    
    // C. Horizontal Groove Shading
    float isGroove = (1.0 - smoothstep(actualGroove/2.0 - aa, actualGroove/2.0 + aa, abs(localY))) * isBodyArea;
    col = lerp(col, grooveColor.rgb, isGroove);

    // D. Vertical Panel Subdivisions
    if (featureDensity > 0.0) {
        float panelInterval = totalWidth / max(featureDensity, 1.0);
        float px = p.x + totalWidth/2.0;
        float panelId = round(px / panelInterval);
        panelId = clamp(panelId, 1.0, max(featureDensity - 1.0, 1.0));
        float dPanel = abs(px - panelId * panelInterval);
        float panelMask = (1.0 - smoothstep(0.0, 0.005, dPanel)) * isBodyArea * (1.0 - isGroove);
        col = lerp(col, shadowColor * 0.5, panelMask * panelLineDepth);
    }

    // E. Corner Rivets / Detail Dots (characteristic of modern metallic plates)
    float bandID = floor((p.y + actualHeight/2.0) / bandInterval);
    bandID = clamp(bandID, 0.0, max(safeBandCount - 1.0, 0.0));
    float bandCenterY = (bandID + 0.5) * bandInterval;
    float bandLocalY = (p.y + actualHeight/2.0) - bandCenterY;
    
    float rivetInset = 0.03;
    float rivetX = abs(p.x) - max((totalWidth/2.0 - rivetInset), 0.0);
    float rivetY = abs(bandLocalY) - max((bandInterval/2.0 - rivetInset), 0.0);
    float dRivet = length(float2(rivetX, rivetY)) - 0.008;
    float rivetMask = (1.0 - smoothstep(0.0, 0.005, dRivet)) * isBodyArea * (1.0 - isGroove);
    col = lerp(col, shadowColor * 0.4, rivetMask);

    // F. Top Cap Edge Highlights
    float inCap1 = 1.0 - smoothstep(0.0, 0.005, dCap1);
    float inCap2 = 1.0 - smoothstep(0.0, 0.005, dCap2);
    float inCap = max(inCap1, inCap2);
    
    // Bright horizontal lines at the bottom edges of the caps
    float capEdge1 = smoothstep(actualHeight/2.0, actualHeight/2.0 + 0.005, p.y) * (1.0 - smoothstep(actualHeight/2.0 + 0.005, actualHeight/2.0 + 0.01, p.y));
    float capEdge2 = smoothstep(actualHeight/2.0 + cap1Height, actualHeight/2.0 + cap1Height + 0.005, p.y) * (1.0 - smoothstep(actualHeight/2.0 + cap1Height + 0.005, actualHeight/2.0 + cap1Height + 0.01, p.y));
    col = lerp(col, highlightColor, max(capEdge1, capEdge2) * inCap * reflectionIntensity);

    // Final Output (Straight Alpha)
    outColor = float4(col, alpha);
}
