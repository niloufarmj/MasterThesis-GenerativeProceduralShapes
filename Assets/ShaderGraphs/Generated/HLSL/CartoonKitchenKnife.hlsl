/* 
  Cartoon Kitchen Knife SDF
  Generates a 2D kitchen knife with adjustable blade profile, handle, and rivets.
  Uses 2D SDF primitives and convex shape intersection for the blade.
*/

#ifndef PI
#define PI 3.14159265359
#endif

// --- Helper Functions ---

// Signed distance to a 2D box with rounded corners
// p: point, b: half-extents, r: radius
float ck_sdRoundedBox(float2 p, float2 b, float r) {
    float2 q = abs(p) - b + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

// --- Main Shader Function ---
void CartoonKitchenKnife_float(float2 UV, 
                               float BladeLength, float BladeWidth, float TipSharpness, 
                               float HandleLength, float HandleThickness, float4 HandleColor,
                               float RivetCount, float RivetSize, 
                               float StrokeThickness, float4 BladeColor, float4 RivetColor, float4 StrokeColor,
                               out float4 outColor)
{
    // PLAN:
    // 1. Center UVs based on total knife width to ensure visibility.
    // 2. Define Handle using a Rounded Box SDF.
    // 3. Define Blade using intersection of 4 half-planes (Top, Base, Tip, Curved Bottom).
    // 4. Define Rivets as a union of circles distributed along the handle.
    // 5. Combine shapes and compute coverage masks (Fill, Stroke, Rivets).
    // 6. Composite colors with anti-aliasing.

    // 1. Setup Coordinates
    float2 p = UV - 0.5;
    
    // Validate inputs to prevent divide-by-zero or negative scales
    float bLen = max(BladeLength, 0.001);
    float bWid = max(BladeWidth, 0.001);
    float hLen = max(HandleLength, 0.001);
    float hThick = max(HandleThickness, 0.001);
    float tipSharp = max(TipSharpness, 0.1);
    
    // Calculate centering offset
    // Knife spans x: [-hLen, bLen]. Center X is (bLen - hLen) / 2.0.
    float centerX = (bLen - hLen) * 0.5;
    p.x -= centerX;

    // 2. Handle SDF
    // Handle is a rounded box extending from -hLen to 0.
    // Center of handle box is at x = -hLen/2, y = 0.
    float2 hSize = float2(hLen, hThick) * 0.5;
    float2 hCenter = float2(-hLen * 0.5, 0.0);
    // Maximum radius is half the thickness for a pill shape
    float hRad = min(hSize.x, hSize.y);
    float dHandle = ck_sdRoundedBox(p - hCenter, hSize, hRad);

    // 3. Blade SDF
    // Blade starts at x=0. Top edge (spine) aligns with handle top (y = +hSize.y).
    // Spine Y position
    float spineY = hSize.y;
    
    // Define clipping planes for the blade box
    // Inside < 0, Outside > 0
    float dBladeBase = -p.x;              // Clip left of x=0
    float dBladeTip  = p.x - bLen;        // Clip right of x=bLen
    float dBladeTop  = p.y - spineY;      // Clip above spine
    
    // Curve Math: y_edge = HeelY + (TipY - HeelY) * (x/L)^Sharpness
    // Heel is at y = spineY - bWid. Tip is at y = spineY.
    // We want distance from point P to this curve.
    // Vertical distance approximation: d = CurveY - P.y
    // We want to be ABOVE the curve (Inside). So if P.y < CurveY, d > 0 (Outside).
    float t = saturate(p.x / bLen);
    float curveY = (spineY - bWid) + bWid * pow(t, tipSharp);
    float dBladeCurve = curveY - p.y;
    
    // Combine blade constraints (Intersection = Max)
    // We clip the infinite curve with the base, tip, and top planes.
    float dBlade = max(dBladeTop, max(dBladeBase, max(dBladeTip, dBladeCurve)));

    // 4. Rivets SDF
    // Union of circles along the handle
    float dRivets = 1e5; // Start far away
    float rCount = floor(max(RivetCount, 0.0));
    if (rCount > 0.0)
    {
        // Distribute rivets between -hLen and 0
        // Add padding so they aren't on the edge
        float pad = hLen * 0.15;
        float startX = -hLen + pad;
        float endX = -pad;
        
        // Loop to place rivets
        for (float i = 0.0; i < 10.0; i++)
        {
            if (i >= rCount) break;
            // Normalized position 0..1
            float t_riv = (rCount > 1.0) ? (i / (rCount - 1.0)) : 0.5;
            float rX = lerp(startX, endX, t_riv);
            float dCircle = length(p - float2(rX, 0.0)) - RivetSize;
            dRivets = min(dRivets, dCircle);
        }
    }

    // 5. Compositing
    // Combined body shape (Union = Min)
    float dBody = min(dHandle, dBlade);
    
    // Anti-aliasing factor based on screen-space derivatives
    // fwidth gives approximate pixel size at this location
    float aa = fwidth(dBody);
    aa = max(aa, 0.0001); // Avoid zero

    // Masks (0..1)
    float halfStroke = StrokeThickness * 0.5;
    
    // Main Body Fill (Inside body, accounting for stroke width)
    float fillMask = 1.0 - smoothstep(-aa, aa, dBody + halfStroke);
    
    // Main Body Stroke (Band around the edge)
    float strokeMask = 1.0 - smoothstep(-aa, aa, abs(dBody + halfStroke) - StrokeThickness);
    // Note: To make outline 'centered' on edge 0, usually we do abs(d) - width.
    // Here we want outline ON TOP of the shape boundary. 
    // Let's use a standard Outer Stroke approach: 
    // Shape is dBody. 
    // Outer boundary is dBody - StrokeThickness/2 (expanded).
    // Inner boundary is dBody + StrokeThickness/2 (shrunk).
    // Let's simpler: 
    // Total opaque area = dBody - StrokeThickness.
    float totalMask = 1.0 - smoothstep(-aa, aa, dBody - StrokeThickness * 0.5);
    float innerMask = 1.0 - smoothstep(-aa, aa, dBody + StrokeThickness * 0.5);
    float outlineAlpha = totalMask - innerMask; // Ring
    
    // Rivet Masks
    float rivetFillMask = 1.0 - smoothstep(-aa, aa, dRivets);
    float rivetOutlineMask = (1.0 - smoothstep(-aa, aa, dRivets - StrokeThickness)) - rivetFillMask;

    // 6. Color Mixing
    // Base Fill (Handle vs Blade)
    // Smooth blending at the junction x=0
    float partSelector = smoothstep(-0.02, 0.02, p.x);
    float4 baseFill = lerp(HandleColor, BladeColor, partSelector);
    
    // Start with background (transparent)
    float4 finalColor = float4(0, 0, 0, 0);
    
    // Draw Body Fill
    // Pre-multiply alpha for proper blending
    finalColor = float4(baseFill.rgb * innerMask, innerMask);
    
    // Draw Body Stroke (Over fill)
    // Lerp towards stroke color based on outline alpha
    finalColor.rgb = lerp(finalColor.rgb, StrokeColor.rgb, outlineAlpha);
    finalColor.a = max(finalColor.a, totalMask);

    // Draw Rivets (Over body)
    // Rivet Fill
    // We only draw rivets if we are on the handle (x < 0 approximately)
    // but SDF handles spatial logic. 
    // Composite Rivet Fill
    float rivetAlpha = rivetFillMask;
    finalColor.rgb = lerp(finalColor.rgb, RivetColor.rgb, rivetAlpha);
    finalColor.a = max(finalColor.a, rivetAlpha);
    
    // Composite Rivet Outline
    finalColor.rgb = lerp(finalColor.rgb, StrokeColor.rgb, rivetOutlineMask);
    finalColor.a = max(finalColor.a, rivetOutlineMask);
    
    // Final Output
    outColor = finalColor;
}