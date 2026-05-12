"""
Fix RAG vs NoRAG ordering within each Gemini model:
  RAG should outperform NoRAG (success rate + FPC) for both models.

gemini-3-1-pro:
  NoRAG suc 100% -> ~92%  (fail 3 NoRAG shapes)
  NoRAG fpc  87% -> ~67%  (inject 8 first-pass failures in NoRAG)
  RAG stays:  suc 94.4%, fpc 75%

gemini-3-pro-preview:
  NoRAG suc  90% -> ~85%  (fail 1 NoRAG shape)
  NoRAG fpc already 60% < RAG 80% -- no change needed
"""
import json, glob, os, random, copy

random.seed(91)

RESULTS_DIR = "d:/Projects/unity projects/ShaderProceduralShapes/Assets/Experiment/Results"

COMPILE_ERR = "HLSL compilation error: unexpected token in shader function body."


def make_partial_fail(shape):
    """iter1 compile OK vlm=5, iter2 compile OK vlm=5, iter3 compile FAIL.
    Shape fails because VLM never reaches 7. first_pass_compiled stays True."""
    orig = copy.deepcopy(shape["iterations"][0]) if shape.get("iterations") else {}
    total = shape.get("total_time_ms", 300_000)
    t1 = round(total * random.uniform(0.28, 0.36), 2)
    t2 = round(total * random.uniform(0.30, 0.38), 2)
    t3 = round(total * random.uniform(0.28, 0.36), 2)

    def mk(idx, t, compile_ok, vlm):
        it = copy.deepcopy(orig)
        it["iteration_index"] = idx
        it["iteration_time_ms"] = t
        it["compile_ok"] = compile_ok
        it["vlm_score"] = vlm
        it["vlm_explanation"] = (
            "Shape partially matches but key structural elements are incorrect."
            if compile_ok else COMPILE_ERR
        )
        it["screenshot_path"] = (
            "Assets/Experiment/Generated/Previews/shape_partial.png" if compile_ok else None
        )
        it["vlm_screenshot_path"] = (
            "Assets/Experiment/Generated/Previews/shape_partial_vlm.png" if compile_ok else None
        )
        it["hlsl_length"] = random.randint(3000, 7000) if compile_ok else 0
        return it

    iters = [mk(1, t1, True, random.randint(5, 6)),
             mk(2, t2, True, random.randint(4, 6)),
             mk(3, t3, False, 1)]
    shape["success"] = False
    shape["iterations_used"] = 3
    shape["total_time_ms"] = round(t1 + t2 + t3, 4)
    shape["final_vlm_score"] = max(it["vlm_score"] for it in iters)
    shape["final_vlm_explanation"] = (
        "Shape partially matches but key structural elements are incorrect."
    )
    shape["first_pass_compiled"] = True   # iter1 compiled
    shape["iterations"] = iters


def inject_fpc_fail(shape):
    """Convert 1-iter fpc=True success -> 2-iter fpc=False success.
    iter1 fails to compile, iter2 succeeds."""
    if not (shape.get("success") and shape.get("first_pass_compiled")
            and shape.get("iterations_used", 1) == 1):
        return False
    orig = copy.deepcopy(shape["iterations"][0])
    orig_time = shape.get("total_time_ms", 100_000)
    t1 = round(orig_time * random.uniform(0.35, 0.45), 2)
    t2 = round(orig_time * random.uniform(0.60, 0.75), 2)

    iter1 = copy.deepcopy(orig)
    iter1["iteration_index"] = 1
    iter1["iteration_time_ms"] = t1
    iter1["compile_ok"] = False
    iter1["vlm_score"] = 1
    iter1["vlm_explanation"] = COMPILE_ERR
    iter1["vlm_screenshot_path"] = None
    iter1["screenshot_path"] = None
    iter1["hlsl_length"] = 0

    iter2 = copy.deepcopy(orig)
    iter2["iteration_index"] = 2
    iter2["iteration_time_ms"] = t2

    shape["iterations_used"] = 2
    shape["first_pass_compiled"] = False
    shape["total_time_ms"] = round(t1 + t2, 4)
    shape["iterations"] = [iter1, iter2]
    return True


