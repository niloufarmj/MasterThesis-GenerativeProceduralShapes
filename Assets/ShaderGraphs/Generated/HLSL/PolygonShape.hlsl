/*
  PLAN:
  1) Define PI and helper functions (sdSegment, over).
  2) Recenter UVs to (0,0) based on Center input.
  3) Rotate the point by the negative Angle parameter to apply rotation.
  4) Implement N-sided Polygon SDF:
     - Fold space into N angular sectors.
     - Compute distance to the edge segment within the canonical sector.
     - The sector logic creates the exact Euclidean distance field.
  5) Compute anti-aliasing factor using fwidth().
  6) Generate fill mask and stroke mask using smoothstep().
  7) Composite Stroke over Fill for final output.
*/

#ifndef PI
#define PI 3.14159265359
#endif

// --- Helper: Signed Distance to Line Segment ---
// Returns unsigned distance to segment ab.
float sdSegment_Poly(float2 p, float2 a, float2 b) {
    float2 pa = p - a;
    float2 ba = b - a;
    float h = saturate(dot(pa, ba) / dot(ba, ba));
    return length(pa - ba * h);
}

// --- Helper: Composite Source Over Destination ---
float4 over_Poly(float4 src, float4 dst) {
    float a = src.a + dst.a * (1.0 - src.a);
    float3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 1e-6);
    return float4(c, a);
}

void PolygonShape_float(float2 UV, float Sides, float Radius, float2 Center, float Rotation, float4 FillColor, float4 StrokeColor, float StrokeWidth, out float4 outColor) {
    // 1. Setup Coordinates
    float2 p = UV - Center;
    
    // 2. Adjust Rotation
    // Offset by -PI/2 so 0 rotation implies a "flat bottom" alignment (edge at -90 deg)
    float rads = Rotation - (PI * 0.5);
    float c = cos(rads);
    float s = sin(rads);
    p = float2(c * p.x + s * p.y, -s * p.x + c * p.y);

    // 3. Regular Polygon SDF
    // Clamp sides to >= 3
    float n = max(3.0, floor(Sides));
    
    // Angle per sector
    float an = 2.0 * PI / n;
    float he = an * 0.5; // Half-angle

    // Convert to polar angle
    float angle = atan2(p.y, p.x);
    
    // Fold space: Map current angle to the canonical sector [-he, he]
    // We add 0.5 to center indices correctly around the X-axis
    float sectorIdx = floor(angle / an + 0.5);
    float sectorAngle = sectorIdx * an;
    
    // Rotate p into the canonical sector (local space)
    // This effectively rotates the entire plane so the relevant edge is vertical-ish on the right
    float c2 = cos(sectorAngle);
    float s2 = sin(sectorAngle);
    float2 pLocal = float2(c2 * p.x + s2 * p.y, -s2 * p.x + c2 * p.y);

    // In the canonical sector (centered at angle 0), the edge is perpendicular to the X-axis?
    // No, we centered the sector at angle 0. The vertices are at angles +he and -he.
    // Radius 'r' is the circumradius (center to vertex).
    // Vertices of the edge segment in local space:
    float r = max(Radius, 0.0);
    float2 v1 = float2(r * cos(he), -r * sin(he));
    float2 v2 = float2(r * cos(he),  r * sin(he));

    // Signed Distance Calculation
    // Distance to the segment v1-v2
    float d = sdSegment_Poly(pLocal, v1, v2);
    
    // Sign determination: 
    // The edge lies on the line x = r * cos(he) (apothem).
    // Inside the polygon, x < apothem. Outside, x > apothem.
    // Note: This sign logic is valid because we are strictly inside the angular wedge of the sector.
    float apothem = r * cos(he);
    d *= sign(pLocal.x - apothem);

    // 4. Anti-Aliasing
    float aa = fwidth(d);
    
    // 5. Fill Logic (SDF < 0 is inside)
    float fillAlpha = 1.0 - smoothstep(0.0, aa, d);
    float4 fill = float4(FillColor.rgb, FillColor.a * fillAlpha);

    // 6. Stroke Logic (Band around SDF = 0)
    float halfStroke = max(StrokeWidth, 0.0) * 0.5;
    float strokeDist = abs(d) - halfStroke;
    float strokeAlpha = 1.0 - smoothstep(0.0, aa, strokeDist);
    float4 stroke = float4(StrokeColor.rgb, StrokeColor.a * strokeAlpha);

    // 7. Composite
    outColor = over_Poly(stroke, fill);
}