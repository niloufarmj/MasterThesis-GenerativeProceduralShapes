#ifndef PI
#define PI 3.14159265359
#endif

// SDF for a box with rounded corners (centered at origin)
// p: sampling point
// b: half-extents (width/2, height/2)
// r: corner radius
float sdRoundedBox(float2 p, float2 b, float r) {
    float2 q = abs(p) - b + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

// Alpha compositing: Source Over Destination
float4 over(float4 src, float4 dst) {
    float a = src.a + dst.a * (1.0 - src.a);
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-8);
    return float4(c, a);
}

void LetterOShape_float(float2 UV, float2 Center, float2 Size, float RingThickness, float CornerRadius, float Angle, float4 FillColor, float4 OutlineColor, float OutlineWidth, out float4 outColor) {
    // PLAN:
    // 1) Center UVs and handle rotation.
    // 2) Define the "spine" of the letter O using a Rounded Box SDF.
    // 3) Create the ring shape by subtracting thickness from the spine (annulus).
    // 4) Compute Fill and Outline masks.
    // 5) Composite Outline over Fill.

    // 1) Center and Rotate
    float2 p = UV - Center;
    float c = cos(Angle);
    float s = sin(Angle);
    p = float2(c * p.x + s * p.y, -s * p.x + c * p.y);

    // 2) Parameters Setup
    // Size represents total width/height. Half-size for SDF.
    float2 halfSize = max(Size, 0.0) * 0.5;
    
    // Clamp corner radius to valid range (cannot exceed half shortest side)
    float r = clamp(CornerRadius, 0.0, min(halfSize.x, halfSize.y));

    // 3) SDF Calculation
    // Base shape (spine of the ring)
    // We subtract r from halfSize inside the SDF logic, but sdRoundedBox expects 'b' as the full box bound if r=0.
    // The logic inside sdRoundedBox is `abs(p) - b + r`. 
    // To keep visual size consistent, we use halfSize as is.
    float d_spine = sdRoundedBox(p, halfSize, r);

    // Turn solid shape into a ring (annulus)
    // abs(d_spine) gives distance from the edge. 
    // Subtracting half thickness gives the ring SDF.
    float halfRing = max(RingThickness, 0.0) * 0.5;
    float d_shape = abs(d_spine) - halfRing;

    // 4) Anti-aliasing and Masks
    float aa = fwidth(d_shape);
    
    // Fill Mask (d_shape < 0 is inside)
    float fillAlpha = 1.0 - smoothstep(0.0, aa, d_shape);
    float4 fill = float4(FillColor.rgb, FillColor.a * fillAlpha);

    // Outline Mask
    // The outline sits on the boundary of the ring (d_shape = 0)
    float halfOutline = max(OutlineWidth, 0.0) * 0.5;
    float d_outline = abs(d_shape) - halfOutline;
    float outlineAlpha = 1.0 - smoothstep(0.0, aa, d_outline);
    float4 stroke = float4(OutlineColor.rgb, OutlineColor.a * outlineAlpha);

    // 5) Composition (Stroke over Fill)
    outColor = over(stroke, fill);
}