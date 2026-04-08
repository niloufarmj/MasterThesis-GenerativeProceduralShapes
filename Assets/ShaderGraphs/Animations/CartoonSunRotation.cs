using UnityEngine;

public class CartoonSunRotation : MonoBehaviour
{
    [Header("Animation Control")]
    public bool loop = true;
    public float speed = 1f;

    [Header("Rotation Settings")]
    public float rotationSpeed = 2f;
    public bool clockwise = false;

    private Material mat;
    private float initialRotation;

    void Awake()
    {
        Renderer rend = GetComponent<Renderer>();
        if (rend != null)
        {
            mat = rend.material;
            initialRotation = mat.GetFloat("_Rotation");
        }
    }

    void Update()
    {
        if (mat == null || !loop) return;

        float direction = clockwise ? -1f : 1f;
        float animatedRotation = initialRotation + (Time.time * speed * rotationSpeed * direction);
        
        mat.SetFloat("_Rotation", animatedRotation);
    }

    public void Reset()
    {
        if (mat != null)
        {
            mat.SetFloat("_Rotation", initialRotation);
        }
    }
}