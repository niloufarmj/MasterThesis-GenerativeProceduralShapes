#ifndef PI
#define PI 3.14159265359
#endif

// --- Helpers ---

// Rotate vector p by angle (radians)
// Rotates the coordinate system, effectively rotating the shape by 'angle'
float2 rotate(float2 p, float angle) {
    float c = cos(angle);
    float s = sin(angle);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

// Signed distance to a rounded box
// b: half-extents (width/2, height/2)
// r: corner radius
float sdRoundBox(float2 p, float2 b, float r) {
    float2 q = abs(p) - (b - r);
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

// Approximate signed distance to an ellipse
// r: half-axes (width/2, height/2)
// Returns negative inside, positive outside
float sdEllipseApprox(float2 p, float2 r) {
    float a = max(r.x, 1e-6);
    float b = max(r.y, 1e-6);
    float x = abs(p.x);
    float y = abs(p.y);
    
    // Implicit equation F(x,y) = x^2/a^2 + y^2/b^2 - 1
    float F = (x * x) / (a * a) + (y * y) / (b * b) - 1.0;
    
    // Gradient length |grad F| = 2 * sqrt( x^2/a^4 + y^2/b^4 )
    float grad = 2.0 * sqrt( (x * x) / (a * a * a * a) + (y * y) / (b * b * b * b) );
    
    // Distance approx = F / |grad F|
    return F / max(grad, 1e-6);
}

// Alpha blending helper (Src Over Dst)
float4 composite(float4 src, float4 dst) {
    float a = src.a + dst.a * (1.0 - src.a);
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-6);
    return float4(c, a);
}

// --- Main Function ---
// Description: A capital letter Q consisting of an elliptical ring and a diagonal tail.
void LetterQShape_float(
    float2 UV,
    float2 EllipseSize,     // Width, Height of the ring
    float RingThickness,    // Width of the ring band
    float2 TailSize,        // Length (x), Thickness (y) of the tail
    float2 TailOffset,      // Position relative to center
    float TailAngle,        // Rotation in radians
    float CornerRadius,     // Rounding for the tail corners
    float2 Center,
    float4 FillColor,
    float4 OutlineColor,
    float OutlineWidth,
    out float4 outColor
) {
    // PLAN:
    // 1) Center UV coordinates.
    // 2) Compute Ellipse SDF and convert to Ring SDF (abs(d) - thick/2).
    // 3) Compute Tail SDF using a rotated rounded box at TailOffset.
    // 4) Union the Ring and Tail (min(dRing, dTail)).
    // 5) Apply Fill and Outline logic with analytic AA.

    // 1) Center and coordinates
    float2 p = UV - Center;
    
    // 2) Ring SDF
    // The ring is the boundary of the ellipse with thickness
    // We use an approximate ellipse SDF which is sufficient for rendering
    float2 halfSize = EllipseSize * 0.5;
    float dEllipse = sdEllipseApprox(p, halfSize);
    
    // Create ring: absolute distance to ellipse edge minus half thickness
    // dRing < 0 inside the solid band
    float dRing = abs(dEllipse) - RingThickness * 0.5;
    
    // 3) Tail SDF
    // Tail is a rotated rounded box positioned at TailOffset
    float2 pTail = p - TailOffset;
    // Rotate coordinate system by -Angle to rotate shape by +Angle
    pTail = rotate(pTail, -TailAngle);
    
    // Clamp corner radius to half the smallest tail dimension to avoid artifacts
    float maxR = min(TailSize.x, TailSize.y) * 0.5;
    float r = clamp(CornerRadius, 0.0, maxR);
    
    // Calculate rounded box SDF for the tail
    float dTail = sdRoundBox(pTail, TailSize * 0.5, r);
    
    // 4) Combine shapes (Union)
    // We merge the ring and tail into a single shape
    float dShape = min(dRing, dTail);
    
    // 5) Rendering with Analytic Anti-Aliasing
    float aa = fwidth(dShape);
    
    // Fill Layer
    // Shape is defined where dShape < 0. We use smoothstep for soft edges.
    float fillMask = 1.0 - smoothstep(-aa, aa, dShape);
    float4 fillLayer = float4(FillColor.rgb, FillColor.a * fillMask);
    
    // Outline Layer
    // Outline is a uniform band centered on the shape's boundary (d=0)
    // The outline spans from -halfOutline to +halfOutline relative to dShape
    float halfOutline = OutlineWidth * 0.5;
    float dOutline = abs(dShape) - halfOutline;
    float outlineMask = 1.0 - smoothstep(-aa, aa, dOutline);
    float4 outlineLayer = float4(OutlineColor.rgb, OutlineColor.a * outlineMask);
    
    // Composite Outline OVER Fill
    outColor = composite(outlineLayer, fillLayer);
}