#ifndef PI
#define PI 3.14159265359
#endif

float nm_sdBox(float2 p, float2 b) {
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

float nm_sdTriangle(float2 p, float2 p0, float2 p1, float2 p2) {
    float2 e0 = p1 - p0;
    float2 e1 = p2 - p1;
    float2 e2 = p0 - p2;

    float2 v0 = p - p0;
    float2 v1 = p - p1;
    float2 v2 = p - p2;

    float2 pq0 = v0 - e0 * clamp(dot(v0, e0) / dot(e0, e0), 0.0, 1.0);
    float2 pq1 = v1 - e1 * clamp(dot(v1, e1) / dot(e1, e1), 0.0, 1.0);
    float2 pq2 = v2 - e2 * clamp(dot(v2, e2) / dot(e2, e2), 0.0, 1.0);

    float s = sign(e0.x * e2.y - e0.y * e2.x);
    
    float2 d = min(
        min(
            float2(dot(pq0, pq0), s * (v0.x * e0.y - v0.y * e0.x)),
            float2(dot(pq1, pq1), s * (v1.x * e1.y - v1.y * e1.x))
        ),
        float2(dot(pq2, pq2), s * (v2.x * e2.y - v2.y * e2.x))
    );

    return -sqrt(d.x) * sign(d.y);
}

float nm_smin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return lerp(b, a, h) - k * h * (1.0 - h);
}

void SimpleHouse_float(
    float2 UV,
    float HouseWidth,
    float BaseHeight,
    float RoofHeight,
    float RoofOverhang,
    float DoorWidth,
    float DoorHeight,
    float4 BaseColor,
    float4 RoofColor,
    float4 DoorColor,
    out float4 outColor
) {
    // Center UV coordinates
    float2 p = UV - 0.5;

    // Calculate vertical metrics to center the entire house at (0.5, 0.5)
    float totalHeight = BaseHeight + RoofHeight;
    float startY = -totalHeight * 0.5;
    float splitY = startY + BaseHeight;

    // 1. Base Box SDF
    float2 baseCenter = float2(0.0, startY + BaseHeight * 0.5);
    float dBase = nm_sdBox(p - baseCenter, float2(HouseWidth * 0.5, BaseHeight * 0.5));

    // 2. Roof Triangle SDF
    float2 v0 = float2(-HouseWidth * 0.5 - RoofOverhang, splitY);
    float2 v1 = float2(HouseWidth * 0.5 + RoofOverhang, splitY);
    float2 v2 = float2(0.0, splitY + RoofHeight);
    float dRoof = nm_sdTriangle(p, v0, v1, v2);

    // 3. Unified House Silhouette (smin prevents inner artifacts at the exact seam)
    float dHouse = nm_smin(dBase, dRoof, 0.01);

    // 4. Door Box SDF
    float2 doorCenter = float2(0.0, startY + DoorHeight * 0.5);
    float dDoor = nm_sdBox(p - doorCenter, float2(DoorWidth * 0.5, DoorHeight * 0.5));
    
    // Clip door strictly to the house silhouette to prevent bottom bleeding
    dDoor = max(dDoor, dHouse);

    // Standard screenspace anti-aliasing
    float aa = max(fwidth(p.x), 0.0001);

    // SDF Masks
    float mHouse = smoothstep(aa, -aa, dHouse);
    float mDoor = smoothstep(aa, -aa, dDoor);

    // -- Color Composition --
    float4 col;
    
    // Split color vertically between Base and Roof (creates perfect internal seam)
    float roofMix = smoothstep(splitY - aa, splitY + aa, p.y);
    col.rgb = lerp(BaseColor.rgb, RoofColor.rgb, roofMix);
    col.a = lerp(BaseColor.a, RoofColor.a, roofMix);

    // Composite Door over the house base color
    float doorAlpha = mDoor * DoorColor.a;
    col.rgb = lerp(col.rgb, DoorColor.rgb, doorAlpha);
    col.a = doorAlpha + col.a * (1.0 - doorAlpha);

    // Apply Unified House Silhouette Mask
    col.a *= mHouse;

    outColor = col;
}
