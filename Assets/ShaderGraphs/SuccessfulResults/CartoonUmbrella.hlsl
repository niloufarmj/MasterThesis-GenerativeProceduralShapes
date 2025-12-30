/*
  PLAN:
  1. Define constants and SDF helpers (Box, Arc, Circle, Ellipse).
  2. Remap UVs to center and scale space.
  3. Handle SDF:
     - Vertical box for the shaft starting at canopy bottom (y=0) downwards.
     - 180-degree arc for the hook at the bottom of the shaft.
  4. Canopy SDF:
     - Main body: Semi-ellipse (or semi-circle if Width=Height) positioned at y=0.
     - Scallops: 5 circular cutouts along the bottom edge (y=0). Radius derived from panel width and curvature depth.
     - Shape = Intersection(UpperEllipse, Negation(ScallopCircles)).
  5. Coloring:
     - Calculate x-index for 5 panels to apply individual colors.
     - Add vertical stroke lines between panels for detail.
  6. Composition:
     - Draw Handle (Behind).
     - Draw Canopy (Front).
     - Apply Stroke to all outer edges.
*/

#ifndef PI
#define PI 3.14159265359
#endif

// SDF for a Box
float umb_sdBox(float2 p, float2 b) {
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// SDF for a Line Segment
float umb_sdSegment(float2 p, float2 a, float2 b) {
    float2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}

// SDF for a 180 degree vertical Arc (J-shape)
// Center is the pivot, r is radius, th is thickness
// Opens to the left (negative x)
float umb_sdHookShape(float2 p, float2 center, float r, float th) {
    float2 q = p - center;
    // We want a semi-circle on the left side: angles [PI/2, 3PI/2] roughly?
    // Actually standard hook goes down then curves up. 
    // Let's model it as a distance to a semicircular wire.
    // Center of curvature is at (center.x - r, center.y).
    float2 curveCenter = float2(center.x - r, center.y);
    float2 local = p - curveCenter;
    
    // Angle restriction: We want the bottom half of the circle (y < center.y)
    // But we need to be careful with the endpoints to match the shaft.
    // Shaft connects at (center.x, center.y). This corresponds to angle 0 on the circle relative to curveCenter.
    // Tip is at angle -PI (or PI).
    
    float dCircle = abs(length(local) - r) - th * 0.5;
    
    // We only want the lower half (y < center.y)
    // If y > center.y, we are equidistant to the endpoints.
    // Endpoint 1: (r, 0) relative to curveCenter -> (center.x, center.y) (Connects to shaft)
    // Endpoint 2: (-r, 0) relative to curveCenter -> (center.x - 2r, center.y) (Tip)
    
    if (local.y > 0.0) {
        float d1 = length(local - float2(r, 0.0));
        float d2 = length(local - float2(-r, 0.0));
        return min(d1, d2) - th * 0.5;
    }
    
    return dCircle;
}

// Approximate SDF for an ellipse
float umb_sdEllipse(float2 p, float2 r) {
    float k0 = length(p/r);
    float k1 = length(p/(r*r));
    return k0 * (k0 - 1.0) / k1;
}

// Alpha blending helper
float4 umb_over(float4 src, float4 dst) {
    return src + dst * (1.0 - src.a);
}

void UmbrellaCartoon_float(
    float2 UV,
    float2 Center,
    float Size,
    float CanopyWidth,
    float CanopyHeight,
    float PanelCurvature,
    float HandleHeight,
    float HandleThickness,
    float HookRadius,
    float4 PanelColor1,
    float4 PanelColor2,
    float4 PanelColor3,
    float4 PanelColor4,
    float4 PanelColor5,
    float4 HandleColor,
    float4 StrokeColor,
    float StrokeWidth,
    out float4 outColor
) {
    // 1. Normalize Coordinates
    float2 p = UV - Center;
    p /= max(Size, 0.001);
    
    // --- HANDLE SDF ---
    // Shaft is a vertical box centered on Y-axis, extending from y=0 down to -HandleHeight
    float halfThick = HandleThickness * 0.5;
    float2 shaftStart = float2(0.0, 0.0);
    float2 shaftEnd = float2(0.0, -HandleHeight);
    
    // Shaft SDF
    float dShaft = umb_sdBox(p - (shaftStart + shaftEnd) * 0.5, float2(halfThick, HandleHeight * 0.5));
    
    // Hook SDF
    // Attached at shaftEnd. Radius = HookRadius.
    float dHook = umb_sdHookShape(p, shaftEnd, HookRadius, HandleThickness);
    
    // Combine Handle
    float dHandle = min(dShaft, dHook);
    
    // --- CANOPY SDF ---
    // 1. Semi-Ellipse Body
    // We model the top as an ellipse centered at (0,0).
    // We will clip the bottom part later.
    float dBody = umb_sdEllipse(p, float2(CanopyWidth * 0.5, CanopyHeight));
    
    // 2. Scalloped Bottom
    // We subtract circles along the bottom edge.
    // There are 5 panels. Total width = CanopyWidth.
    float panelW = CanopyWidth / 5.0;
    
    // We calculate the circle radius required to produce the desired 'sag' (PanelCurvature)
    // given the chord length (panelW).
    // Formula: R = (w^2 + 4s^2) / (8s)
    float s = max(PanelCurvature, 0.001);
    float w = panelW;
    float R = (w*w + 4.0*s*s) / (8.0*s);
    
    // Center Y offset for the circle: yc = s - R
    // The circle top (closest to 0) is at y = s (relative to circle center) -> y = 0 in space? No.
    // We want the scalloped edge to have peaks at y=0 (ribs) and valleys at y=s (relative to 0).
    // Actually, usually an umbrella curves UP between ribs. So the fabric is higher than the ribs.
    // Let's assume ribs are at y=0. Fabric arcs up to y=s.
    // Then we subtract a circle centered BELOW y=0.
    // Circle passes through (-w/2, 0) and (w/2, 0) and (0, s).
    // Center is (0, yc). Dist to (0,s) is R -> |s - yc| = R.
    // Dist to (w/2, 0) is R -> w^2/4 + yc^2 = R^2.
    // With y=s being the peak of the cutout (void), this makes sense.
    // Wait, if we subtract the circle, the void goes up to y=s.
    // The canopy remains where y > circle_edge.
    // So the bottom edge of canopy will be an arc from 0 to s to 0.
    // This matches the look of loose fabric.
    
    float yc = (s*s - w*w*0.25) / (2.0*s);
    float scallopRadius = abs(s - yc);
    
    // Determine which panel we are under to find the local center
    // Map x to panel index [-2, 2] for 5 panels centered at 0
    float panelIndex = floor((p.x + CanopyWidth * 0.5) / panelW);
    // Clamp to valid panels [0, 4]
    float clampedIdx = clamp(panelIndex, 0.0, 4.0);
    
    // Center X of the current panel's scallop
    float centerX = (clampedIdx + 0.5) * panelW - CanopyWidth * 0.5;
    
    // Distance to the subtraction circle
    float dScallopCircle = length(float2(p.x - centerX, p.y - yc)) - scallopRadius;
    
    // We also need to cut the ellipse at the bottom generally.
    // The ellipse extends to -Height. We want it to stop at the scallops.
    // The scallops are around y=0. 
    // Boolean subtraction: Intersection(Body, Not(Scallops)).
    // But we also need to enforce the general "upper half" constraint so the bottom of ellipse is gone.
    // Let's define the cut boundary as the union of the 5 scallop circles plus a plane below.
    // Or simpler: max(dBody, -dScallopCircle).
    // Since the scallop circles are huge (low curvature), they form a continuous boundary near y=0.
    // However, between the circles (at the ribs), the distance might leak.
    // Let's explicitly union the scallop distances? 
    // Just using the closest scallop is usually sufficient if they meet exactly at the ribs.
    // They meet at (ribX, 0). At this point, dScallopCircle = 0.
    // So max(dBody, 0) would cut exactly at 0.
    // If we want the ribs to be sharp, this works.
    
    float dCanopy = max(dBody, -dScallopCircle);
    
    // Also clip anything well below the canopy to avoid ellipse artifacts if any
    // The scallops handle the edge near 0. If y < -0.1, it should definitely be empty.
    // max(dCanopy, -p.y - 0.1) is a safety clip, but the scallops should cover it.
    // Actually, if we are far down, -dScallopCircle (distance to center ~0, radius large) 
    // becomes -(large - large) ~ 0. Wait.
    // If y is very negative, p is far from circle center (yc is negative). 
    // length is large. dScallop is large positive. -dScallop is large negative.
    // max(dBody, large_negative) = dBody.
    // So the ellipse WOULD return at the bottom.
    // WE MUST CLIP THE BOTTOM HALF OF THE ELLIPSE.
    // Intersection with half-plane y > -some_margin.
    // The lowest point of the scallop is at y=0 (rib tips). 
    // So we can safely clip everything below y = -0.01 (margin for stroke).
    // But strictly, dCanopy should be intersected with a plane.
    dCanopy = max(dCanopy, -(p.y + HandleThickness)); // Clip below geometric bottom

    // --- COLOR LOGIC ---
    float aa = fwidth(dBody) * 1.5; // Antialiasing width
    
    // Handle Color
    float handleAlpha = 1.0 - smoothstep(0.0, aa, dHandle);
    float handleStroke = 1.0 - smoothstep(0.0, aa, abs(dHandle) - StrokeWidth * 0.5);
    float4 handleFill = float4(HandleColor.rgb, 1.0);
    float4 handleOut = lerp(float4(0,0,0,0), handleFill, handleAlpha);
    handleOut = lerp(handleOut, StrokeColor, handleStroke * HandleColor.a);
    
    // Canopy Color
    // Select color based on clampedIdx
    float4 cCol = PanelColor1;
    if (abs(clampedIdx - 1.0) < 0.1) cCol = PanelColor2;
    if (abs(clampedIdx - 2.0) < 0.1) cCol = PanelColor3;
    if (abs(clampedIdx - 3.0) < 0.1) cCol = PanelColor4;
    if (abs(clampedIdx - 4.0) < 0.1) cCol = PanelColor5;
    
    // Canopy Alpha & Stroke
    float canopyAlpha = 1.0 - smoothstep(0.0, aa, dCanopy);
    float canopyStroke = 1.0 - smoothstep(0.0, aa, abs(dCanopy) - StrokeWidth * 0.5);
    
    // Add vertical lines between panels
    // Ribs are at x = -2w, -w, 0, w, 2w (relative to center)
    // We want distance to nearest rib x.
    // x relative to center + offset to align 0 with a rib?
    // Panels are centered at 0.5, 1.5... Ribs are at integers * w - width/2.
    // Rib X coords: -2.5w (edge), -1.5w, -0.5w, 0.5w, 1.5w, 2.5w (edge)
    // Wait, 5 panels. -2.5 to 2.5 range? No. Width is 5w.
    // Domain is -2.5w to 2.5w.
    // Ribs are at -1.5w, -0.5w, 0.5w, 1.5w.
    // Let's calculate dist to nearest internal rib.
    float ribDist = 1e5;
    for(float i = -1.5; i <= 1.5; i += 1.0) {
        float rx = i * panelW;
        // Rib is a vertical line segment from y=0 up to ellipse top? 
        // Or just a line on the shell. In 2D, it's a vertical line.
        // Clip to canopy inside.
        float dLine = abs(p.x - rx);
        ribDist = min(ribDist, dLine);
    }
    
    // Rib stroke
    float ribStrokeVal = 1.0 - smoothstep(0.0, aa, ribDist - StrokeWidth * 0.3);
    // Mask rib stroke by canopy alpha (so it doesn't go outside)
    ribStrokeVal *= canopyAlpha;

    float4 canopyFill = float4(cCol.rgb, 1.0);
    float4 canopyOut = lerp(float4(0,0,0,0), canopyFill, canopyAlpha);
    
    // Apply internal rib strokes
    canopyOut = lerp(canopyOut, StrokeColor, ribStrokeVal * StrokeColor.a);
    // Apply outline stroke
    canopyOut = lerp(canopyOut, StrokeColor, canopyStroke * StrokeColor.a);

    // --- COMPOSITION ---
    // Handle behind Canopy
    outColor = umb_over(canopyOut, handleOut);
}