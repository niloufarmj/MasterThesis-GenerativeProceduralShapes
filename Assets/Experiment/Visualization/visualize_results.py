#!/usr/bin/env python3
"""
visualize_results.py
====================
Master Thesis — Generative Procedural Shapes
Reads all experiment JSON files from the results directory and produces a
comprehensive set of charts suitable for academic publication.

Usage
-----
python visualize_results.py \
    --results_dir  "Assets/Experiment/Results" \
    --out_dir      "Assets/Experiment/Visualization/Charts"

All charts are saved as high-resolution PNG (300 dpi) and a combined PDF.
A summary CSV is also written to out_dir/summary_stats.csv.

Requirements
------------
See requirements.txt  (pip install -r requirements.txt)
"""

import argparse
import json
import os
import sys
import warnings
from pathlib import Path

import matplotlib
matplotlib.use("Agg")   # headless back-end, safe in any environment
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
from matplotlib.backends.backend_pdf import PdfPages
import numpy as np
import pandas as pd
import seaborn as sns
from scipy import stats

warnings.filterwarnings("ignore")

# ─── colour palette ──────────────────────────────────────────────────────────
C_RAG    = "#2196F3"   # blue  – Phase 2 (RAG)
C_NORAG  = "#FF9800"   # amber – Phase 1 (No-RAG)
C_SIMPLE = "#4CAF50"   # green – Simple shapes
C_COMPLEX= "#E91E63"   # pink  – Complex shapes
C_IN_KB  = "#9C27B0"   # purple – In-RAG KB
C_OUT_KB = "#607D8B"   # grey  – Out-of-KB
C_OK     = "#43A047"
C_FAIL   = "#E53935"

PALETTE = {
    "RAG": C_RAG, "NoRAG": C_NORAG,
    "Simple": C_SIMPLE, "Complex": C_COMPLEX,
    "In-KB": C_IN_KB, "Out-KB": C_OUT_KB,
    "PropertyChange": "#00BCD4", "HLSLUpdate": "#FF5722"
}

sns.set_theme(style="whitegrid", palette="muted", font_scale=1.1)

# ─── helpers ─────────────────────────────────────────────────────────────────

def load_results(results_dir: Path):
    gen_rows, edit_rows, anim_rows = [], [], []

    for p in sorted(results_dir.glob("*.json")):
        try:
            data = json.loads(p.read_text(encoding="utf-8"))
        except Exception as e:
            print(f"  ⚠  Skipping {p.name}: {e}")
            continue

        etype = data.get("experiment_type", "")

        if etype == "generation":
            pipeline = data.get("pipeline", "Unknown")
            set_name = data.get("shape_set_name", "?")
            code_prov = data.get("code_provider", "?")
            eval_prov = data.get("eval_provider", "?")
            for s in data.get("shapes", []):
                row = {
                    "pipeline":           pipeline,
                    "shape_set":          set_name,
                    "code_provider":      code_prov,
                    "eval_provider":      eval_prov,
                    "prompt":             s.get("prompt", ""),
                    "complexity":         s.get("shape_complexity", "Unknown"),
                    "in_kb":              s.get("in_knowledge_base", False),
                    "success":            int(s.get("success", False)),
                    "iterations_used":    s.get("iterations_used", 0),
                    "total_time_s":       s.get("total_time_ms", 0) / 1000.0,
                    "final_vlm_score":    s.get("final_vlm_score", 0),
                    "human_score":        s.get("human_score", 0),
                    "first_pass_compile": int(s.get("first_pass_compiled", False)),
                    "rag_components":     s.get("rag_components_decomposed", 0),
                    "rag_retrieved":      s.get("rag_retrieved_examples", 0),
                    "rag_avg_sim":        s.get("rag_avg_similarity_score", 0.0),
                }
                # iteration-level compile rate
                iters = s.get("iterations", [])
                row["compile_rate"] = (
                    sum(1 for i in iters if i.get("compile_ok")) / len(iters)
                    if iters else 0.0
                )
                row["iter_scores"]  = [i.get("vlm_score", 0) for i in iters]
                gen_rows.append(row)

        elif etype == "edit":
            for item in data.get("items", []):
                edit_rows.append({
                    "shape_prompt":     item.get("base_shape_prompt", ""),
                    "edit_request":     item.get("edit_request", ""),
                    "edit_type":        item.get("edit_type", "Unknown"),
                    "success":          int(item.get("success", False)),
                    "iterations_used":  item.get("iterations_used", 0),
                    "total_time_s":     item.get("total_time_ms", 0) / 1000.0,
                    "vlm_before":       item.get("vlm_score_before", 0),
                    "vlm_after":        item.get("vlm_score_after", 0),
                    "improvement":      item.get("score_improvement", 0),
                    "human_score":      item.get("human_score", 0),
                })

        elif etype == "animation":
            for item in data.get("items", []):
                anim_rows.append({
                    "shape_prompt":    item.get("base_shape_prompt", ""),
                    "anim_request":    item.get("animation_request", ""),
                    "success":         int(item.get("success", False)),
                    "total_time_s":    item.get("total_time_ms", 0) / 1000.0,
                    "human_score":     item.get("human_score", 0),
                })

    gen_df  = pd.DataFrame(gen_rows)
    edit_df = pd.DataFrame(edit_rows)
    anim_df = pd.DataFrame(anim_rows)
    return gen_df, edit_df, anim_df


def save_fig(fig, out_dir: Path, name: str, pdf: PdfPages):
    fig.tight_layout()
    path = out_dir / f"{name}.png"
    fig.savefig(path, dpi=300, bbox_inches="tight")
    pdf.savefig(fig, bbox_inches="tight")
    plt.close(fig)
    print(f"  ✓ {path.name}")


def fmt_pct(v): return f"{v*100:.1f}%"
def fmt_n(v):   return f"{v:.2f}"


# ─── GENERATION CHARTS ───────────────────────────────────────────────────────

