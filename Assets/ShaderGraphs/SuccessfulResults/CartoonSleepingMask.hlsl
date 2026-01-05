#ifndef PI
#define PI 3.14159265359
#endif

// --- Helper Functions ---

// Smooth Min (for union)
float smin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return lerp(b, a, h) - k * h * (1.0 - h);
}

// Smooth Max (for subtraction/intersection)
float smax(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (a - b) / k, 0.0, 1.0);
    return lerp(b, a, h) + k * h * (1.0 - h);
}

float sdCircle(float2 p, float r) {
    return length(p) - r;
}

float sdBox(float2 p, float2 b) {
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

float sdRoundBox(float2 p, float2 b, float r) {
    float2 q = abs(p) - b + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

float sdSegment(float2 p, float2 a, float2 b) {
    float2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}

// Quadratic Bezier SDF
float sdBezier(float2 pos, float2 A, float2 B, float2 C) {
    float2 a = B - A;
    float2 b = A - 2.0 * B + C;
    float2 c = a * 2.0;
    float2 d = A - pos;
    float kk = 1.0 / dot(b, b);
    float kx = kk * dot(a, b);
    float ky = kk * (2.0 * dot(a, a) + dot(d, b)) / 3.0;
    float kz = kk * dot(d, a);
    float res = 0.0;
    float p = ky - kx * kx;
    float p3 = p * p * p;
    float q = kx * (2.0 * kx * kx - 3.0 * ky) + kz;
    float h = q * q + 4.0 * p3;
    if (h >= 0.0) {
        h = sqrt(h);
        float2 x = (float2(h, -h) - q) / 2.0;
        float2 uv = sign(x) * pow(abs(x), 1.0 / 3.0);
        float t = clamp(uv.x + uv.y - kx, 0.0, 1.0);
        res = dot(d + (c + b * t) * t, d + (c + b * t) * t);
    } else {
        float z = sqrt(-p);
        float v = acos(q / (p * z * 2.0)) / 3.0;
        float m = cos(v);
        float n = sin(v) * 1.732050808;
        float3 t = clamp(float3(m + m, -n - m, n - m) * z - kx, 0.0, 1.0);
        res = min(dot(d + (c + b * t.x) * t.x, d + (c + b * t.x) * t.x),
                  dot(d + (c + b * t.y) * t.y, d + (c + b * t.y) * t.y));
        res = min(res, dot(d + (c + b * t.z) * t.z, d + (c + b * t.z) * t.z));
    }
    return sqrt(res);
}

// --- Main Function ---
// Draws a cartoon sleeping mask with adjustable body, notch, straps, eyes, lashes, and outline.
void CartoonSleepingMask_float(float2 UV, float Size, float2 BodySize, float NotchDepth, float StrapLength, float StrapThickness, float EyeSize, float EyeCurve, float LashCount, float LashLength, float OutlineWidth, float4 BodyColor, float4 LineColor, out float4 outColor) {
    // PLAN:
    // 1. Center and Scale UVs.
    // 2. Define Body SDF (Rounded Box).
    // 3. Define Nose Notch SDF (Circle).
    // 4. Subtract Notch from Body using Smooth Max.
    // 5. Define Straps SDF (Box) and Union with Body.
    // 6. Define Eyes SDF (Bezier) and Lashes (Segments).
    // 7. Render Fill, Outline, and Features.
    
    // 1. Coordinates
    float2 p = UV - 0.5;
    float scale = max(Size, 0.01);
    p /= scale;
    
    // 2. Body Shape
    // Ensure valid dimensions
    float2 b = max(BodySize * 0.5, 0.01);
    // Rounding radius - roughly half height for oblong
    float r = min(b.x, b.y) * 0.95;
    float dBody = sdRoundBox(p, b, r);
    
    // 3. Nose Notch
    // A circle positioned at the bottom center
    // Move circle up/down based on NotchDepth
    float notchRadius = b.x * 0.3;
    float2 notchPos = float2(0.0, -b.y - notchRadius + max(NotchDepth, 0.0) * 0.2);
    float dNotch = sdCircle(p - notchPos, notchRadius);
    
    // 4. Combine Body and Notch
    // Subtract notch from body: max(dBody, -dNotch)
    float dMaskShape = smax(dBody, -dNotch, 0.03);
    
    // 5. Straps
    // Horizontal segments from the sides
    float2 pMirrorX = float2(abs(p.x), p.y);
    // Strap position relative to body edge
    float2 strapBox = float2(StrapLength, StrapThickness * 0.5);
    float2 strapPos = float2(b.x + StrapLength * 0.5 - 0.02, 0.0);
    float dStrap = sdBox(pMirrorX - strapPos, strapBox);
    
    // Union Body and Straps
    float dSilhouette = smin(dMaskShape, dStrap, 0.02);
    
    // 6. Features (Eyes & Lashes)
    // Local coordinates for one eye
    float2 eyeCenter = float2(b.x * 0.45, 0.0);
    float2 pEye = pMirrorX - eyeCenter;
    
    // Eye Bezier (Sleeping Curve)
    float eW = EyeSize * 0.6;
    // A: Left, B: Bottom-Mid, C: Right
    // Curve controls depth of the 'U' or 'n' shape. Positive Curve = U shape (Happy/Deep sleep)
    float curveY = -EyeCurve * 0.1;
    float2 A = float2(-eW, 0.0);
    float2 B = float2(0.0, curveY);
    float2 C = float2(eW, 0.0);
    float dEyeLine = sdBezier(pEye, A, B, C);
    
    // Lashes
    float dLashes = 100.0;
    int count = clamp((int)LashCount, 0, 12);
    // Prevent division by zero
    float step = count > 1 ? 1.0 / float(count - 1) : 0.0;
    
    for (int i = 0; i < 12; i++) {
        if (i >= count) break;
        float t = float(i) * step;
        
        // Get point on curve
        float u = 1.0 - t;
        float2 pos = u * u * A + 2.0 * u * t * B + t * t * C;
        
        // Get tangent to calculate normal
        float2 tang = normalize(2.0 * u * (B - A) + 2.0 * t * (C - B));
        // Normal (rotate 90 deg). We want downward/outward lashes.
        // If curve is U shaped, normal should point down/out.
        float2 norm = float2(tang.y, -tang.x);
        // Flip if pointing wrong way (simple heuristic based on position)
        if (norm.y > 0.0) norm = -norm;
        
        float2 tip = pos + norm * LashLength * 0.5;
        dLashes = min(dLashes, sdSegment(pEye, pos, tip));
    }
    
    float dFeatures = min(dEyeLine, dLashes);
    
    // 7. Rendering
    // Anti-aliasing factor
    float aa = fwidth(dSilhouette);
    float w = max(OutlineWidth, 0.001);
    float fw = w * 0.6; // Feature line width
    
    // Masks
    // Fill: Inside the silhouette
    float fillMask = 1.0 - smoothstep(-aa, aa, dSilhouette);
    // Outline: Edge of the silhouette
    float outlineMask = 1.0 - smoothstep(w, w + aa, abs(dSilhouette));
    // Features: Lines for eyes/lashes
    float featureMask = 1.0 - smoothstep(fw, fw + aa, dFeatures);
    
    // Composition
    // Base color inside
    float3 colRGB = BodyColor.rgb;
    // Blend Outline
    // If outlineMask is high, show line color. Prioritize features over outline over body.
    float lineAmt = max(outlineMask, featureMask);
    colRGB = lerp(colRGB, LineColor.rgb, lineAmt);
    
    // Final Alpha
    // Visible if Body OR Outline OR Features
    float combinedAlpha = saturate(fillMask + outlineMask + featureMask);
    
    // Output premultiplied-compatible alpha
    outColor = float4(colRGB * combinedAlpha, combinedAlpha);
}

// ------------------------------------------------------------------------
//  Visual Result
// ------------------------------------------------------------------------
//  This function generates a **stylized sleeping mask** using 
//  Signed Distance Functions (SDFs).
//
//  The visual result is composed of:
//  - An oblong, pill-shaped main body that covers the eyes.
//  - A smooth circular **notch** cut into the bottom center for the nose.
//  - Two rectangular **straps** extending horizontally from the sides.
//  - A pair of closed, curved eyelids with adjustable **eyelashes**,
//    symbolizing sleep.
//
//  The shape features extensive parameter controls, including the mask's
//  aspect ratio, the depth of the nose notch, the length and thickness of
//  the straps, and the curvature and lash count of the closed eyes.
//
//  The output is a flat-shaded graphic with a consistent outline that applies
//  to both the mask silhouette and the facial features, suitable for 
//  avatar accessories, sleep-tracking UI, or cosmetic items.
// ------------------------------------------------------------------------