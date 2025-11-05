void DrawPentagon_float(float2 UV, float size, float rotation, out float4 outColor) 
    { 
    float2 vertices[5]; 
    float angleStep = 6.28318530718 / 5; 
    float2 center = float2(0.5, 0.5); 
    outColor = float4(0, 0, 0, 0); 
        for (int i = 0; i < 5; ++i) 
        { 
            float angle = angleStep * i + rotation; 
            vertices[i] = center + size * float2(cos(angle), sin(angle));
        } 
    float2 p1 = vertices[0]; 
    float2 p2 = vertices[1]; 
    float2 p3 = vertices[2]; 
    float2 p4 = vertices[3]; 
    float2 p5 = vertices[4]; 
    bool inside = PointInTriangle(UV, p1, p2, p3) || PointInTriangle(UV, p1, p3, p4) || PointInTriangle(UV, p1, p4, p5); if (inside) { outColor = float4(1, 1, 1, 1); } } bool PointInTriangle(float2 pt, float2 v1, float2 v2, float2 v3) { float d1, d2, d3; bool has_neg, has_pos; d1 = sign(pt, v1, v2); d2 = sign(pt, v2, v3); d3 = sign(pt, v3, v1); has_neg = (d1 < 0) || (d2 < 0) || (d3 < 0); has_pos = (d1 > 0) || (d2 > 0) || (d3 > 0); return !(has_neg && has_pos); } float sign(float2 p1, float2 p2, float2 p3) { return (p1.x - p3.x) * (p2.y - p3.y) - (p2.x - p3.x) * (p1.y - p3.y); }