def chart_success_rate_pipeline(df, out_dir, pdf):
    """Bar chart: success rate — RAG vs No-RAG (overall and by complexity)."""
    fig, axes = plt.subplots(1, 2, figsize=(12, 5))

    # left: overall
    order = ["RAG", "NoRAG"]
    rates = [df[df.pipeline == p]["success"].mean() if len(df[df.pipeline == p]) > 0 else 0
             for p in order]
    colors = [PALETTE[p] for p in order]
    bars = axes[0].bar(["Phase 2 (RAG)", "Phase 1 (No-RAG)"], rates, color=colors,
                       width=0.5, edgecolor="white", linewidth=1.5)
    for bar, rate in zip(bars, rates):
        axes[0].text(bar.get_x() + bar.get_width()/2, bar.get_height() + 0.01,
                     fmt_pct(rate), ha="center", va="bottom", fontweight="bold")
    axes[0].set_ylim(0, 1.1)
    axes[0].set_ylabel("Success Rate")
    axes[0].set_title("Overall Success Rate\nPhase 1 vs Phase 2")

    # right: grouped by complexity
    combos = [("Simple","RAG"), ("Simple","NoRAG"), ("Complex","RAG"), ("Complex","NoRAG")]
    labels = ["Simple\nRAG", "Simple\nNo-RAG", "Complex\nRAG", "Complex\nNo-RAG"]
    colors2 = [C_SIMPLE, C_NORAG, C_COMPLEX, C_NORAG]
    rates2 = []
    for comp, pip in combos:
        sub = df[(df.complexity == comp) & (df.pipeline == pip)]
        rates2.append(sub["success"].mean() if len(sub) > 0 else 0)

    bars2 = axes[1].bar(labels, rates2, color=colors2, width=0.5, edgecolor="white", linewidth=1.5)
    for bar, rate in zip(bars2, rates2):
        axes[1].text(bar.get_x() + bar.get_width()/2, bar.get_height() + 0.01,
                     fmt_pct(rate), ha="center", va="bottom", fontweight="bold")
    axes[1].set_ylim(0, 1.1)
    axes[1].set_ylabel("Success Rate")
    axes[1].set_title("Success Rate by Complexity\n& Pipeline")

    fig.suptitle("Figure 1 — Generation Success Rate Comparison", fontsize=13, fontweight="bold")
    save_fig(fig, out_dir, "01_success_rate_pipeline", pdf)


def chart_vlm_score_distribution(df, out_dir, pdf):
    """Box plot + strip: VLM score distribution by pipeline × complexity."""
    fig, ax = plt.subplots(figsize=(10, 6))
    plot_df = df[["pipeline","complexity","final_vlm_score"]].copy()
    plot_df["Group"] = plot_df["pipeline"] + " / " + plot_df["complexity"]
    order = ["RAG / Simple", "NoRAG / Simple", "RAG / Complex", "NoRAG / Complex"]
    colors_map = {"RAG / Simple": C_RAG, "NoRAG / Simple": C_NORAG,
                  "RAG / Complex": C_RAG, "NoRAG / Complex": C_NORAG}
    palette_list = [colors_map.get(g, "#888") for g in order]

    sns.boxplot(data=plot_df[plot_df.Group.isin(order)], x="Group", y="final_vlm_score",
                order=order, palette=palette_list, width=0.5, ax=ax,
                flierprops={"marker":"o","markersize":4,"alpha":0.5})
    sns.stripplot(data=plot_df[plot_df.Group.isin(order)], x="Group", y="final_vlm_score",
                  order=order, color="black", alpha=0.35, size=3.5, jitter=True, ax=ax)
    ax.axhline(7, color="#E53935", linestyle="--", linewidth=1.5, label="Success threshold (7)")
    ax.set_ylim(0, 11)
    ax.set_ylabel("Final VLM Score (1–10)")
    ax.set_xlabel("")
    ax.set_title("Figure 2 — VLM Score Distribution by Pipeline & Complexity", fontweight="bold")
    ax.legend()
    save_fig(fig, out_dir, "02_vlm_score_distribution", pdf)


def chart_avg_iterations(df, out_dir, pdf):
    """Bar chart: average iterations to success."""
    fig, ax = plt.subplots(figsize=(8, 5))
    success_df = df[df.success == 1]
    combos = [("RAG","Simple"), ("RAG","Complex"), ("NoRAG","Simple"), ("NoRAG","Complex")]
    labels = ["RAG\nSimple", "RAG\nComplex", "No-RAG\nSimple", "No-RAG\nComplex"]
    colors = [C_RAG, C_RAG, C_NORAG, C_NORAG]
    means, sems = [], []
    for pip, comp in combos:
        sub = success_df[(success_df.pipeline == pip) & (success_df.complexity == comp)]
        if len(sub) > 0:
            means.append(sub.iterations_used.mean())
            sems.append(sub.iterations_used.sem() if len(sub) > 1 else 0)
        else:
            means.append(0); sems.append(0)

    bars = ax.bar(labels, means, color=colors, width=0.45, edgecolor="white",
                  yerr=sems, capsize=4, error_kw={"elinewidth":1.5})
    for bar, m in zip(bars, means):
        if m > 0:
            ax.text(bar.get_x() + bar.get_width()/2, bar.get_height() + 0.05,
                    f"{m:.2f}", ha="center", va="bottom", fontsize=9)
    ax.set_ylabel("Avg Iterations to Success (±SEM)")
    ax.set_title("Figure 3 — Average Iterations to Reach Success", fontweight="bold")
    ax.set_ylim(0, max(means or [1]) * 1.4 + 0.5)
    handles = [mpatches.Patch(color=C_RAG, label="RAG (Phase 2)"),
               mpatches.Patch(color=C_NORAG, label="No-RAG (Phase 1)")]
    ax.legend(handles=handles)
    save_fig(fig, out_dir, "03_avg_iterations", pdf)


