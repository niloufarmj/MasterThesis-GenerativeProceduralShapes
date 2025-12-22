#ifndef PI
#define PI 3.14159265359
#endif

// Helper: Rotate a 2D vector by an angle
float2 sf_rotate(float2 p, float angle) {
    float c = cos(angle);
    float s = sin(angle);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

// Helper: Signed distance to a line segment
float sf_segment(float2 p, float2 a, float2 b) {
    float2 pa = p - a;
    float2 ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}

void SnowflakeShape_float(float2 UV, float Size, float NumArms, float Detail, float4 Color, out float4 outColor) {
    // PLAN:
    // 1. Center UV coordinates at (0.5, 0.5).
    // 2. Apply polar repetition to fold space into N symmetric sectors (wedge).
    // 3. Apply mirror symmetry within the wedge to simplify branch construction.
    // 4. Build a skeleton using line segments (SDF):
    //    - Main stem along the local X-axis.
    //    - Primary branches angled at 60 degrees.
    //    - Secondary lattice branches parallel to the stem (hexagonal grid look).
    // 5. Combine all segments using min() for union.
    // 6. Render the skeleton as thin, anti-aliased lines.

    // 1. Center UVs
    float2 p = UV - 0.5;

    // 2. Angular Symmetry (Polar Fold)
    // Ensure at least 2 arms
    float arms = max(2.0, floor(NumArms));
    float sectorAngle = 2.0 * PI / arms;

    // Convert to polar coordinates
    float angle = atan2(p.y, p.x);
    float r = length(p);

    // Snap to the nearest sector center and remap angle to [-sectorAngle/2, sectorAngle/2]
    float id = floor(angle / sectorAngle + 0.5);
    angle = angle - id * sectorAngle;

    // Convert back to Cartesian in the local rotated frame
    p = float2(cos(angle), sin(angle)) * r;

    // 3. Mirror Symmetry (handle top/bottom of the arm)
    p.y = abs(p.y);

    // 4. SDF Construction
    // Start with the main stem from center to tip
    float d = sf_segment(p, float2(0.0, 0.0), float2(Size, 0.0));

    // Branch generation
    // Map Detail (0-1) to number of branches and complexity
    float det = clamp(Detail, 0.0, 1.0);
    int branchCount = (int)lerp(3.0, 12.0, det);

    // Loop to add pairs of branches along the stem
    // We use a fixed upper bound for compilation safety
    for (int i = 1; i <= 12; i++) {
        if (i > branchCount) break;

        // Position along the stem (0.0 to 1.0)
        float t = (float)i / (float)(branchCount + 1);
        
        // Branch base position
        float2 base = float2(t * Size, 0.0);

        // Branch length tapers towards the tip of the flake
        float branchLen = Size * 0.5 * (1.0 - t);

        // Primary Branch: Angled at 60 degrees (PI/3)
        // This creates the classic snowflake 6-fold star look
        float2 dir = float2(cos(PI/3.0), sin(PI/3.0));
        float2 tip = base + dir * branchLen;
        
        d = min(d, sf_segment(p, base, tip));

        // Secondary Branches (Lattice Effect)
        // Adds small spurs to create the "intricate geometric lines" look
        if (det > 0.4) {
            // Position along the primary branch
            float t2 = 0.6;
            float2 subBase = lerp(base, tip, t2);
            
            // Sub-branch direction: Parallel to main stem (0 degrees)
            // This aligns with the hexagonal lattice structure
            float2 subDir = float2(1.0, 0.0);
            float subLen = branchLen * 0.4;
            float2 subTip = subBase + subDir * subLen;

            d = min(d, sf_segment(p, subBase, subTip));
        }
    }

    // 5. Rendering
    // Render as thin lines (skeleton) rather than a solid shape
    float thickness = max(0.002, Size * 0.015);
    
    // Compute anti-aliasing width using fwidth
    float aa = fwidth(d);
    aa = max(aa, 0.001); // Avoid division by zero or super sharp aliasing

    // Create alpha mask: 1.0 on the line, 0.0 outside
    float mask = 1.0 - smoothstep(thickness - aa, thickness + aa, d);

    // 6. Output Color
    // RGB masked by shape, Alpha channel contains the opacity
    outColor = float4(Color.rgb * mask, Color.a * mask);
}