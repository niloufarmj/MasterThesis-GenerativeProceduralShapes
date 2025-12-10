#ifndef PI
#define PI 3.14159265359
#endif

// Helper: Signed distance to a box
// p: sampling point, b: half-extents (width/2, height/2)
float sdBox_Plus(float2 p, float2 b) {
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

void PlusShape_float(float2 UV, float Size, float Thickness, float Rotation, float2 Center, float4 Color, out float4 outColor) {
    // PLAN:
    // 1) Recenter UV coordinates to the specified Center.
    // 2) Rotate the coordinate system by -Rotation (so shape rotates +Rotation).
    // 3) Define two box SDFs: one vertical, one horizontal.
    // 4) Combine them using min() to create the union (cross shape).
    // 5) Apply smoothstep for anti-aliasing and apply color.

    // 1) Center UV
    float2 p = UV - Center;

    // 2) Rotate sampling point by -Rotation
    float c = cos(Rotation);
    float s = sin(Rotation);
    float2 pr = float2(c * p.x + s * p.y, -s * p.x + c * p.y);

    // 3) Define Dimensions (Half-extents)
    // Vertical Bar: Width = Thickness, Height = Size
    // Horizontal Bar: Width = Size, Height = Thickness
    // We multiply by 0.5 because sdBox expects half-extents
    float2 boxV = float2(Thickness, Size) * 0.5;
    float2 boxH = float2(Size, Thickness) * 0.5;

    // 4) Calculate SDFs
    float dVert = sdBox_Plus(pr, boxV);
    float dHorz = sdBox_Plus(pr, boxH);
    
    // Union of the two bars
    float dist = min(dVert, dHorz);

    // 5) Anti-aliasing
    // smoothstep from positive (outside) to negative (inside) creates a soft edge
    float edge = smoothstep(0.01, -0.01, dist);

    // Output color with alpha mask
    outColor = float4(Color.rgb * edge, edge);
}