def chart_time_violin(df, out_dir, pdf):
    """Violin plot: generation time distribution."""
    fig, ax = plt.subplots(figsize=(10, 6))
    plot_df = df[["pipeline","complexity","total_time_s"]].copy()
    plot_df["Group"] = plot_df["pipeline"] + "\n" + plot_df["complexity"]
    order = ["RAG\nSimple", "RAG\nComplex", "NoRAG\nSimple", "NoRAG\nComplex"]
    colors_map = {"RAG\nSimple": C_RAG, "RAG\nComplex": "#1565C0",
                  "NoRAG\nSimple": C_NORAG, "NoRAG\nComplex": "#E65100"}
    palette_list = [colors_map.get(g, "#888") for g in order]

    sub = plot_df[plot_df.Group.isin(order)]
    if len(sub) > 1:
        sns.violinplot(data=sub, x="Group", y="total_time_s", order=order,
                       palette=palette_list, cut=0, inner="box", ax=ax)
    else:
        ax.text(0.5, 0.5, "Insufficient data for violin plot",
                ha="center", va="center", transform=ax.transAxes)
    ax.set_ylabel("Total Generation Time (s)")
    ax.set_xlabel("")
    ax.set_title("Figure 4 — Generation Time Distribution (Violin)", fontweight="bold")
    save_fig(fig, out_dir, "04_time_violin", pdf)


def chart_compile_rate(df, out_dir, pdf):
    """Bar chart: first-pass compile success rate."""
    fig, ax = plt.subplots(figsize=(9, 5))
    groups = [("RAG","Simple"), ("RAG","Complex"), ("NoRAG","Simple"), ("NoRAG","Complex")]
    labels = ["RAG / Simple", "RAG / Complex", "No-RAG / Simple", "No-RAG / Complex"]
    colors = [C_RAG, C_RAG, C_NORAG, C_NORAG]
    rates = []
    for pip, comp in groups:
        sub = df[(df.pipeline == pip) & (df.complexity == comp)]
        rates.append(sub.first_pass_compile.mean() if len(sub) > 0 else 0)

    bars = ax.bar(labels, rates, color=colors, width=0.45, edgecolor="white", linewidth=1.5)
    for bar, rate in zip(bars, rates):
        ax.text(bar.get_x() + bar.get_width()/2, bar.get_height() + 0.01,
                fmt_pct(rate), ha="center", va="bottom", fontweight="bold")
    ax.set_ylim(0, 1.15)
    ax.set_ylabel("First-Pass Compile Rate")
    ax.set_title("Figure 5 — First-Pass HLSL Compile Success Rate", fontweight="bold")
    ax.legend(handles=[mpatches.Patch(color=C_RAG, label="Phase 2 (RAG)"),
                        mpatches.Patch(color=C_NORAG, label="Phase 1 (No-RAG)")])
    save_fig(fig, out_dir, "05_compile_rate", pdf)


def chart_score_vs_time_scatter(df, out_dir, pdf):
    """Scatter plot: VLM score vs generation time, coloured by pipeline."""
    fig, ax = plt.subplots(figsize=(9, 6))
    for pip, color, label in [("RAG", C_RAG, "Phase 2 (RAG)"),
                                ("NoRAG", C_NORAG, "Phase 1 (No-RAG)")]:
        sub = df[df.pipeline == pip]
        if len(sub) == 0: continue
        ax.scatter(sub.total_time_s, sub.final_vlm_score, c=color, alpha=0.55,
                   s=50, label=label, edgecolors="white", linewidths=0.5)
        # trend line
        if len(sub) > 2:
            m, b, r, p, _ = stats.linregress(sub.total_time_s, sub.final_vlm_score)
            xs = np.linspace(sub.total_time_s.min(), sub.total_time_s.max(), 100)
            ax.plot(xs, m*xs + b, color=color, linewidth=2, linestyle="--", alpha=0.8)

    ax.axhline(7, color="#E53935", linestyle=":", linewidth=1.5, label="Success threshold")
    ax.set_xlabel("Total Generation Time (s)")
    ax.set_ylabel("Final VLM Score (1–10)")
    ax.set_title("Figure 6 — VLM Score vs Generation Time", fontweight="bold")
    ax.legend()
    save_fig(fig, out_dir, "06_score_vs_time_scatter", pdf)


def chart_score_histogram(df, out_dir, pdf):
    """Overlapping histograms: VLM score distribution for RAG vs No-RAG."""
    fig, ax = plt.subplots(figsize=(9, 5))
    bins = range(1, 12)
    for pip, color, label in [("RAG", C_RAG, "Phase 2 (RAG)"),
                                ("NoRAG", C_NORAG, "Phase 1 (No-RAG)")]:
        sub = df[df.pipeline == pip]["final_vlm_score"]
        if len(sub) == 0: continue
        ax.hist(sub, bins=bins, color=color, alpha=0.55, label=label, edgecolor="white")
    ax.axvline(7, color="#E53935", linestyle="--", linewidth=1.5, label="Success threshold (7)")
    ax.set_xlabel("Final VLM Score (1–10)")
    ax.set_ylabel("Count")
    ax.set_title("Figure 7 — VLM Score Frequency Distribution", fontweight="bold")
    ax.legend()
    save_fig(fig, out_dir, "07_score_histogram", pdf)


def chart_in_kb_comparison(df, out_dir, pdf):
    """Bar chart: In-KB vs Out-of-KB shapes — success rate and avg VLM score (RAG only)."""
    rag_df = df[df.pipeline == "RAG"]
    if len(rag_df) == 0:
        print("  ⚠  No RAG data — skipping In-KB comparison chart.")
        return

    fig, axes = plt.subplots(1, 2, figsize=(11, 5))

    for ax, metric, ylabel, title_suffix in [
        (axes[0], "success", "Success Rate", "Success Rate"),
        (axes[1], "final_vlm_score", "Avg VLM Score", "Avg VLM Score")
    ]:
        in_kb  = rag_df[rag_df.in_kb == True][metric]
        out_kb = rag_df[rag_df.in_kb == False][metric]

        if metric == "success":
            vals = [in_kb.mean() if len(in_kb) > 0 else 0,
                    out_kb.mean() if len(out_kb) > 0 else 0]
            errs = [0, 0]
        else:
            vals = [in_kb.mean() if len(in_kb) > 0 else 0,
                    out_kb.mean() if len(out_kb) > 0 else 0]
            errs = [in_kb.sem() if len(in_kb) > 1 else 0,
                    out_kb.sem() if len(out_kb) > 1 else 0]

        bars = ax.bar(["In-KB", "Out-of-KB"], vals, color=[C_IN_KB, C_OUT_KB],
                      width=0.4, edgecolor="white", yerr=errs, capsize=5)
        for bar, v in zip(bars, vals):
            label = fmt_pct(v) if metric == "success" else fmt_n(v)
            ax.text(bar.get_x() + bar.get_width()/2, bar.get_height() + (0.01 if metric=="success" else 0.05),
                    label, ha="center", va="bottom", fontweight="bold")

        if metric == "success":
            ax.set_ylim(0, 1.15)
        else:
            ax.set_ylim(0, 11)
        ax.set_ylabel(ylabel)
        ax.set_title(f"RAG — {title_suffix}\nIn-KB vs Out-of-KB")
        n_in  = len(in_kb)
        n_out = len(out_kb)
        ax.set_xlabel(f"(n_in={n_in}, n_out={n_out})")

    fig.suptitle("Figure 8 — Impact of Knowledge-Base Coverage (RAG Only)",
                 fontsize=13, fontweight="bold")
    save_fig(fig, out_dir, "08_in_kb_comparison", pdf)


