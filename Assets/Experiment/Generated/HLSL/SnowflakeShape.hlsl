/*
  PLAN:
  1. Center UVs and convert to polar coordinates.
  2. Fold space into N sectors (Branches) using angular repetition.
  3. Fold each sector for mirror symmetry (abs(y)) to create a 'pine tree' structure.
  4. Define the main trunk SDF (segment along X axis).
  5. Define side branch SDFs (segments angled off the trunk).
  6. Combine distances with min() and subtract thickness.
  7. Apply smoothstep for anti-aliasing and output color.
*/

// Helper: Signed Distance to a Line Segment
float sdSegment_Snowflake(float2 p, float2 a, float2 b)
{
    float2 pa = p - a;
    float2 ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}

void SnowflakeShape_float(float2 UV, float Branches, float Size, float Thickness, float4 Color, out float4 outColor)
{
    #ifndef PI
    #define PI 3.14159265359
    #endif

    // 1. Center coordinates
    float2 p = UV - 0.5;
    
    // 2. Polar coordinates for rotational symmetry
    float r = length(p);
    float ang = atan2(p.y, p.x);
    
    // Ensure at least 3 branches to maintain shape integrity
    float n = max(3.0, Branches);
    float sectorAngle = 2.0 * PI / n;
    
    // Wrap angle to [-sectorAngle/2, sectorAngle/2] to repeat the branch n times
    // frac((ang/sectorAngle) + 0.5) maps the angle to 0..1 range within the sector
    ang = (frac((ang / sectorAngle) + 0.5) - 0.5) * sectorAngle;
    
    // Convert back to Cartesian space for the single canonical branch
    // This aligns the branch along the positive X-axis
    p = float2(cos(ang), sin(ang)) * r;
    
    // 3. Mirror symmetry across the X-axis (creates the symmetric fern/tree look)
    p.y = abs(p.y);
    
    // 4. Construct the Snowflake Branch SDF
    // Main Trunk: Line from center (0,0) to tip (Size, 0)
    float d = sdSegment_Snowflake(p, float2(0.0, 0.0), float2(Size, 0.0));
    
    // Side Branches: Add pairs of sub-branches angled at 60 degrees
    float branchAngle = PI / 3.0; // 60 degrees standard for snowflakes
    float2 dir = float2(cos(branchAngle), sin(branchAngle));
    
    // Branch 1 (Inner)
    float pos1 = Size * 0.3;
    float len1 = Size * 0.3;
    d = min(d, sdSegment_Snowflake(p, float2(pos1, 0.0), float2(pos1, 0.0) + dir * len1));
    
    // Branch 2 (Middle)
    float pos2 = Size * 0.6;
    float len2 = Size * 0.25;
    d = min(d, sdSegment_Snowflake(p, float2(pos2, 0.0), float2(pos2, 0.0) + dir * len2));
    
    // Branch 3 (Outer)
    float pos3 = Size * 0.85;
    float len3 = Size * 0.15;
    d = min(d, sdSegment_Snowflake(p, float2(pos3, 0.0), float2(pos3, 0.0) + dir * len3));
    
    // 5. Apply thickness
    // Subtract half thickness because SDF is distance to center
    float dist = d - (Thickness * 0.5);
    
    // 6. Anti-aliasing and Output
    float edge = smoothstep(0.01, -0.01, dist);
    outColor = float4(Color.rgb * edge, edge);
}