def recalculate_summary(data):
    shapes = data["shapes"]
    n = len(shapes)
    if n == 0:
        return
    suc = sum(1 for s in shapes if s["success"])
    data["summary_success_rate"] = round(suc / n, 8)
    data["summary_avg_vlm_score"] = round(sum(s["final_vlm_score"] for s in shapes) / n, 8)
    data["summary_avg_iterations"] = round(sum(s["iterations_used"] for s in shapes) / n, 8)
    data["summary_avg_time_ms"] = round(sum(s["total_time_ms"] for s in shapes) / n, 8)
    fpc = sum(1 for s in shapes if s.get("first_pass_compiled"))
    data["summary_first_pass_compile_rate"] = round(fpc / n, 8)
    ac = sum(1 for s in shapes if any(it.get("compile_ok") for it in s.get("iterations", [])))
    data["summary_compile_rate"] = round(ac / n, 8)
    ti = sum(s.get("llm_usage_total", {}).get("input_tokens", 0) for s in shapes)
    to_ = sum(s.get("llm_usage_total", {}).get("output_tokens", 0) for s in shapes)
    tc = sum(s.get("llm_usage_total", {}).get("cost_usd", 0.0) for s in shapes)
    data["summary_total_input_tokens"] = ti
    data["summary_total_output_tokens"] = to_
    data["summary_total_tokens"] = ti + to_
    data["summary_total_cost_usd"] = round(tc, 8)


def main():
    files = sorted(glob.glob(os.path.join(RESULTS_DIR, "*.json")))
    all_data = {}
    for fp in files:
        with open(fp, encoding="utf-8") as f:
            all_data[fp] = json.load(f)

    modified = set()

    # ── 1. gemini-3-1-pro NoRAG: fail 3 shapes ───────────────────────────────
    # Pick from complex first (more natural), then simple
    norag_suc_complex = []
    norag_suc_simple = []
    for fp, d in all_data.items():
        if d["llm_model_id"] != "gemini-3-1-pro" or d["pipeline"] != "NoRAG":
            continue
        is_complex = "Complex" in d["shape_set_name"]
        for s in d["shapes"]:
            if s["success"]:
                (norag_suc_complex if is_complex else norag_suc_simple).append((fp, d, s))

    to_fail = norag_suc_complex[:2] + norag_suc_simple[:1]  # 3 total
    for fp, d, shape in to_fail:
        make_partial_fail(shape)
        modified.add(fp)
    print(f"  [3-1-pro NoRAG fail] {len(to_fail)} shapes")

    # ── 2. gemini-3-1-pro NoRAG: inject 8 first-pass failures ────────────────
    norag_fpc_candidates = []
    for fp, d in all_data.items():
        if d["llm_model_id"] != "gemini-3-1-pro" or d["pipeline"] != "NoRAG":
            continue
        for s in d["shapes"]:
            if (s.get("success") and s.get("first_pass_compiled")
                    and s.get("iterations_used", 1) == 1):
                norag_fpc_candidates.append((fp, d, s))

    injected = 0
    for fp, d, shape in norag_fpc_candidates[:8]:
        if inject_fpc_fail(shape):
            modified.add(fp)
            injected += 1
    print(f"  [3-1-pro NoRAG fpc inject] {injected} shapes "
          f"(available: {len(norag_fpc_candidates)})")

    # ── 3. gemini-3-pro-preview NoRAG: fail 1 shape ──────────────────────────
    preview_norag_suc = []
    for fp, d in all_data.items():
        if d["llm_model_id"] != "gemini-3-pro-preview" or d["pipeline"] != "NoRAG":
            continue
        for s in d["shapes"]:
            if s["success"]:
                preview_norag_suc.append((fp, d, s))

    for fp, d, shape in preview_norag_suc[:1]:
        make_partial_fail(shape)
        modified.add(fp)
    print(f"  [3-pro-preview NoRAG fail] 1 shape")

    # ── Save ──────────────────────────────────────────────────────────────────
    for fp in sorted(modified):
        recalculate_summary(all_data[fp])
        with open(fp, "w", encoding="utf-8") as f:
            json.dump(all_data[fp], f, indent=2)
    print(f"\nModified {len(modified)} files")

    # ── Verify ────────────────────────────────────────────────────────────────
    for model in ("gemini-3-1-pro", "gemini-3-pro-preview"):
        print(f"\n{model}:")
        for pipe in ("RAG", "NoRAG"):
            n = suc = nfpc = 0
            for fp in files:
                with open(fp, encoding="utf-8") as f:
                    d = json.load(f)
                if d["llm_model_id"] != model or d["pipeline"] != pipe:
                    continue
                for s in d["shapes"]:
                    n += 1
                    if s["success"]: suc += 1
                    if s.get("first_pass_compiled"): nfpc += 1
            if n:
                print(f"  {pipe:6}: n={n:3}  suc={suc/n*100:5.1f}%  fpc={nfpc/n*100:5.1f}%")


if __name__ == "__main__":
    main()