def chart_rag_similarity_vs_score(df, out_dir, pdf):
    """Scatter: RAG retrieval similarity vs final VLM score."""
    rag_df = df[(df.pipeline == "RAG") & (df.rag_avg_sim > 0)]
    if len(rag_df) < 3:
        print("  ⚠  Insufficient RAG similarity data — skipping chart.")
        return

    fig, ax = plt.subplots(figsize=(8, 6))
    sc = ax.scatter(rag_df.rag_avg_sim, rag_df.final_vlm_score,
                    c=rag_df.complexity.map({"Simple": C_SIMPLE, "Complex": C_COMPLEX}).fillna("#888"),
                    s=60, alpha=0.65, edgecolors="white", linewidths=0.5)
    if len(rag_df) > 2:
        m, b, r, p, _ = stats.linregress(rag_df.rag_avg_sim, rag_df.final_vlm_score)
        xs = np.linspace(rag_df.rag_avg_sim.min(), rag_df.rag_avg_sim.max(), 100)
        ax.plot(xs, m*xs + b, color=C_RAG, linewidth=2, linestyle="--",
                label=f"Trend  r={r:.2f}  p={p:.3f}")

    ax.axhline(7, color="#E53935", linestyle=":", linewidth=1.2, label="Success threshold")
    ax.set_xlabel("Avg RAG Retrieval Similarity Score")
    ax.set_ylabel("Final VLM Score")
    ax.set_title("Figure 9 — Retrieval Similarity vs Generation Quality (RAG)", fontweight="bold")
    handles = [mpatches.Patch(color=C_SIMPLE, label="Simple"),
               mpatches.Patch(color=C_COMPLEX, label="Complex")]
    ax.legend(handles=handles + ax.get_lines())
    save_fig(fig, out_dir, "09_rag_similarity_vs_score", pdf)


def chart_rag_components(df, out_dir, pdf):
    """Bar chart: number of decomposed components vs success rate (RAG only)."""
    rag_df = df[df.pipeline == "RAG"]
    if len(rag_df) == 0 or rag_df.rag_components.max() == 0:
        print("  ⚠  No RAG component data — skipping chart.")
        return

    comp_groups = rag_df.groupby("rag_components")["success"].agg(["mean","count"])
    comp_groups = comp_groups[comp_groups["count"] >= 1]

    fig, ax = plt.subplots(figsize=(9, 5))
    ax.bar(comp_groups.index.astype(str), comp_groups["mean"],
           color=C_RAG, width=0.5, edgecolor="white")
    for x, (_, row) in zip(comp_groups.index, comp_groups.iterrows()):
        ax.text(str(x), row["mean"] + 0.01, fmt_pct(row["mean"]),
                ha="center", va="bottom", fontsize=9)
    ax.set_ylim(0, 1.2)
    ax.set_xlabel("Number of Decomposed Components")
    ax.set_ylabel("Success Rate")
    ax.set_title("Figure 10 — RAG: Decomposition Complexity vs Success Rate", fontweight="bold")
    save_fig(fig, out_dir, "10_rag_components_vs_success", pdf)


def chart_iteration_convergence(df, out_dir, pdf):
    """Line chart: average VLM score per iteration number (convergence curve)."""
    max_iter = 6
    fig, ax = plt.subplots(figsize=(9, 6))

    for pip, color, label in [("RAG", C_RAG, "Phase 2 (RAG)"),
                                ("NoRAG", C_NORAG, "Phase 1 (No-RAG)")]:
        sub = df[df.pipeline == pip]
        iter_scores = {i: [] for i in range(1, max_iter + 1)}
        for _, row in sub.iterrows():
            for idx, score in enumerate(row.get("iter_scores", []), start=1):
                if idx <= max_iter:
                    iter_scores[idx].append(score)
        xs, ys, errs = [], [], []
        for i in range(1, max_iter + 1):
            scores = iter_scores[i]
            if len(scores) > 0:
                xs.append(i)
                ys.append(np.mean(scores))
                errs.append(np.std(scores) / np.sqrt(len(scores)))
        if xs:
            ax.plot(xs, ys, marker="o", color=color, linewidth=2, label=label, markersize=7)
            ax.fill_between(xs,
                             [y - e for y, e in zip(ys, errs)],
                             [y + e for y, e in zip(ys, errs)],
                             color=color, alpha=0.15)

    ax.axhline(7, color="#E53935", linestyle="--", linewidth=1.5, label="Success threshold")
    ax.set_xlabel("Iteration Number")
    ax.set_ylabel("Avg VLM Score (±1 SEM)")
    ax.set_xticks(range(1, max_iter + 1))
    ax.set_ylim(0, 11)
    ax.set_title("Figure 11 — Score Convergence Across Iterations", fontweight="bold")
    ax.legend()
    save_fig(fig, out_dir, "11_iteration_convergence", pdf)


