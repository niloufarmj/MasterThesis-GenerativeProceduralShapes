// Helper: SDF for an axis-aligned box
float sdBox(float2 p, float2 b)
{
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

void Rectangle_float(float2 UV, float Width, float Height, float2 Center, float4 Color, out float4 outColor)
{
    // Translate UV to center
    float2 p = UV - Center;

    // Calculate half-dimensions (extents)
    float2 halfExtents = float2(max(Width, 0.0), max(Height, 0.0)) * 0.5;

    // Compute Signed Distance Field (SDF)
    // Negative values are inside the rectangle, positive outside
    float dist = sdBox(p, halfExtents);

    // Anti-aliasing using fwidth to approximate 1 pixel in SDF space
    float aa = fwidth(dist);
    aa = max(aa, 0.0001); // Fallback to prevent smoothstep division by zero
    
    // Create smooth transition from 0 to 1 at the edge
    float alpha = smoothstep(aa, -aa, dist);

    // Output final color with alpha
    outColor = float4(Color.rgb, Color.a * alpha);
}
