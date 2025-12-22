#ifndef PI
#define PI 3.14159265359
#endif

// Helper: Rotate 2D vector
float2 rotate(float2 p, float angle) {
    float c = cos(angle);
    float s = sin(angle);
    return float2(p.x * c - p.y * s, p.x * s + p.y * c);
}

// Helper: Distance to Line Segment (Capsule)
float sdSegment(float2 p, float2 a, float2 b) {
    float2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}

void MagnifyingGlassSDF_float(float2 UV, float2 Center, float Size, float Rotation, float HandleLength, float HandleWidth, float RimThickness, float4 GlassColor, float4 FrameColor, float HighlightStrength, out float4 outColor) {
    // PLAN:
    // 1) Center UVs by subtracting Center parameter.
    // 2) Rotate the local coordinate space to handle rotation.
    // 3) Calculate SDFs for Glass (Circle), Handle (Segment), and Rim (Annulus).
    // 4) Combine shapes using CSG (Union/Difference).
    // 5) Calculate Highlight SDF for effect.
    // 6) Use smoothstep for AA and composite layers (Frame over Glass).
    
    // 1. Transform Coordinates
    float2 p = UV - Center;
    p = rotate(p, Rotation);

    // 2. Define SDFs
    // Glass is the inner circle
    float dGlass = length(p) - Size;

    // Frame outer boundary
    float rOuter = Size + RimThickness;
    float dFrameOuter = length(p) - rOuter;

    // Handle is a segment starting at bottom of rim
    float2 hStart = float2(0.0, -rOuter + 0.01); // slight overlap into rim
    float2 hEnd = float2(0.0, -rOuter - HandleLength);
    float dHandle = sdSegment(p, hStart, hEnd) - (HandleWidth * 0.5);

    // Combine Outer Frame and Handle
    float dSolid = min(dFrameOuter, dHandle);

    // Final Frame: Solid shape MINUS the inner glass hole
    // Use max(Solid, -Glass) for subtraction (since dGlass < 0 inside)
    float dFrame = max(dSolid, -dGlass);

    // Highlight: Small glare offset to top-right
    float2 hPos = p - float2(Size * 0.35, Size * 0.35);
    float dHighlight = length(hPos) - (Size * 0.25);

    // 3. Masks (Anti-Aliasing)
    // Use derivative for consistent AA width in screen space
    float aa = length(fwidth(p));
    aa = max(aa, 0.0001); // Safety clamp

    float mGlass = smoothstep(aa, -aa, dGlass);
    float mFrame = smoothstep(aa, -aa, dFrame);
    float mHighlight = smoothstep(aa, -aa, dHighlight);

    // Clip highlight to glass
    mHighlight *= mGlass;

    // 4. Compositing
    // Glass Layer (Transparent + Highlight)
    // Add highlight to RGB, keep alpha proportional to glass opacity
    float3 glassRGB = GlassColor.rgb + (float3(1.0, 1.0, 1.0) * HighlightStrength * mHighlight);
    float glassA = GlassColor.a * mGlass;
    
    // Frame Layer (Opaque/Alpha)
    float3 frameRGB = FrameColor.rgb;
    float frameA = FrameColor.a * mFrame;

    // Blend Frame OVER Glass
    // Alpha = FrameAlpha + GlassAlpha * (1 - FrameAlpha)
    float outA = frameA + glassA * (1.0 - frameA);

    // RGB (Straight) Calculation
    // Premultiplied Color = FrameColor * FrameAlpha + GlassColor * GlassAlpha * (1 - FrameAlpha)
    float3 outRGB_Premul = frameRGB * frameA + glassRGB * glassA * (1.0 - frameA);
    
    // Avoid divide by zero for straight alpha output
    float3 outRGB = (outA > 1e-5) ? (outRGB_Premul / outA) : float3(0,0,0);

    outColor = float4(outRGB, outA);
}