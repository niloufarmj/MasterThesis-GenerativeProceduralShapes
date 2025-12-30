#ifndef PI
#define PI 3.14159265359
#endif

// --- Helper Functions ---

// Calculate vector perpendicular to the right
inline float2 nm_perpRight(float2 e) {
    return float2(e.y, -e.x);
}

// Distance from point p to segment v0-v1
inline float nm_distPointToSegment(float2 p, float2 v0, float2 v1) {
    float2 e = v1 - v0;
    float ee = max(dot(e, e), 1e-12);
    float t = clamp(dot(p - v0, e) / ee, 0.0, 1.0);
    float2 q = v0 + t * e;
    return length(p - q);
}

// Signed Distance Function for an Isosceles Trapezoid centered at (0,0)
// widthBottom: width at y = -height/2
// widthTop: width at y = +height/2
// height: total vertical height
inline float nm_sdTrapezoid(float2 p, float widthBottom, float widthTop, float height) {
    float a = 0.5 * widthTop;
    float b = 0.5 * widthBottom;
    float h = 0.5 * height;

    // Vertices (CCW): Bottom-Left, Bottom-Right, Top-Right, Top-Left
    float2 v0 = float2(-b, -h);
    float2 v1 = float2(b, -h);
    float2 v2 = float2(a, h);
    float2 v3 = float2(-a, h);

    // Edges (outward normals)
    float2 e0 = v1 - v0; float2 n0 = normalize(nm_perpRight(e0));
    float2 e1 = v2 - v1; float2 n1 = normalize(nm_perpRight(e1));
    float2 e2 = v3 - v2; float2 n2 = normalize(nm_perpRight(e2));
    float2 e3 = v0 - v3; float2 n3 = normalize(nm_perpRight(e3));

    // Signed distance to infinite lines
    float d0 = dot(p - v0, n0);
    float d1 = dot(p - v1, n1);
    float d2 = dot(p - v2, n2);
    float d3 = dot(p - v3, n3);

    // Combine half-spaces (inside if all negative)
    float sgn = (max(max(d0, d1), max(d2, d3)) <= 0.0) ? -1.0 : 1.0;

    // Combine segment distances for boundary
    float dist = min(
        min(nm_distPointToSegment(p, v0, v1), nm_distPointToSegment(p, v1, v2)),
        min(nm_distPointToSegment(p, v2, v3), nm_distPointToSegment(p, v3, v0))
    );

    return dist * sgn;
}

// Blend 'src' color over 'dst' color (Standard alpha blending for straight alpha)
inline float4 over(float4 src, float4 dst) {
    float a = src.a + dst.a * (1.0 - src.a);
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-8);
    return float4(c, a);
}

// --- Main Function ---
// Renders a cartoon ice cream cone with 3 scoops based on user request.
void IceCreamCone_float(
    float2 UV,
    float2 Center,
    float2 ConeSize,        // x = Width (Top), y = Height
    float ConeTipWidth,     // Width of the bottom tip (0 for sharp)
    float4 ConeColor,
    float ScoopRadius,      // Shared radius for all scoops
    float ScoopSpacingRatio,// Spacing factor (e.g. 1.2 * Radius)
    float4 Scoop1Color,     // Bottom Scoop Color
    float4 Scoop2Color,     // Middle Scoop Color
    float4 Scoop3Color,     // Top Scoop Color
    out float4 outColor)
{
    // PLAN:
    // 1. Define geometry positions relative to 'Center'.
    // 2. Compute Cone SDF (Trapezoid pointing down from Center).
    // 3. Compute 3 Scoop SDFs (Circles stacked up from Center).
    // 4. Compute masks with anti-aliasing.
    // 5. Composite layers: Background -> Cone -> Scoop1 -> Scoop2 -> Scoop3.

    // 1. Cone Geometry
    // The trapezoid function is centered at (0,0). Its top is at local y = +Height/2.
    // We want the Top to align with 'Center'. So we offset the sampling point.
    // Shift P downwards by Height/2 so that Center maps to the top of the shape.
    float2 coneCenterPos = Center - float2(0.0, ConeSize.y * 0.5);
    float2 pCone = UV - coneCenterPos;
    float dCone = nm_sdTrapezoid(pCone, ConeTipWidth, ConeSize.x, ConeSize.y);
    
    float aa = max(fwidth(dCone), 0.001);
    float maskCone = 1.0 - smoothstep(0.0, aa, dCone);
    float4 layerCone = float4(ConeColor.rgb, ConeColor.a * maskCone);

    // Start composition with Cone
    float4 result = layerCone;

    // 2. Scoop 1 (Bottom) - Sitting at Center
    float2 pScoop1 = UV - Center;
    float dScoop1 = length(pScoop1) - ScoopRadius;
    float aa1 = max(fwidth(dScoop1), 0.001);
    float maskS1 = 1.0 - smoothstep(0.0, aa1, dScoop1);
    float4 layerS1 = float4(Scoop1Color.rgb, Scoop1Color.a * maskS1);
    
    result = over(layerS1, result);

    // 3. Scoop 2 (Middle) - Stacked upwards
    float spacing = ScoopRadius * max(ScoopSpacingRatio, 0.1);
    float2 pScoop2 = UV - (Center + float2(0.0, spacing));
    float dScoop2 = length(pScoop2) - ScoopRadius;
    float aa2 = max(fwidth(dScoop2), 0.001);
    float maskS2 = 1.0 - smoothstep(0.0, aa2, dScoop2);
    float4 layerS2 = float4(Scoop2Color.rgb, Scoop2Color.a * maskS2);
    
    result = over(layerS2, result);

    // 4. Scoop 3 (Top) - Stacked further up
    float2 pScoop3 = UV - (Center + float2(0.0, spacing * 2.0));
    float dScoop3 = length(pScoop3) - ScoopRadius;
    float aa3 = max(fwidth(dScoop3), 0.001);
    float maskS3 = 1.0 - smoothstep(0.0, aa3, dScoop3);
    float4 layerS3 = float4(Scoop3Color.rgb, Scoop3Color.a * maskS3);
    
    result = over(layerS3, result);

    // Final Output
    outColor = result;
}