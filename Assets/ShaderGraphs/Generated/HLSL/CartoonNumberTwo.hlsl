#ifndef PI
#define PI 3.14159265359
#endif

// --- Helper Functions ---

// Polynomial Smooth Minimum (for blending shapes seamlessly)
float smin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / max(k, 1e-5), 0.0, 1.0);
    return lerp(b, a, h) - k * h * (1.0 - h);
}

// Signed Distance to a Line Segment
float sdSegment(float2 p, float2 a, float2 b) {
    float2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}

// Distance to a Circle Arc (Skeleton)
// Defined by center c, radius r, and angle range [aMin, aMax] in radians.
// Assumes the range does not cross the +/- PI discontinuity.
float sdArcSkeleton(float2 p, float2 c, float r, float aMin, float aMax) {
    float2 d = p - c;
    float theta = atan2(d.y, d.x);
    // Clamp angle to the arc's extent
    float closestAngle = clamp(theta, aMin, aMax);
    float2 closestPoint = c + float2(cos(closestAngle), sin(closestAngle)) * r;
    return length(p - closestPoint);
}

// Blending Helper: Source Over Destination
float4 blendOver(float4 src, float4 dst) {
    float a = src.a + dst.a * (1.0 - src.a);
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-8);
    return float4(c, a);
}

// --- Main Function ---
// Generates a Cartoon Number 2 shape with adjustable skeleton, thickness, and rounded joints.
void CartoonNumberTwo_float(float2 UV, float Size, float Width, float Height, float Thickness, float CornerRadius, float4 Color, float4 OutlineColor, float OutlineWidth, out float4 outColor) {
    // PLAN:
    // 1) Center and scale UVs.
    // 2) Define 3 skeleton parts: Top Arc, Diagonal Body, Base Line.
    // 3) Calculate distances to each skeleton part.
    // 4) Combine distances using Smooth Minimum (smin) to fuse joints seamlessly.
    // 5) Subtract Thickness to create the volume.
    // 6) Render Shape and Outline with Anti-Aliasing.

    // 1) Center and Scale
    float2 p = (UV - 0.5) * (2.0 / max(Size, 1e-4));

    // 2) Skeleton Definitions
    // Radius of the top loop is half the width
    float R = Width * 0.5;
    
    // Top Arc Center: Positioned so the top of the '2' touches Height/2
    // y_top + R = Height/2  =>  y_top = Height/2 - R
    float topY = Height * 0.5 - R;
    float2 arcCenter = float2(0.0, topY);
    
    // Angles for the arc (Radians)
    // Start: ~160 degrees (Top Left curl) -> 2.8 rad
    // End: ~-35 degrees (Bottom Right connection) -> -0.6 rad
    float arcStartAng = 2.8;
    float arcEndAng = -0.6;
    
    // Calculate the end point of the arc to connect the diagonal
    float2 arcEndPoint = arcCenter + float2(cos(arcEndAng), sin(arcEndAng)) * R;
    
    // Base Line: Horizontal line at the bottom
    float2 baseStart = float2(-Width * 0.5, -Height * 0.5);
    float2 baseEnd = float2(Width * 0.5, -Height * 0.5);

    // 3) Calculate Distances (Skeleton)
    // Distance to the curved top
    float dArc = sdArcSkeleton(p, arcCenter, R, arcEndAng, arcStartAng);
    
    // Distance to the diagonal connecting arc end to base start
    float dDiag = sdSegment(p, arcEndPoint, baseStart);
    
    // Distance to the flat base
    float dBase = sdSegment(p, baseStart, baseEnd);

    // 4) Combine Primitives (Seamless Fusion)
    // Use smin to smooth the sharp V-joint between Diagonal and Base,
    // and the joint between Arc and Diagonal.
    float k = max(CornerRadius, 1e-4);
    float dSkeleton = smin(dArc, dDiag, k);
    dSkeleton = smin(dSkeleton, dBase, k);

    // 5) Create Volume
    // Subtract thickness/2 to expand the skeleton line into a shape
    float dShape = dSkeleton - Thickness * 0.5;

    // 6) Rendering / Outline / AA
    float aa = fwidth(dShape);
    
    // Fill Layer
    float fillAlpha = 1.0 - smoothstep(-aa, aa, dShape);
    float4 fillLayer = float4(Color.rgb, Color.a * fillAlpha);

    // Outline Layer
    // Outline is a band centered on the shape edge (dShape = 0)
    // Half-width of the outline band
    float halfOutline = OutlineWidth * 0.5;
    // Signed distance to the outline's outer and inner edges
    float dOutline = abs(dShape) - halfOutline;
    float outlineAlpha = 1.0 - smoothstep(-aa, aa, dOutline);
    float4 outlineLayer = float4(OutlineColor.rgb, OutlineColor.a * outlineAlpha);

    // Composite: Stroke OVER Fill
    outColor = blendOver(outlineLayer, fillLayer);
    // Ensure output is premultiplied or handled correctly by shader graph blending
    // Here we output straight alpha colors suitable for Unlit/Transparent nodes.
}