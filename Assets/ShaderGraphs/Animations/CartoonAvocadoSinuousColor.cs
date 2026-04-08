using UnityEngine;

public class CartoonAvocadoSinuousColor : MonoBehaviour
{
    [Header("Animation Settings")]
    public bool loop = true;
    public float speed = 1f;
    public float duration = 2f;

    [Header("Color Targets")]
    public Color targetSkinColor = new Color(0.2f, 0.6f, 0.2f, 1f);
    public Color targetFleshColor = new Color(0.9f, 0.9f, 0.3f, 1f);

    private Material mat;
    private Color initialSkinColor;
    private Color initialFleshColor;
    private float startTime;

    void Awake()
    {
        Renderer rend = GetComponent<Renderer>();
        if (rend != null)
        {
            mat = rend.material;
            if (mat.HasProperty("_SkinColor"))
            {
                initialSkinColor = mat.GetColor("_SkinColor");
            }
            if (mat.HasProperty("_FleshColor"))
            {
                initialFleshColor = mat.GetColor("_FleshColor");
            }
        }
        startTime = Time.time;
    }

    void Update()
    {
        if (mat == null) return;

        float elapsed = Time.time - startTime;
        float t = 0f;

        if (loop)
        {
            // Create a smooth 0 to 1 sinuous oscillation
            t = (Mathf.Sin(elapsed * speed) + 1f) * 0.5f;
        }
        else
        {
            // Perform a one-shot sine wave cycle over 'duration'
            float normalizedTime = Mathf.Clamp01(elapsed / duration);
            t = Mathf.Sin(normalizedTime * Mathf.PI);
        }

        mat.SetColor("_SkinColor", Color.Lerp(initialSkinColor, targetSkinColor, t));
        mat.SetColor("_FleshColor", Color.Lerp(initialFleshColor, targetFleshColor, t));
    }

    public void Reset()
    {
        if (mat != null)
        {
            mat.SetColor("_SkinColor", initialSkinColor);
            mat.SetColor("_FleshColor", initialFleshColor);
        }
    }
}