def chart_model_comparison_heatmap(df, out_dir, pdf):
    """Heatmap: (code_provider × eval_provider) vs success rate."""
    if len(df) == 0: return

    pivot = df.groupby(["code_provider","eval_provider"])["success"].mean().unstack(fill_value=0)
    if pivot.empty:
        print("  ⚠  Not enough provider variation for heatmap — skipping.")
        return

    fig, ax = plt.subplots(figsize=(7, 5))
    sns.heatmap(pivot, annot=True, fmt=".2f", cmap="YlOrRd", vmin=0, vmax=1,
                linewidths=0.5, ax=ax, annot_kws={"size": 12, "fontweight": "bold"})
    ax.set_xlabel("Eval Provider")
    ax.set_ylabel("Code Provider")
    ax.set_title("Figure 12 — Success Rate by Provider Combination", fontweight="bold")
    save_fig(fig, out_dir, "12_model_heatmap", pdf)


def chart_vlm_vs_human_scatter(df, out_dir, pdf):
    """Scatter: VLM score vs Human score (only rows where human_score > 0)."""
    scored = df[df.human_score > 0]
    if len(scored) < 3:
        print("  ⚠  Insufficient human scores — skipping VLM vs Human chart.")
        return

    fig, ax = plt.subplots(figsize=(7, 6))
    for pip, color, marker in [("RAG", C_RAG, "o"), ("NoRAG", C_NORAG, "s")]:
        sub = scored[scored.pipeline == pip]
        if len(sub) == 0: continue
        ax.scatter(sub.final_vlm_score, sub.human_score, c=color, marker=marker,
                   s=60, alpha=0.7, label=pip, edgecolors="white")

    all_scores = pd.concat([scored.final_vlm_score, scored.human_score])
    lo, hi = all_scores.min() - 0.5, all_scores.max() + 0.5
    ax.plot([lo, hi], [lo, hi], "k--", linewidth=1, alpha=0.4, label="Perfect agreement")
    if len(scored) > 2:
        m, b, r, p, _ = stats.linregress(scored.final_vlm_score, scored.human_score)
        xs = np.linspace(scored.final_vlm_score.min(), scored.final_vlm_score.max(), 100)
        ax.plot(xs, m*xs + b, color="gray", linewidth=2, linestyle="-.",
                label=f"Regression r={r:.2f}")
    ax.set_xlabel("VLM Score (automated)")
    ax.set_ylabel("Human Score")
    ax.set_title("Figure 13 — VLM Score vs Human Evaluation", fontweight="bold")
    ax.legend()
    save_fig(fig, out_dir, "13_vlm_vs_human", pdf)


def chart_phase_comparison_summary(df, out_dir, pdf):
    """Side-by-side bar chart: 4 key metrics comparing Phase 1 vs Phase 2."""
    metrics = [
        ("success",          "Success Rate",           True),
        ("final_vlm_score",  "Avg VLM Score",          False),
        ("total_time_s",     "Avg Gen Time (s)",        False),
        ("first_pass_compile","1st-Pass Compile Rate",  True),
    ]

    fig, axes = plt.subplots(2, 2, figsize=(12, 9))
    axes = axes.flatten()

    for ax, (col, ylabel, is_rate) in zip(axes, metrics):
        values, labels, colors = [], [], []
        for pip, label, color in [("RAG", "Phase 2\n(RAG)", C_RAG),
                                   ("NoRAG", "Phase 1\n(No-RAG)", C_NORAG)]:
            sub = df[df.pipeline == pip][col]
            if len(sub) == 0:
                continue
            values.append(sub.mean())
            labels.append(label)
            colors.append(color)

        if not values: continue
        bars = ax.bar(labels, values, color=colors, width=0.4, edgecolor="white", linewidth=1.5)
        for bar, v in zip(bars, values):
            text = fmt_pct(v) if is_rate else f"{v:.2f}"
            ax.text(bar.get_x() + bar.get_width()/2, bar.get_height() * 1.03,
                    text, ha="center", va="bottom", fontweight="bold", fontsize=11)
        if is_rate:
            ax.set_ylim(0, 1.2)
        ax.set_ylabel(ylabel)
        ax.set_title(ylabel)

    fig.suptitle("Figure 14 — Phase 1 vs Phase 2 Key Metrics Summary",
                 fontsize=13, fontweight="bold")
    save_fig(fig, out_dir, "14_phase_comparison_summary", pdf)


def chart_correlation_heatmap(df, out_dir, pdf):
    """Correlation heatmap of numeric generation metrics."""
    numeric_cols = [
        "success", "iterations_used", "total_time_s", "final_vlm_score",
        "first_pass_compile", "rag_components", "rag_retrieved", "rag_avg_sim",
        "compile_rate", "human_score"
    ]
    avail = [c for c in numeric_cols if c in df.columns]
    sub = df[avail].dropna()

    if sub.shape[0] < 5 or sub.shape[1] < 3:
        print("  ⚠  Insufficient data for correlation heatmap — skipping.")
        return

    corr = sub.corr()
    fig, ax = plt.subplots(figsize=(10, 8))
    mask = np.triu(np.ones_like(corr, dtype=bool))
    sns.heatmap(corr, mask=mask, annot=True, fmt=".2f", cmap="coolwarm",
                center=0, linewidths=0.5, ax=ax, annot_kws={"size": 8})
    ax.set_title("Figure 15 — Metric Correlation Heatmap (Generation)", fontweight="bold")
    save_fig(fig, out_dir, "15_correlation_heatmap", pdf)


# ─── EDIT CHARTS ─────────────────────────────────────────────────────────────

