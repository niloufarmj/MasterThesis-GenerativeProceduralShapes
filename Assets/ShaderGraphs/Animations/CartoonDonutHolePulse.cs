using UnityEngine;

public class CartoonDonutHolePulse : MonoBehaviour
{
    [Header("Animation Settings")]
    public bool loop = true;
    public float speed = 3f;

    [Header("Mask Size (Hole Size)")]
    public float minMaskSize = 0f;
    public float maxMaskSize = 1f;

    private Material mat;
    private float initialMask;
    private float startTime;

    void Awake()
    {
        Renderer rend = GetComponent<Renderer>();
        if (rend != null)
        {
            mat = rend.material;
            if (mat.HasProperty("_mask"))
            {
                initialMask = mat.GetFloat("_mask");
            }
        }
        startTime = Time.time;
    }

    void Update()
    {
        if (mat == null) return;

        float elapsedTime = Time.time - startTime;
        float phase = elapsedTime * speed;

        // Stop at one full cycle if not looping
        if (!loop && phase > Mathf.PI * 2f)
        {
            phase = Mathf.PI * 2f;
        }

        // Using 1 - Cos normalizes the wave to start at 0, peak at 1, and return to 0 at 2PI
        float wave = (1f - Mathf.Cos(phase)) * 0.5f;
        float currentMask = Mathf.Lerp(minMaskSize, maxMaskSize, wave);

        mat.SetFloat("_mask", currentMask);
    }

    public void Reset()
    {
        if (mat != null)
        {
            mat.SetFloat("_mask", initialMask);
        }
    }
}