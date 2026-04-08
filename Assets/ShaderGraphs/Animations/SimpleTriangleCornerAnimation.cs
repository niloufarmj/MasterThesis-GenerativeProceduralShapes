using UnityEngine;

public class SimpleTriangleCornerAnimation : MonoBehaviour
{
    [Header("Animation Control")]
    public bool loop = true;
    public float speed = 2f;

    [Header("Corner Radius Range")]
    public float minCornerRadius = 0.0f;
    public float maxCornerRadius = 0.25f;

    private Material mat;
    private float initialCornerRadius;
    private float startTime;

    void Awake()
    {
        mat = GetComponent<Renderer>().material;
        if (mat.HasProperty("__CornerRadius"))
        {
            initialCornerRadius = mat.GetFloat("__CornerRadius");
        }
    }

    void OnEnable()
    {
        startTime = Time.time;
    }

    void Update()
    {
        if (mat == null || !loop) return;

        // Sinuous oscillation using Sine wave, mapped from -1..1 to 0..1
        float t = (Mathf.Sin((Time.time - startTime) * speed) + 1f) * 0.5f;
        float currentRadius = Mathf.Lerp(minCornerRadius, maxCornerRadius, t);

        mat.SetFloat("__CornerRadius", currentRadius);
    }

    public void Reset()
    {
        if (mat != null && mat.HasProperty("__CornerRadius"))
        {
            mat.SetFloat("__CornerRadius", initialCornerRadius);
        }
    }
}