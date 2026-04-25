#ifndef PI
#define PI 3.14159265359
#endif

// a 5-pointed star with adjustable size, inner radius ratio, rotation, and color, centered

// Helper to calculate signed distance to a line segment.
// It's not a true SDF but gives the distance and a sign based on which side of the line p is on.
float sdLine(float2 p, float2 a, float2 b)
{
    float2 pa = p - a;
    float2 ba = b - a;
    // Project p onto the line, but clamp to the segment bounds
    float h = saturate(dot(pa, ba) / dot(ba, ba));
    float dist = length(pa - ba * h);

    // Get the sign to know if we are inside or outside using 2D cross product.
    // sign( (b.x-a.x)*(p.y-a.y) - (b.y-a.y)*(p.x-a.x) )
    float sgn = sign(ba.x * pa.y - ba.y * pa.x);

    return dist * sgn;
}

void Star5Point_float(float2 UV, float Size, float InnerRadiusRatio, float Rotation, float4 Color, out float4 outColor)
{
    // PLAN:
    // 1. Center UV coordinates and apply rotation.
    // 2. Define vertices for one 'point' of the star (an outer and an inner vertex).
    // 3. Use polar coordinates (atan2) and modulo (fmod) to fold the 2D space.
    //    This means we only need to calculate the distance for one segment, and it will be repeated 5 times.
    // 4. Calculate the signed distance from the folded coordinate to the star's edge line.
    // 5. Since the SDF should be negative inside, flip the sign of the distance.
    // 6. Apply anti-aliasing via smoothstep for a soft edge.

    // 1. Center UVs and apply rotation
    float2 p = UV - 0.5;
    float c = cos(-Rotation);
    float s = sin(-Rotation);
    p = float2(p.x * c - p.y * s, p.x * s + p.y * c);

    // 2. Define vertices for one point of the star
    float numPoints = 5.0;
    float anglePerSegment = PI / numPoints;
    float outerRadius = Size * 0.5;
    float innerRadius = outerRadius * saturate(InnerRadiusRatio);

    float2 v_outer = float2(outerRadius, 0);
    float2 v_inner = float2(innerRadius * cos(anglePerSegment), innerRadius * sin(anglePerSegment));

    // 3. Fold the space using polar coordinates
    float angle = atan2(p.y, p.x);
    float sectorAngle = 2.0 * anglePerSegment;
    angle = fmod(angle + sectorAngle, sectorAngle);

    // We are now in a V-shaped wedge. We mirror the angle around the center of the wedge.
    if (angle > anglePerSegment)
    {
        angle = sectorAngle - angle;
    }

    // Convert back to cartesian in the folded space
    float r = length(p);
    p = r * float2(cos(angle), sin(angle));

    // 4. Calculate signed distance to the edge line
    // The edge connects the inner vertex and the outer vertex.
    float dist = sdLine(p, v_inner, v_outer);

    // 5. The SDF should be negative inside the shape. Our cross-product sign convention makes it positive inside, so we flip it.
    dist = -dist;
    
    // 6. Anti-alias the edge
    // Use fwidth for screen-space anti-aliasing, which is more robust than a fixed value.
    float aa = fwidth(dist);
    float mask = smoothstep(aa, -aa, dist);

    // Output the final color
    outColor = float4(Color.rgb * mask, Color.a * mask);
}