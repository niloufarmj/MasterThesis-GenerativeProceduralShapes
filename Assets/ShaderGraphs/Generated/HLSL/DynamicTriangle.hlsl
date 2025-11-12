float sdf_rounded_triangle(float2 p, float edge_length, float radius) 
{ 
    float3 p3 = abs(p); 
    float s = max(p3.x, p3.y) - edge_length + radius; 
    return min(s, length(max(p3 - edge_length, 0.0)) - radius); 
} 
void DynamicTriangle_float(float2 UV, float edge_length, float radius, out float4 outColor) 
{
    UV = UV * 2 - 1; 
    float d = sdf_rounded_triangle(UV, edge_length, radius); 
    float alpha = smoothstep(0.02, 0.0, d); 
    outColor = float4(1,1,1, alpha); 
}