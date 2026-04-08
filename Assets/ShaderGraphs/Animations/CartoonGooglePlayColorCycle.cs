using UnityEngine;

public class CartoonGooglePlayColorCycle : MonoBehaviour
{
    [Header("Animation Settings")]
    public bool loop = true;
    [Tooltip("Speed of the color rotation cycle.")]
    public float speed = 1.5f;
    [Tooltip("Uses SmoothStep for softer color transitions if true.")]
    public bool smoothEasing = true;

    private Material mat;
    private Color[] originalColors = new Color[4];
    private float startTime;

    void Awake()
    {
        Renderer rend = GetComponent<Renderer>();
        if (rend != null)
        {
            mat = rend.material;
        }

        if (mat != null)
        {
            // Store initial color values: Top(0), Right(1), Bottom(2), Left(3)
            originalColors[0] = mat.GetColor("_ColorTop");
            originalColors[1] = mat.GetColor("_ColorRight");
            originalColors[2] = mat.GetColor("_ColorBottom");
            originalColors[3] = mat.GetColor("_ColorLeft");
        }
        
        startTime = Time.time;
    }

    void Update()
    {
        if (mat == null) return;

        float elapsed = Time.time - startTime;
        float t = elapsed * speed;

        if (!loop)
        {
            // Clamp to 4 phases to complete exactly one full color rotation
            t = Mathf.Clamp(t, 0f, 4f);
        }

        int i = Mathf.FloorToInt(t);
        float f = t - i;
        
        if (smoothEasing)
        {
            f = Mathf.SmoothStep(0f, 1f, f);
        }

        // Rotate colors smoothly across the four directional zones
        mat.SetColor("_ColorTop", Color.Lerp(originalColors[i % 4], originalColors[(i + 1) % 4], f));
        mat.SetColor("_ColorRight", Color.Lerp(originalColors[(i + 1) % 4], originalColors[(i + 2) % 4], f));
        mat.SetColor("_ColorBottom", Color.Lerp(originalColors[(i + 2) % 4], originalColors[(i + 3) % 4], f));
        mat.SetColor("_ColorLeft", Color.Lerp(originalColors[(i + 3) % 4], originalColors[(i + 4) % 4], f));
    }

    public void Reset()
    {
        if (mat != null)
        {
            mat.SetColor("_ColorTop", originalColors[0]);
            mat.SetColor("_ColorRight", originalColors[1]);
            mat.SetColor("_ColorBottom", originalColors[2]);
            mat.SetColor("_ColorLeft", originalColors[3]);
        }
        startTime = Time.time;
    }
}