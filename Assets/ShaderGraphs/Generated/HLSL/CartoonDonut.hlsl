/* 
  Cartoon Donut Shader 
  - Procedural donut with adjustable dimensions
  - Wavy icing layer
  - Grid-based scattered sprinkles
  - Flat 2D cartoon style with outlines
*/

#ifndef PI
#define PI 3.14159265359
#endif

// --- Helper Functions ---

// Pseudo-random number generator
float2 hash22(float2 p) {
    float3 p3 = frac(float3(p.xyx) * float3(.1031, .1030, .0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return frac((p3.xx+p3.yz)*p3.zy);
}

// SDF for a capsule
float sdCapsule(float2 p, float2 a, float2 b, float r) {
    float2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h) - r;
}

// Helper to blend layers (Painter's Algorithm)
void layer(inout float4 baseCol, float4 newCol, float mask) {
    baseCol = lerp(baseCol, newCol, mask * newCol.a);
}

// --- Main Function ---
void CartoonDonut_float(
    float2 UV,
    float OuterRadius,
    float InnerRadius,
    float4 DoughColor,
    float4 IcingColor,
    float IcingWaviness,
    float SprinkleDensity,
    float SprinkleSize,
    float4 SprinkleColor1,
    float4 SprinkleColor2,
    float StrokeThickness,
    float4 StrokeColor,
    out float4 outColor)
{
    // PLAN:
    // 1) Center UVs and calculate donut body SDF (Annulus).
    // 2) Calculate wavy icing SDF sitting on top of the donut.
    // 3) Use a grid system to scatter capsule sprinkles, checking if they land on icing.
    // 4) Composite layers: Dough -> Outline -> Icing -> Outline -> Sprinkles -> Outline.
    
    // 1. Setup Coordinates
    float2 p = UV - 0.5;
    float len = length(p);
    float angle = atan2(p.y, p.x);
    float aa = fwidth(len); // Anti-aliasing width
    if(aa == 0) aa = 0.001;

    // 2. Donut Body SDF
    // Safe radius calculations
    float r_outer = max(OuterRadius, InnerRadius);
    float r_inner = min(OuterRadius, InnerRadius);
    float r_mid = (r_outer + r_inner) * 0.5;
    float half_width = (r_outer - r_inner) * 0.5;
    
    // Distance to donut edge
    float d_dough = abs(len - r_mid) - half_width;

    // 3. Icing SDF
    // Icing covers ~85% of the donut width, with wavy edges
    // Waviness varies the thickness of the icing band
    float waveFreq = 12.0;
    float wave = sin(angle * waveFreq) * IcingWaviness;
    // Icing radius threshold (wavy)
    float d_icing = abs(len - r_mid) - (half_width * 0.85 + wave);

    // 4. Sprinkles (Grid Scattering)
    float d_sprinkles = 1e5;
    float4 sprinkleFill = float4(0,0,0,0);

    float gridScale = max(1.0, SprinkleDensity);
    float2 gridUV = p * gridScale;
    float2 cellID = floor(gridUV);
    
    // Check 3x3 neighbor cells to handle boundary overlaps
    [unroll]
    for(int y = -1; y <= 1; y++) {
        [unroll]
        for(int x = -1; x <= 1; x++) {
            float2 neighbor = float2(x, y);
            float2 id = cellID + neighbor;
            
            // Random seed for this sprinkle
            float2 rnd = hash22(id * 12.34);
            
            // Random position in cell
            float2 center = id + 0.5 + (rnd - 0.5) * 0.7;
            float2 pos = center / gridScale;
            
            // IMPORTANT: Only draw sprinkle if its center is ON the icing
            // Re-evaluate icing SDF at sprinkle position
            float len_s = length(pos);
            float angle_s = atan2(pos.y, pos.x);
            float wave_s = sin(angle_s * waveFreq) * IcingWaviness;
            float dist_icing_at_pos = abs(len_s - r_mid) - (half_width * 0.85 + wave_s);
            
            // Margin ensures sprinkles don't hang halfway off the icing too much
            if(dist_icing_at_pos < -0.02) {
                // Capsule shape
                float rot = hash22(id * 7.77).x * PI * 2.0;
                float2 capDir = float2(sin(rot), cos(rot));
                
                // Dimensions
                float capLen = SprinkleSize * 2.0;
                float capRad = SprinkleSize * 0.5;
                
                // Local SDF
                float2 p_local = p - pos;
                float d_local = sdCapsule(p_local, -capDir*capLen*0.5, capDir*capLen*0.5, capRad);
                
                if(d_local < d_sprinkles) {
                    d_sprinkles = d_local;
                    // Random color selection
                    float colMix = hash22(id * 51.2).y;
                    sprinkleFill = (colMix > 0.5) ? SprinkleColor1 : SprinkleColor2;
                }
            }
        }
    }

    // 5. Compositing (Painter's Algorithm)
    // Initialize with transparent
    float4 col = float4(0,0,0,0);
    
    // --- Layer 1: Dough ---
    // Fill
    float maskDough = 1.0 - smoothstep(-aa, aa, d_dough);
    layer(col, DoughColor, maskDough);
    // Outline
    float maskDoughStroke = 1.0 - smoothstep(-aa, aa, abs(d_dough) - StrokeThickness);
    layer(col, StrokeColor, maskDoughStroke);

    // --- Layer 2: Icing ---
    // Fill
    float maskIcing = 1.0 - smoothstep(-aa, aa, d_icing);
    layer(col, IcingColor, maskIcing);
    // Outline
    float maskIcingStroke = 1.0 - smoothstep(-aa, aa, abs(d_icing) - StrokeThickness);
    layer(col, StrokeColor, maskIcingStroke);

    // --- Layer 3: Sprinkles ---
    // Optional thin outline for sprinkles (half thickness)
    float sprinkleStrokeThick = StrokeThickness * 0.5;
    float maskSprinkleStroke = 1.0 - smoothstep(-aa, aa, abs(d_sprinkles) - sprinkleStrokeThick);
    // Only show sprinkle stroke where icing exists (avoid artifacts) - optional logic
    // Actually sprinkles are already filtered by position, so just draw.
    
    // Fill
    float maskSprinkle = 1.0 - smoothstep(-aa, aa, d_sprinkles);
    
    // Composite Sprinkle Stroke then Fill
    layer(col, StrokeColor, maskSprinkleStroke);
    layer(col, sprinkleFill, maskSprinkle);

    outColor = col;
}