def chart_edit_type_distribution(edit_df, out_dir, pdf):
    """Pie chart: edit type distribution."""
    if len(edit_df) == 0: return
    counts = edit_df["edit_type"].value_counts()
    if len(counts) == 0: return

    fig, axes = plt.subplots(1, 2, figsize=(12, 5))

    # Pie
    colors = [PALETTE.get(t, "#888") for t in counts.index]
    axes[0].pie(counts.values, labels=counts.index, colors=colors,
                autopct="%1.1f%%", startangle=90,
                wedgeprops={"edgecolor":"white","linewidth":2})
    axes[0].set_title("Edit Type Distribution")

    # Success rate by edit type
    success_by_type = edit_df.groupby("edit_type")["success"].mean()
    bars = axes[1].bar(success_by_type.index, success_by_type.values,
                       color=[PALETTE.get(t, "#888") for t in success_by_type.index],
                       width=0.4, edgecolor="white")
    for bar, v in zip(bars, success_by_type.values):
        axes[1].text(bar.get_x() + bar.get_width()/2, bar.get_height() + 0.01,
                     fmt_pct(v), ha="center", va="bottom", fontweight="bold")
    axes[1].set_ylim(0, 1.15)
    axes[1].set_ylabel("Success Rate")
    axes[1].set_title("Edit Success Rate by Type")

    fig.suptitle("Figure 16 — Edit Pipeline: Type Distribution & Success Rate",
                 fontsize=13, fontweight="bold")
    save_fig(fig, out_dir, "16_edit_type_distribution", pdf)


def chart_edit_score_improvement(edit_df, out_dir, pdf):
    """Grouped bar chart: VLM score before vs after edit, by edit type."""
    if len(edit_df) == 0: return

    fig, axes = plt.subplots(1, 2, figsize=(12, 5))

    # Before vs after per type
    for ax, grouped_by, title_suffix in [
        (axes[0], "edit_type", "by Edit Type"),
        (axes[1], "success",   "Success vs Failure")
    ]:
        if grouped_by == "success":
            edit_df["success_label"] = edit_df["success"].map({1: "Success", 0: "Failure"})
            grouped_by = "success_label"

        groups = edit_df[grouped_by].unique()
        x = np.arange(len(groups))
        width = 0.3
        bars1 = ax.bar(x - width/2,
                        [edit_df[edit_df[grouped_by] == g]["vlm_before"].mean() for g in groups],
                        width, label="Before", color="#78909C", edgecolor="white")
        bars2 = ax.bar(x + width/2,
                        [edit_df[edit_df[grouped_by] == g]["vlm_after"].mean() for g in groups],
                        width, label="After", color="#26A69A", edgecolor="white")
        ax.set_xticks(x)
        ax.set_xticklabels(groups)
        ax.set_ylim(0, 11)
        ax.axhline(7, color="#E53935", linestyle="--", linewidth=1.2)
        ax.set_ylabel("Avg VLM Score")
        ax.set_title(f"Before vs After {title_suffix}")
        ax.legend()

    fig.suptitle("Figure 17 — Edit Pipeline: VLM Score Before vs After",
                 fontsize=13, fontweight="bold")
    save_fig(fig, out_dir, "17_edit_score_improvement", pdf)


def chart_edit_improvement_dist(edit_df, out_dir, pdf):
    """Histogram + KDE: score improvement distribution."""
    if len(edit_df) == 0: return

    fig, ax = plt.subplots(figsize=(9, 5))
    for et, color in [("PropertyChange", PALETTE["PropertyChange"]),
                       ("HLSLUpdate", PALETTE["HLSLUpdate"])]:
        sub = edit_df[edit_df.edit_type == et]["improvement"].dropna()
        if len(sub) < 2: continue
        ax.hist(sub, bins=range(-5, 11), alpha=0.55, color=color, label=et, edgecolor="white")

    ax.axvline(0, color="black", linewidth=1.2, linestyle="-", label="No change")
    ax.set_xlabel("VLM Score Improvement (After − Before)")
    ax.set_ylabel("Count")
    ax.set_title("Figure 18 — Edit Score Improvement Distribution", fontweight="bold")
    ax.legend()
    save_fig(fig, out_dir, "18_edit_improvement_dist", pdf)


def chart_edit_time_by_type(edit_df, out_dir, pdf):
    """Box plot: edit time by edit type."""
    if len(edit_df) == 0: return

    fig, ax = plt.subplots(figsize=(7, 5))
    types = [t for t in ["PropertyChange", "HLSLUpdate"] if t in edit_df.edit_type.values]
    if not types:
        return
    palette_list = [PALETTE.get(t, "#888") for t in types]
    sns.boxplot(data=edit_df[edit_df.edit_type.isin(types)],
                x="edit_type", y="total_time_s", order=types,
                palette=palette_list, width=0.4, ax=ax)
    sns.stripplot(data=edit_df[edit_df.edit_type.isin(types)],
                  x="edit_type", y="total_time_s", order=types,
                  color="black", alpha=0.4, size=4, jitter=True, ax=ax)
    ax.set_xlabel("Edit Type")
    ax.set_ylabel("Total Edit Time (s)")
    ax.set_title("Figure 19 — Edit Time by Edit Type", fontweight="bold")
    save_fig(fig, out_dir, "19_edit_time_by_type", pdf)


# ─── ANIMATION CHARTS ────────────────────────────────────────────────────────

def chart_animation_results(anim_df, out_dir, pdf):
    """Bar chart: animation success rate + time distribution."""
    if len(anim_df) == 0:
        print("  ⚠  No animation data — skipping animation charts.")
        return

    fig, axes = plt.subplots(1, 2, figsize=(11, 5))

    # Success rate
    rate = anim_df["success"].mean()
    axes[0].bar(["Animation\nGeneration"], [rate], color=C_RAG, width=0.35, edgecolor="white")
    axes[0].text(0, rate + 0.02, fmt_pct(rate), ha="center", va="bottom",
                 fontweight="bold", fontsize=13)
    axes[0].set_ylim(0, 1.2)
    axes[0].set_ylabel("Success Rate")
    axes[0].set_title("Animation Pipeline Success Rate")

    # Time distribution
    axes[1].hist(anim_df["total_time_s"], bins=10, color=C_RAG, edgecolor="white", alpha=0.8)
    axes[1].axvline(anim_df["total_time_s"].mean(), color="#E53935",
                    linestyle="--", linewidth=2, label=f"Mean {anim_df['total_time_s'].mean():.1f}s")
    axes[1].set_xlabel("Generation Time (s)")
    axes[1].set_ylabel("Count")
    axes[1].set_title("Animation Script Generation Time")
    axes[1].legend()

    fig.suptitle("Figure 20 — Animation Pipeline: Success Rate & Generation Time",
                 fontsize=13, fontweight="bold")
    save_fig(fig, out_dir, "20_animation_results", pdf)


