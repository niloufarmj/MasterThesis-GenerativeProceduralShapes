using UnityEngine;

public class TechnicalMannequinYogaTree : MonoBehaviour
{
    [Header("Animation Control")]
    public bool loop = true;
    public float speed = 1f;

    [Header("Timing (Seconds)")]
    public float holdTPoseDuration = 1.5f;
    public float transitionToTreeDuration = 2.0f;
    public float holdTreeDuration = 2.0f;
    public float transitionToTPoseDuration = 2.0f;

    [Header("Tree Pose Target Angles")]
    public float tree_LShoulderAngle = 2.8f;
    public float tree_RShoulderAngle = -2.8f;
    public float tree_LElbowAngle = 0.5f;
    public float tree_RElbowAngle = 0.5f;
    public float tree_LHipAngle = 0.0f;
    public float tree_RHipAngle = 1.5f;
    public float tree_LKneeAngle = 0.0f;
    public float tree_RKneeAngle = 2.5f;

    private Material mat;
    private float timer = 0f;

    // Initial T-Pose Angles
    private float init_LShoulder;
    private float init_RShoulder;
    private float init_LElbow;
    private float init_RElbow;
    private float init_LHip;
    private float init_RHip;
    private float init_LKnee;
    private float init_RKnee;

    void Awake()
    {
        Renderer r = GetComponent<Renderer>();
        if (r != null)
        {
            mat = r.material;
            
            // Store initial values to use as the resting T-pose
            init_LShoulder = mat.GetFloat("_LShoulderAngle");
            init_RShoulder = mat.GetFloat("_RShoulderAngle");
            init_LElbow = mat.GetFloat("_LElbowAngle");
            init_RElbow = mat.GetFloat("_RElbowAngle");
            init_LHip = mat.GetFloat("_LHipAngle");
            init_RHip = mat.GetFloat("_RHipAngle");
            init_LKnee = mat.GetFloat("_LKneeAngle");
            init_RKnee = mat.GetFloat("_RKneeAngle");
        }
    }

    void Update()
    {
        if (mat == null) return;

        timer += Time.deltaTime * speed;
        float totalDuration = holdTPoseDuration + transitionToTreeDuration + holdTreeDuration + transitionToTPoseDuration;

        float currentTime = timer;
        if (loop)
        {
            currentTime = timer % totalDuration;
        }
        else
        {
            currentTime = Mathf.Clamp(timer, 0f, totalDuration);
        }

        float t = 0f;

        // Phase 1: Hold T-Pose
        if (currentTime < holdTPoseDuration)
        {
            t = 0f;
        }
        // Phase 2: Transition to Tree Pose
        else if (currentTime < holdTPoseDuration + transitionToTreeDuration)
        {
            float localT = (currentTime - holdTPoseDuration) / transitionToTreeDuration;
            t = Mathf.SmoothStep(0f, 1f, localT);
        }
        // Phase 3: Hold Tree Pose
        else if (currentTime < holdTPoseDuration + transitionToTreeDuration + holdTreeDuration)
        {
            t = 1f;
        }
        // Phase 4: Transition back to T-Pose
        else
        {
            float localT = (currentTime - (holdTPoseDuration + transitionToTreeDuration + holdTreeDuration)) / transitionToTPoseDuration;
            t = Mathf.SmoothStep(1f, 0f, localT);
        }

        // Apply interpolated values to material
        mat.SetFloat("_LShoulderAngle", Mathf.Lerp(init_LShoulder, tree_LShoulderAngle, t));
        mat.SetFloat("_RShoulderAngle", Mathf.Lerp(init_RShoulder, tree_RShoulderAngle, t));
        mat.SetFloat("_LElbowAngle", Mathf.Lerp(init_LElbow, tree_LElbowAngle, t));
        mat.SetFloat("_RElbowAngle", Mathf.Lerp(init_RElbow, tree_RElbowAngle, t));
        mat.SetFloat("_LHipAngle", Mathf.Lerp(init_LHip, tree_LHipAngle, t));
        mat.SetFloat("_RHipAngle", Mathf.Lerp(init_RHip, tree_RHipAngle, t));
        mat.SetFloat("_LKneeAngle", Mathf.Lerp(init_LKnee, tree_LKneeAngle, t));
        mat.SetFloat("_RKneeAngle", Mathf.Lerp(init_RKnee, tree_RKneeAngle, t));
    }

    public void Reset()
    {
        if (mat == null) return;

        mat.SetFloat("_LShoulderAngle", init_LShoulder);
        mat.SetFloat("_RShoulderAngle", init_RShoulder);
        mat.SetFloat("_LElbowAngle", init_LElbow);
        mat.SetFloat("_RElbowAngle", init_RElbow);
        mat.SetFloat("_LHipAngle", init_LHip);
        mat.SetFloat("_RHipAngle", init_RHip);
        mat.SetFloat("_LKneeAngle", init_LKnee);
        mat.SetFloat("_RKneeAngle", init_RKnee);
        
        timer = 0f;
    }
}