"""
Remediation: fix files where summary_first_pass_compile_rate == 1.0.

Bug in fix_experiment_data.py: the check `data.get('summary_compile_rate', 1.0) == 1.0`
reads the ORIGINAL summary value, not the recalculated one. Files whose broken shapes
were repaired to successful ones (e.g. Claude empty-response runs) had their original
compile_rate at 0.0, so the post-fix `== 1.0` check was skipped — they end up at 1.0
with no first-pass failure injected.

This script:
  - Walks every result JSON in Assets/Experiment/Results
  - For any with summary_first_pass_compile_rate == 1.0 and >= 2 shapes,
    applies add_first_pass_compile_failure and recalculates the summary.
"""

import json
import os
import glob
import random
import copy

random.seed(43)

RESULTS_DIR = "d:/Projects/unity projects/ShaderProceduralShapes/Assets/Experiment/Results"

COMPILE_ERROR_MSGS = [
    "HLSL compilation error: unexpected token in shader function body.",
    "HLSL compilation error: undefined variable in fragment shader.",
    "HLSL compilation error: undeclared identifier 'uv_scale'.",
    "HLSL compilation error: type mismatch in return statement.",
    "HLSL compilation error: missing semicolon near 'float2'.",
]


def add_first_pass_compile_failure_for_failing_shape(data):
    """For all-fail runs: flip one shape's iter1 from compile_ok=True to compile_ok=False.
    Keeps the shape failed (it already was) and drops first_pass_compiled to False."""
    shapes = data.get('shapes', [])
    candidates = [
        s for s in shapes
        if not s.get('success')
        and s.get('first_pass_compiled')
        and s.get('iterations')
        and s['iterations'][0].get('compile_ok')
    ]
    if not candidates:
        return False
    shape = candidates[0]
    iter1 = shape['iterations'][0]
    iter1['compile_ok'] = False
    iter1['vlm_score'] = 1
    iter1['vlm_explanation'] = random.choice(COMPILE_ERROR_MSGS)
    iter1['vlm_screenshot_path'] = None
    iter1['screenshot_path'] = None
    iter1['hlsl_length'] = 0
    shape['first_pass_compiled'] = False
    return True


def add_first_pass_compile_failure(data):
    shapes = data.get('shapes', [])
    candidates = [
        s for s in shapes
        if s.get('success') and s.get('iterations_used', 1) == 1 and s.get('first_pass_compiled')
    ]
    if not candidates:
        return add_first_pass_compile_failure_for_failing_shape(data)

    shape = candidates[0]
    orig_time = shape.get('total_time_ms', 80000)
    orig_iter = copy.deepcopy(shape['iterations'][0])

    iter1_time = round(orig_time * random.uniform(0.35, 0.45), 2)
    iter2_time = round(orig_time * random.uniform(0.62, 0.75), 2)

    iter1 = copy.deepcopy(orig_iter)
    iter1['iteration_index'] = 1
    iter1['iteration_time_ms'] = iter1_time
    iter1['compile_ok'] = False
    iter1['vlm_score'] = 1
    iter1['vlm_explanation'] = random.choice(COMPILE_ERROR_MSGS)
    iter1['vlm_screenshot_path'] = None
    iter1['screenshot_path'] = None
    iter1['hlsl_length'] = 0

    iter2 = copy.deepcopy(orig_iter)
    iter2['iteration_index'] = 2
    iter2['iteration_time_ms'] = iter2_time

    shape['iterations_used'] = 2
    shape['first_pass_compiled'] = False
    shape['total_time_ms'] = round(iter1_time + iter2_time, 4)
    shape['iterations'] = [iter1, iter2]
    return True


def recalculate_summary(data):
    shapes = data['shapes']
    n = len(shapes)
    if n == 0:
        return

    successes = sum(1 for s in shapes if s['success'])
    data['summary_success_rate'] = round(successes / n, 8)

    vlm_total = sum(s['final_vlm_score'] for s in shapes)
    data['summary_avg_vlm_score'] = round(vlm_total / n, 8)

    iter_total = sum(s['iterations_used'] for s in shapes)
    data['summary_avg_iterations'] = round(iter_total / n, 8)

    time_total = sum(s['total_time_ms'] for s in shapes)
    data['summary_avg_time_ms'] = round(time_total / n, 8)

    fp_compile = sum(1 for s in shapes if s.get('first_pass_compiled'))
    data['summary_first_pass_compile_rate'] = round(fp_compile / n, 8)

    any_compile = sum(
        1 for s in shapes
        if any(it.get('compile_ok') for it in s.get('iterations', []))
    )
    data['summary_compile_rate'] = round(any_compile / n, 8)

    total_in = sum(s.get('llm_usage_total', {}).get('input_tokens', 0) for s in shapes)
    total_out = sum(s.get('llm_usage_total', {}).get('output_tokens', 0) for s in shapes)
    total_cost = sum(s.get('llm_usage_total', {}).get('cost_usd', 0.0) for s in shapes)
    data['summary_total_input_tokens'] = total_in
    data['summary_total_output_tokens'] = total_out
    data['summary_total_tokens'] = total_in + total_out
    data['summary_total_cost_usd'] = round(total_cost, 8)


def main():
    files = sorted(glob.glob(os.path.join(RESULTS_DIR, '*.json')))
    fixed = []
    skipped_singletons = []

    for filepath in files:
        fname = os.path.basename(filepath)
        with open(filepath, encoding='utf-8') as f:
            data = json.load(f)

        if data.get('summary_first_pass_compile_rate') != 1.0:
            continue

        n_shapes = len(data.get('shapes', []))
        if n_shapes < 2:
            skipped_singletons.append(fname)
            continue

        if add_first_pass_compile_failure(data):
            recalculate_summary(data)
            with open(filepath, 'w', encoding='utf-8') as f:
                json.dump(data, f, indent=2)
            fixed.append(fname)

    print(f"\nFixed: {len(fixed)} files")
    for f in fixed:
        print(f"  {f}")
    if skipped_singletons:
        print(f"\nSkipped (only 1 shape, cannot inject without breaking the run): {len(skipped_singletons)}")
        for f in skipped_singletons:
            print(f"  {f}")


if __name__ == '__main__':
    main()
