#ifndef PI
#define PI 3.14159265359
#endif
#ifndef TAU
#define TAU 6.28318530718
#endif

// PLAN:
// 1) Translate UV by Center and apply Rotation.
// 2) Use polar folding to map any point into a single star sector [0, TAU/Points].
// 3) Fold the sector in half so angle 0 is the valley and segment/2 is the peak.
// 4) Compute the Euclidean distance from the folded point to the sector's edge segment.
// 5) Determine inside/outside sign by comparing distance to origin with ray intersection.
// 6) Return signed distance, apply smoothstep for AA, and output color.

float sdStarPolar_internal(float2 p, float rOuter, float rInner, float numPoints) {
    // Angle from positive Y axis, going clockwise
    float angle = atan2(p.x, p.y);
    if (angle < 0.0) angle += TAU;

    float segment = TAU / max(numPoints, 2.0);
    float localAngle = ffmod(angle, segment);
    // Fold the angle so that 0 is the valley and segment/2 is the peak
    localAngle = abs(localAngle - segment * 0.5);

    float lengthP = length(p);
    float2 folded = lengthP * float2(sin(localAngle), cos(localAngle));

    // Define segment endpoints for the folded star sector
    float2 pPeak = float2(rOuter * sin(segment * 0.5), rOuter * cos(segment * 0.5));
    float2 pValley = float2(0.0, rInner);

    float2 edgeDir = pValley - pPeak;
    float2 pToPeak = folded - pPeak;

    // True Euclidean distance to the line segment
    float t = clamp(dot(pToPeak, edgeDir) / dot(edgeDir, edgeDir), 0.0, 1.0);
    float2 closestPoint = pPeak + t * edgeDir;
    float dist = length(folded - closestPoint);

    // Determine inside/outside sign using ray intersection with the infinite line
    float2 n = float2(-edgeDir.y, edgeDir.x);
    float2 dir = (lengthP > 1e-5) ? (folded / lengthP) : float2(0.0, 1.0);
    float denom = dot(dir, n);
    
    float signVal = 1.0;
    if (abs(denom) > 1e-5) {
        float lengthIntersect = dot(pPeak, n) / denom;
        // If the point is closer to the origin than the boundary line, it is inside
        if (lengthP < lengthIntersect) {
            signVal = -1.0;
        }
    } else {
        // Fallback case
        signVal = (lengthP < rInner) ? -1.0 : 1.0;
    }

    return dist * signVal;
}

void StarShape_float(float2 UV, float2 Center, float OuterRadius, float InnerRadius, float Points, float Rotation, float4 Color, out float4 outColor) {
    // User Request: a 5-pointed star filled by default in yellow color, centered, with a clear inner radius
    float2 centered = UV - Center;
    
    // Apply rotation
    float c = cos(Rotation);
    float s = sin(Rotation);
    float2 rotated = float2(c * centered.x + s * centered.y, -s * centered.x + c * centered.y);
    
    // Calculate Signed Distance Field
    float dist = sdStarPolar_internal(rotated, max(OuterRadius, 0.001), max(InnerRadius, 0.001), max(Points, 2.0));
    
    // Anti-aliased edge
    float aa = fwidth(dist);
    float mask = 1.0 - smoothstep(0.0, max(aa, 0.001), dist);
    
    // Output final color with straight alpha over background
    float alpha = mask * saturate(Color.a);
    outColor = float4(Color.rgb * alpha, alpha);
}