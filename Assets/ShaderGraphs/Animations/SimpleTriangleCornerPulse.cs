using UnityEngine;

public class SimpleTriangleCornerPulse : MonoBehaviour
{
    [Header("Animation Settings")]
    public bool loop = true;
    public float speed = 3f;

    [Header("Corner Radius Settings")]
    public float minCornerRadius = 0.0f;
    public float maxCornerRadius = 0.14f;

    private Material _material;
    private float _initialMaxCornerRadius;
    private float _startTime;

    private void Awake()
    {
        Renderer renderer = GetComponent<Renderer>();
        if (renderer != null)
        {
            _material = renderer.material;
            _initialMaxCornerRadius = _material.GetFloat("_MaxCornerRadius");
        }
        _startTime = Time.time;
    }

    private void Update()
    {
        if (_material == null) return;

        float timeElapsed = Time.time - _startTime;
        float phase = timeElapsed * speed;

        if (!loop && phase > Mathf.PI * 2f)
        {
            phase = Mathf.PI * 2f;
        }

        // Shifted sine wave: starts at 0, smoothly interpolates to 1, and back to 0
        float t = (Mathf.Sin(phase - Mathf.PI / 2f) + 1f) * 0.5f;
        
        float currentRadius = Mathf.Lerp(minCornerRadius, maxCornerRadius, t);
        _material.SetFloat("_MaxCornerRadius", currentRadius);
    }

    public void Reset()
    {
        if (_material != null)
        {
            _material.SetFloat("_MaxCornerRadius", _initialMaxCornerRadius);
        }
    }
}