#ifndef PI
#define PI 3.14159265359
#endif

void YinYangShape_float(float2 UV, float Size, float Rotation, float2 Center, float4 YinColor, float4 YangColor, float DotScale, out float4 outColor) {
    // PLAN:
    // 1) Center UVs and rotate the coordinate space.
    // 2) Define main circle SDF and sub-shape SDFs (top/bottom circles, dots).
    // 3) Create a base mask splitting the plane into Left (Yin) and Right (Yang).
    // 4) Modify the base mask using the sub-circle SDFs to form the swirl.
    // 5) Modify the mask again for the contrasting dots.
    // 6) Calculate anti-aliasing width.
    // 7) Mix colors based on the mask and apply the outer circle clip.

    // 1) Center and Rotate
    float2 p = UV - Center;
    
    // Rotate point by -Rotation to rotate shape by +Rotation
    // Standard 2D rotation matrix: [cos -sin; sin cos]
    // To rotate space opposite to shape: using angle directly often works intuitively in ShaderGraph
    // But strictly: Rot(p, -a) rotates shape by a.
    // Let's use x' = x*c + y*s; y' = -x*s + y*c; (Rotation by -angle)
    float c = cos(Rotation);
    float s = sin(Rotation);
    p = float2(p.x * c + p.y * s, -p.x * s + p.y * c);

    // 2) SDF Definitions
    // Ensure sizes are positive to avoid artifacts
    float rMain = max(Size, 0.0);
    float rSub = rMain * 0.5;
    float rDot = rMain * max(DotScale, 0.0);

    // Distances
    // Main outer circle
    float dOuter = length(p) - rMain;
    
    // Top circle (centered at 0, +rSub)
    float dTopCircle = length(p - float2(0.0, rSub)) - rSub;
    
    // Bottom circle (centered at 0, -rSub)
    float dBotCircle = length(p + float2(0.0, rSub)) - rSub;
    
    // Top dot (centered at 0, +rSub)
    float dTopDot = length(p - float2(0.0, rSub)) - rDot;
    
    // Bottom dot (centered at 0, -rSub)
    float dBotDot = length(p + float2(0.0, rSub)) - rDot;

    // 3) Anti-aliasing width
    // Use fwidth for screen-space AA, clamped to epsilon to prevent divide-by-zero
    float aa = max(fwidth(dOuter), 1e-4);

    // 4) Base Logic (Yin vs Yang)
    // We want a value 't' where 0 = Yin (Left/Black), 1 = Yang (Right/White)
    
    // Initial split: Right side (x > 0) is Yang (1), Left is Yin (0)
    // smoothstep creates a smooth transition across x=0
    float t = smoothstep(-aa, aa, p.x);

    // 5) Form the Swirl
    // The Top Circle is Yin (0). It encroaches onto the Right side.
    // Mask for inside Top Circle: 1 if inside, 0 if outside
    float maskTop = smoothstep(aa, -aa, dTopCircle);
    // Where Top Circle exists, force t towards 0 (Yin)
    t = lerp(t, 0.0, maskTop);

    // The Bottom Circle is Yang (1). It encroaches onto the Left side.
    float maskBot = smoothstep(aa, -aa, dBotCircle);
    // Where Bottom Circle exists, force t towards 1 (Yang)
    t = lerp(t, 1.0, maskBot);

    // 6) Add the Dots
    // Top Dot is Yang (1) inside the Yin Top Circle
    float maskTopDot = smoothstep(aa, -aa, dTopDot);
    t = lerp(t, 1.0, maskTopDot);

    // Bottom Dot is Yin (0) inside the Yang Bottom Circle
    float maskBotDot = smoothstep(aa, -aa, dBotDot);
    t = lerp(t, 0.0, maskBotDot);

    // 7) Final Composition
    // Calculate alpha for the whole shape (outer circle clipping)
    float outerAlpha = smoothstep(aa, -aa, dOuter);
    
    // Mix the colors based on t
    // Note: t is [0..1], 0=YinColor, 1=YangColor
    float4 finalColor = lerp(YinColor, YangColor, t);
    
    // Apply outer shape mask to alpha
    // We output pre-multiplied RGB or straight RGB? 
    // Standard is usually straight RGB with Alpha, but let's apply mask to RGB for clean edges on black background too
    outColor = float4(finalColor.rgb * outerAlpha, finalColor.a * outerAlpha);
}