def chart_animation_human_scores(anim_df, out_dir, pdf):
    """Bar chart: human score distribution for animations."""
    scored = anim_df[anim_df.human_score > 0]
    if len(scored) < 2: return

    fig, ax = plt.subplots(figsize=(8, 5))
    counts = scored["human_score"].value_counts().sort_index()
    ax.bar(counts.index.astype(str), counts.values, color=C_RAG, width=0.5, edgecolor="white")
    ax.axvline(str(7), color="#E53935", linestyle="--", linewidth=1.5, label="Threshold (7)")
    ax.set_xlabel("Human Score (1–10)")
    ax.set_ylabel("Count")
    ax.set_title("Figure 21 — Animation: Human Score Distribution", fontweight="bold")
    ax.legend()
    save_fig(fig, out_dir, "21_animation_human_scores", pdf)


# ─── COMBINED / SUMMARY CHARTS ───────────────────────────────────────────────

def chart_radar_pipeline_comparison(df, out_dir, pdf):
    """Radar / spider chart: multi-metric comparison of RAG vs No-RAG."""
    metrics_def = [
        ("success",              "Success Rate",    True),
        ("first_pass_compile",   "1st-Pass Compile",True),
        ("final_vlm_score",      "Avg VLM Score",   False, 10),
        ("iterations_used",      "Iter Efficiency", False, 6),
    ]

    def normalise(val, is_rate, max_val=None):
        if is_rate: return float(val)
        return float(val) / (max_val or 1.0)

    cats = []
    vals_rag, vals_norag = [], []
    for m in metrics_def:
        col, label = m[0], m[1]
        is_rate = m[2]
        max_val = m[3] if len(m) > 3 else None

        cats.append(label)
        rag_sub   = df[df.pipeline == "RAG"][col]
        norag_sub = df[df.pipeline == "NoRAG"][col]

        # For iterations, lower is better — invert
        if col == "iterations_used":
            v_rag   = 1 - normalise(rag_sub.mean()   if len(rag_sub)   > 0 else 0, False, max_val)
            v_norag = 1 - normalise(norag_sub.mean() if len(norag_sub) > 0 else 0, False, max_val)
        else:
            v_rag   = normalise(rag_sub.mean()   if len(rag_sub)   > 0 else 0, is_rate, max_val)
            v_norag = normalise(norag_sub.mean() if len(norag_sub) > 0 else 0, is_rate, max_val)
        vals_rag.append(v_rag)
        vals_norag.append(v_norag)

    N = len(cats)
    if N == 0: return

    angles = [n / float(N) * 2 * np.pi for n in range(N)]
    angles += angles[:1]
    vals_rag   += vals_rag[:1]
    vals_norag += vals_norag[:1]

    fig, ax = plt.subplots(figsize=(7, 7), subplot_kw={"polar": True})
    ax.plot(angles, vals_rag,   color=C_RAG,   linewidth=2.5, linestyle="-",  label="Phase 2 (RAG)")
    ax.fill(angles, vals_rag,   color=C_RAG,   alpha=0.2)
    ax.plot(angles, vals_norag, color=C_NORAG, linewidth=2.5, linestyle="--", label="Phase 1 (No-RAG)")
    ax.fill(angles, vals_norag, color=C_NORAG, alpha=0.2)
    ax.set_xticks(angles[:-1])
    ax.set_xticklabels(cats, fontsize=11)
    ax.set_ylim(0, 1)
    ax.set_yticks([0.25, 0.5, 0.75, 1.0])
    ax.set_yticklabels(["0.25","0.5","0.75","1.0"], fontsize=8)
    ax.set_title("Figure 22 — Radar: Phase 1 vs Phase 2\nNormalised Metrics",
                 fontweight="bold", pad=20)
    ax.legend(loc="upper right", bbox_to_anchor=(1.35, 1.1))
    save_fig(fig, out_dir, "22_radar_pipeline_comparison", pdf)


def chart_all_experiment_types_summary(gen_df, edit_df, anim_df, out_dir, pdf):
    """Overview bar chart summarising success rates across all 3 experiment types."""
    labels, rates, colors = [], [], []

    if len(gen_df) > 0:
        for pip, color, label in [("RAG", C_RAG, "Generation\n(Phase 2 RAG)"),
                                   ("NoRAG", C_NORAG, "Generation\n(Phase 1 No-RAG)")]:
            sub = gen_df[gen_df.pipeline == pip]
            if len(sub) > 0:
                labels.append(label)
                rates.append(sub.success.mean())
                colors.append(color)

    if len(edit_df) > 0:
        labels.append("Edit\n(Phase 2 only)")
        rates.append(edit_df.success.mean())
        colors.append("#00BCD4")

    if len(anim_df) > 0:
        labels.append("Animation\n(Phase 2 only)")
        rates.append(anim_df.success.mean())
        colors.append("#8BC34A")

    if not labels:
        print("  ⚠  No data for overview chart.")
        return

    fig, ax = plt.subplots(figsize=(10, 6))
    bars = ax.bar(labels, rates, color=colors, width=0.5, edgecolor="white", linewidth=1.5)
    for bar, rate in zip(bars, rates):
        ax.text(bar.get_x() + bar.get_width()/2, bar.get_height() + 0.01,
                fmt_pct(rate), ha="center", va="bottom", fontweight="bold", fontsize=12)
    ax.set_ylim(0, 1.2)
    ax.set_ylabel("Success Rate")
    ax.set_title("Figure 23 — Overall Success Rate: All Experiment Types",
                 fontsize=13, fontweight="bold")
    ax.axhline(0.75, color="#4CAF50", linestyle=":", linewidth=1.5,
               label="Illustrative 75% baseline")
    ax.legend()
    save_fig(fig, out_dir, "23_all_experiments_summary", pdf)


# ─── SUMMARY CSV ─────────────────────────────────────────────────────────────

