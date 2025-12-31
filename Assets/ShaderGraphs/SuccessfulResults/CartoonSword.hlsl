// PLAN:
// 1. Define helpers (sdBox, sdCircle, sdTriangle, rotate, blend).
// 2. Center and rotate UV coordinates.
// 3. Compute SDFs for Blade, Handle, Pommel, and Guard.
// 4. Apply specific details (Ridge line, Grip texture).
// 5. Generate Fill and Stroke for each part.
// 6. Composite parts in depth order (Blade -> Pommel -> Handle -> Guard).

#ifndef PI
#define PI 3.14159265359
#endif

// --- Helpers ---
float sdBox_Sword(float2 p, float2 b) {
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

float sdCircle_Sword(float2 p, float r) {
    return length(p) - r;
}

float sdTriangle_Sword(float2 p, float2 p0, float2 p1, float2 p2) {
    float2 e0 = p1 - p0, e1 = p2 - p1, e2 = p0 - p2;
    float2 v0 = p - p0, v1 = p - p1, v2 = p - p2;
    float2 pq0 = v0 - e0 * clamp(dot(v0, e0) / dot(e0, e0), 0.0, 1.0);
    float2 pq1 = v1 - e1 * clamp(dot(v1, e1) / dot(e1, e1), 0.0, 1.0);
    float2 pq2 = v2 - e2 * clamp(dot(v2, e2) / dot(e2, e2), 0.0, 1.0);
    float s = sign(e0.x * e2.y - e0.y * e2.x);
    float2 d = min(min(float2(dot(pq0, pq0), s * (v0.x * e0.y - v0.y * e0.x)),
                       float2(dot(pq1, pq1), s * (v1.x * e1.y - v1.y * e1.x))), 
                       float2(dot(pq2, pq2), s * (v2.x * e2.y - v2.y * e2.x)));
    return -sqrt(d.x) * sign(d.y);
}

float2 rotate_Sword(float2 p, float angle) {
    float c = cos(angle);
    float s = sin(angle);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

// Alpha blending: source over destination
float4 blend_Sword(float4 src, float4 dst) {
    float outA = src.a + dst.a * (1.0 - src.a);
    float3 outRGB = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(outA, 1e-6);
    return float4(outRGB, outA);
}

// --- Main Function ---
// Generates a cartoon sword with adjustable components
void CartoonSword_float(float2 UV, float2 Center, float Rotation, 
                        float BladeLength, float BladeWidth, float4 BladeColor, float4 RidgeColor,
                        float GuardWidth, float GuardHeight, float GuardCurve, float4 GuardColor,
                        float HandleLength, float HandleThickness, float GripLines, float4 HandleColor,
                        float PommelSize, float4 PommelColor,
                        float StrokeWidth, float4 StrokeColor,
                        out float4 outColor) 
{
    // 1. Setup Coordinates
    float2 p = UV - Center;
    p = rotate_Sword(p, Rotation);
    float aa = fwidth(length(p)); // analytic antialiasing width
    if (aa == 0) aa = 0.001;

    // 2. Helper Vars for Composition
    float4 colBlade = float4(0,0,0,0);
    float4 colHandle = float4(0,0,0,0);
    float4 colPommel = float4(0,0,0,0);
    float4 colGuard = float4(0,0,0,0);
    float4 strokeCol = StrokeColor;
    float halfStroke = StrokeWidth * 0.5;

    // --- BLADE ---
    {
        // Blade Tip Height (proportional to width to keep it pointy)
        float tipH = BladeWidth * 2.0;
        float shaftLen = max(0.0, BladeLength - tipH);
        float halfW = BladeWidth * 0.5;

        // Shaft SDF (Box)
        // Box centered at y = shaftLen/2
        float2 pShaft = p - float2(0.0, shaftLen * 0.5);
        float dShaft = sdBox_Sword(pShaft, float2(halfW, shaftLen * 0.5));

        // Tip SDF (Triangle)
        // Vertices relative to origin: (-w/2, shaftLen), (w/2, shaftLen), (0, totalLen)
        float2 v0 = float2(-halfW, shaftLen);
        float2 v1 = float2(halfW, shaftLen);
        float2 v2 = float2(0.0, BladeLength);
        float dTip = sdTriangle_Sword(p, v0, v1, v2);

        // Union Shaft + Tip
        float dBlade = min(dShaft, dTip);

        // Ridge Pattern (Inside blade)
        float dRidge = abs(p.x) - halfW * 0.1;
        // Only show ridge if inside blade
        float ridgeMask = 1.0 - smoothstep(0.0, aa, dRidge);
        float4 fill = lerp(BladeColor, RidgeColor, ridgeMask * 0.5);

        // Blade Render
        float maskFill = 1.0 - smoothstep(0.0, aa, dBlade);
        float maskStroke = 1.0 - smoothstep(halfStroke, halfStroke + aa, abs(dBlade));
        
        float4 cFill = float4(fill.rgb, fill.a * maskFill);
        float4 cStroke = float4(strokeCol.rgb, strokeCol.a * maskStroke);
        colBlade = blend_Sword(cStroke, cFill);
    }

    // --- HANDLE ---
    {
        // Handle goes DOWN from 0 to -HandleLength
        float2 pH = p - float2(0.0, -HandleLength * 0.5);
        float dHandle = sdBox_Sword(pH, float2(HandleThickness * 0.5, HandleLength * 0.5));

        // Grip Texture (Stripes)
        float stripes = sin((p.y * 30.0) + (p.x * 10.0));
        float gripMask = step(0.0, stripes) * GripLines; // 0 or 1 based on param
        // subtle darken for grip
        float4 fill = lerp(HandleColor, HandleColor * 0.8, gripMask * 0.3);

        float maskFill = 1.0 - smoothstep(0.0, aa, dHandle);
        float maskStroke = 1.0 - smoothstep(halfStroke, halfStroke + aa, abs(dHandle));

        float4 cFill = float4(fill.rgb, fill.a * maskFill);
        float4 cStroke = float4(strokeCol.rgb, strokeCol.a * maskStroke);
        colHandle = blend_Sword(cStroke, cFill);
    }

    // --- POMMEL ---
    {
        // Pommel at bottom of handle
        float2 pPom = p - float2(0.0, -HandleLength);
        float dPommel = sdCircle_Sword(pPom, PommelSize);

        float maskFill = 1.0 - smoothstep(0.0, aa, dPommel);
        float maskStroke = 1.0 - smoothstep(halfStroke, halfStroke + aa, abs(dPommel));

        float4 cFill = float4(PommelColor.rgb, PommelColor.a * maskFill);
        float4 cStroke = float4(strokeCol.rgb, strokeCol.a * maskStroke);
        colPommel = blend_Sword(cStroke, cFill);
    }

    // --- GUARD ---
    {
        // Guard at y=0, bent by x^2
        float2 pG = p;
        // Apply curvature
        pG.y -= GuardCurve * (pG.x * pG.x) * 4.0;
        float dGuard = sdBox_Sword(pG, float2(GuardWidth * 0.5, GuardHeight * 0.5));
        
        // Slightly round the guard box
        dGuard -= GuardHeight * 0.2;

        float maskFill = 1.0 - smoothstep(0.0, aa, dGuard);
        float maskStroke = 1.0 - smoothstep(halfStroke, halfStroke + aa, abs(dGuard));

        float4 cFill = float4(GuardColor.rgb, GuardColor.a * maskFill);
        float4 cStroke = float4(strokeCol.rgb, strokeCol.a * maskStroke);
        colGuard = blend_Sword(cStroke, cFill);
    }

    // --- COMPOSITE (Depth Order) ---
    // Order: Blade (back) -> Pommel -> Handle -> Guard (front)
    float4 current = colBlade;
    current = blend_Sword(colPommel, current);
    current = blend_Sword(colHandle, current);
    current = blend_Sword(colGuard, current);

    outColor = current;
}