def write_summary_csv(gen_df, edit_df, anim_df, out_dir):
    rows = []

    if len(gen_df) > 0:
        for pip in gen_df.pipeline.unique():
            for comp in gen_df.complexity.unique():
                sub = gen_df[(gen_df.pipeline == pip) & (gen_df.complexity == comp)]
                if len(sub) == 0: continue
                rows.append({
                    "experiment": "generation",
                    "pipeline": pip,
                    "complexity": comp,
                    "n": len(sub),
                    "success_rate": sub.success.mean(),
                    "avg_vlm_score": sub.final_vlm_score.mean(),
                    "avg_iterations": sub.iterations_used.mean(),
                    "avg_time_s": sub.total_time_s.mean(),
                    "compile_rate": sub.first_pass_compile.mean(),
                    "avg_human_score": sub[sub.human_score > 0].human_score.mean()
                        if any(sub.human_score > 0) else None,
                })

    if len(edit_df) > 0:
        for et in edit_df.edit_type.unique():
            sub = edit_df[edit_df.edit_type == et]
            rows.append({
                "experiment": "edit",
                "pipeline": "RAG",
                "complexity": et,
                "n": len(sub),
                "success_rate": sub.success.mean(),
                "avg_vlm_score": sub.vlm_after.mean(),
                "avg_iterations": sub.iterations_used.mean(),
                "avg_time_s": sub.total_time_s.mean(),
                "compile_rate": None,
                "avg_human_score": sub[sub.human_score > 0].human_score.mean()
                    if any(sub.human_score > 0) else None,
            })

    if len(anim_df) > 0:
        rows.append({
            "experiment": "animation",
            "pipeline": "RAG",
            "complexity": "N/A",
            "n": len(anim_df),
            "success_rate": anim_df.success.mean(),
            "avg_vlm_score": None,
            "avg_iterations": None,
            "avg_time_s": anim_df.total_time_s.mean(),
            "compile_rate": None,
            "avg_human_score": anim_df[anim_df.human_score > 0].human_score.mean()
                if any(anim_df.human_score > 0) else None,
        })

    csv_path = out_dir / "summary_stats.csv"
    pd.DataFrame(rows).to_csv(csv_path, index=False, float_format="%.4f")
    print(f"  ✓ {csv_path.name}")


# ─── MAIN ────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="Visualise Phase 2 Experiment Results")
    parser.add_argument("--results_dir", type=Path,
                        default=Path("Assets/Experiment/Results"),
                        help="Directory containing JSON result files")
    parser.add_argument("--out_dir", type=Path,
                        default=Path("Assets/Experiment/Visualization/Charts"),
                        help="Output directory for charts and CSV")
    args = parser.parse_args()

    if not args.results_dir.exists():
        print(f"Results directory not found: {args.results_dir}")
        sys.exit(1)

    args.out_dir.mkdir(parents=True, exist_ok=True)

    print(f"\n{'='*60}")
    print("  Thesis Experiment Visualizer")
    print(f"  Results : {args.results_dir.resolve()}")
    print(f"  Output  : {args.out_dir.resolve()}")
    print(f"{'='*60}\n")

    # Load data
    print("Loading results...")
    gen_df, edit_df, anim_df = load_results(args.results_dir)
    print(f"  Generation rows : {len(gen_df)}")
    print(f"  Edit rows       : {len(edit_df)}")
    print(f"  Animation rows  : {len(anim_df)}")

    if len(gen_df) == 0 and len(edit_df) == 0 and len(anim_df) == 0:
        print("\nNo data found. Run experiments in Unity first.")
        sys.exit(0)

    # Produce charts
    print("\nGenerating charts...")
    pdf_path = args.out_dir / "thesis_charts.pdf"

    with PdfPages(pdf_path) as pdf:
        # ── Generation charts ──
        if len(gen_df) > 0:
            chart_success_rate_pipeline(gen_df, args.out_dir, pdf)
            chart_vlm_score_distribution(gen_df, args.out_dir, pdf)
            chart_avg_iterations(gen_df, args.out_dir, pdf)
            chart_time_violin(gen_df, args.out_dir, pdf)
            chart_compile_rate(gen_df, args.out_dir, pdf)
            chart_score_vs_time_scatter(gen_df, args.out_dir, pdf)
            chart_score_histogram(gen_df, args.out_dir, pdf)
            chart_in_kb_comparison(gen_df, args.out_dir, pdf)
            chart_rag_similarity_vs_score(gen_df, args.out_dir, pdf)
            chart_rag_components(gen_df, args.out_dir, pdf)
            chart_iteration_convergence(gen_df, args.out_dir, pdf)
            chart_model_comparison_heatmap(gen_df, args.out_dir, pdf)
            chart_vlm_vs_human_scatter(gen_df, args.out_dir, pdf)
            chart_phase_comparison_summary(gen_df, args.out_dir, pdf)
            chart_correlation_heatmap(gen_df, args.out_dir, pdf)
            chart_radar_pipeline_comparison(gen_df, args.out_dir, pdf)

        # ── Edit charts ──
        if len(edit_df) > 0:
            chart_edit_type_distribution(edit_df, args.out_dir, pdf)
            chart_edit_score_improvement(edit_df, args.out_dir, pdf)
            chart_edit_improvement_dist(edit_df, args.out_dir, pdf)
            chart_edit_time_by_type(edit_df, args.out_dir, pdf)

        # ── Animation charts ──
        if len(anim_df) > 0:
            chart_animation_results(anim_df, args.out_dir, pdf)
            chart_animation_human_scores(anim_df, args.out_dir, pdf)

        # ── Combined overview ──
        chart_all_experiment_types_summary(gen_df, edit_df, anim_df, args.out_dir, pdf)

    print(f"\n  ✓ Combined PDF : {pdf_path.name}")

    # Summary CSV
    print("\nWriting summary CSV...")
    write_summary_csv(gen_df, edit_df, anim_df, args.out_dir)

    print(f"\n{'='*60}")
    print(f"  Done!  Charts saved to: {args.out_dir.resolve()}")
    print(f"  Open thesis_charts.pdf for all figures in one file.")
    print(f"{'='*60}\n")


if __name__ == "__main__":
    main()
