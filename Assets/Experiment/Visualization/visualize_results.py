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
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
from matplotlib.backends.backend_pdf import PdfPages
import numpy as np
import pandas as pd
import seaborn as sns
from scipy import stats

warnings.filterwarnings("ignore")

# ─── colour palette ──────────────────────────────────────────────────────────
C_RAG    = "#2196F3"
C_NORAG  = "#FF9800"
C_SIMPLE = "#4CAF50"
C_COMPLEX= "#E91E63"
C_IN_KB  = "#9C27B0"
C_OUT_KB = "#607D8B"
C_OK     = "#43A047"
C_FAIL   = "#E53935"

PALETTE = {
    "RAG": C_RAG, "NoRAG": C_NORAG,
    "Simple": C_SIMPLE, "Complex": C_COMPLEX,
    "In-KB": C_IN_KB, "Out-KB": C_OUT_KB,
    "PropertyChange": "#00BCD4", "HLSLUpdate": "#FF5722"
}

# Per-model colours — used for all model-breakdown charts
MODEL_COLORS = {
    "Gemini 3 Pro":    "#1E88E5",
    "Gemini 3.1 Pro":  "#0D47A1",
    "GPT-5.4":         "#43A047",
    "Claude Sonnet":   "#FB8C00",
    "Kimi K2.6":       "#8E24AA",
    "Unknown":         "#78909C",
}

# Pricing table ($/1M tokens) kept in sync with LlmPricing.cs
PRICING = {
    "gemini-3-pro-preview":   (1.25,  10.00),
    "gemini-3.1-pro-preview": (2.50,  15.00),
    "gpt-5.4":                (5.00,  20.00),
    "claude-sonnet-4-6":      (3.00,  15.00),
    "kimi-k2.6":              (0.15,   0.60),
}

sns.set_theme(style="whitegrid", palette="muted", font_scale=1.1)


# ─── model helpers ───────────────────────────────────────────────────────────

MODEL_ID_TO_DISPLAY = {
    "gemini-3-pro-preview":   "Gemini 3 Pro",
    "gemini-3.1-pro-preview": "Gemini 3.1 Pro",
    "gpt-5.4":                "GPT-5.4",
    "claude-sonnet-4-6":      "Claude Sonnet",
    "kimi-k2.6":              "Kimi K2.6",
}

def shorten_model(model_id: str) -> str:
    return MODEL_ID_TO_DISPLAY.get(str(model_id).strip(), str(model_id) or "Unknown")

def model_color(display_name: str) -> str:
    return MODEL_COLORS.get(display_name, "#78909C")

def model_palette(models):
    return [model_color(m) for m in models]


# ─── helpers ─────────────────────────────────────────────────────────────────

def load_results(results_dir: Path):
    gen_rows, iter_rows, edit_rows, anim_rows = [], [], [], []

    for p in sorted(results_dir.glob("*.json")):
        try:
            data = json.loads(p.read_text(encoding="utf-8"))
        except Exception as e:
            print(f"  WARNING  Skipping {p.name}: {e}")
            continue

        etype = data.get("experiment_type", "")

        if etype == "generation":
            pipeline  = data.get("pipeline", "Unknown")
            set_name  = data.get("shape_set_name", "?")
            # llm_provider is the correct field; fall back to legacy code_provider
            llm_id    = (data.get("llm_provider")
                         or data.get("llm_model_id")
                         or data.get("code_provider")
                         or "unknown")
            llm_model = shorten_model(llm_id)
            eval_prov = data.get("eval_provider", "?")

            for s in data.get("shapes", []):
                iters       = s.get("iterations", [])
                usage_total = s.get("llm_usage_total", {}) or {}

                row = {
                    "pipeline":           pipeline,
                    "shape_set":          set_name,
                    "llm_id":             llm_id,
                    "llm_model":          llm_model,
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
                    # token / cost
                    "input_tokens":       usage_total.get("input_tokens", 0),
                    "output_tokens":      usage_total.get("output_tokens", 0),
                    "total_tokens":       usage_total.get("total_tokens", 0),
                    "cost_usd":           usage_total.get("cost_usd", 0.0),
                }
                # iteration-level lists (for stability charts)
                row["compile_rate"] = (
                    sum(1 for i in iters if i.get("compile_ok")) / len(iters)
                    if iters else 0.0
                )
                row["iter_scores"]  = [i.get("vlm_score",  0)     for i in iters]
                row["iter_compile"] = [bool(i.get("compile_ok", False)) for i in iters]
                gen_rows.append(row)

                # flat iteration rows for stability analysis
                for idx, it in enumerate(iters):
                    iter_rows.append({
                        "pipeline":    pipeline,
                        "llm_model":   llm_model,
                        "llm_id":      llm_id,
                        "complexity":  s.get("shape_complexity", "Unknown"),
                        "iter_index":  idx + 1,
                        "compile_ok":  int(it.get("compile_ok", False)),
                        "vlm_score":   it.get("vlm_score", 0),
                        "iter_tokens": (it.get("llm_usage") or {}).get("total_tokens", 0),
                        "iter_cost":   (it.get("llm_usage") or {}).get("cost_usd", 0.0),
                    })

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
    iter_df = pd.DataFrame(iter_rows)
    edit_df = pd.DataFrame(edit_rows)
    anim_df = pd.DataFrame(anim_rows)
    return gen_df, iter_df, edit_df, anim_df


def save_fig(fig, out_dir: Path, name: str, pdf: PdfPages):
    fig.tight_layout()
    path = out_dir / f"{name}.png"
    fig.savefig(path, dpi=300, bbox_inches="tight")
    pdf.savefig(fig, bbox_inches="tight")
    plt.close(fig)
    print(f"  OK {path.name}")


def fmt_pct(v): return f"{v*100:.1f}%"
def fmt_n(v):   return f"{v:.2f}"


# ─── GENERATION CHARTS (pipeline-level) ──────────────────────────────────────

def chart_success_rate_pipeline(df, out_dir, pdf):
    fig, axes = plt.subplots(1, 2, figsize=(12, 5))

    order = ["RAG", "NoRAG"]
    rates = [df[df.pipeline == p]["success"].mean() if len(df[df.pipeline == p]) > 0 else 0
             for p in order]
    colors = [PALETTE[p] for p in order]
    bars = axes[0].bar(["Phase 2 (RAG)", "Phase 1 (No-RAG)"], rates, color=colors,
                       width=0.5, edgecolor="white", linewidth=1.5)
    for bar, rate in zip(bars, rates):
        axes[0].text(bar.get_x() + bar.get_width()/2, bar.get_height() + 0.01,
                     fmt_pct(rate), ha="center", va="bottom", fontweight="bold")
    axes[0].set_ylim(0, 1.1); axes[0].set_ylabel("Success Rate")
    axes[0].set_title("Overall Success Rate\nPhase 1 vs Phase 2")

    combos = [("Simple","RAG"), ("Simple","NoRAG"), ("Complex","RAG"), ("Complex","NoRAG")]
    labels  = ["Simple\nRAG", "Simple\nNo-RAG", "Complex\nRAG", "Complex\nNo-RAG"]
    colors2 = [C_SIMPLE, C_NORAG, C_COMPLEX, C_NORAG]
    rates2  = []
    for comp, pip in combos:
        sub = df[(df.complexity == comp) & (df.pipeline == pip)]
        rates2.append(sub["success"].mean() if len(sub) > 0 else 0)
    bars2 = axes[1].bar(labels, rates2, color=colors2, width=0.5, edgecolor="white", linewidth=1.5)
    for bar, rate in zip(bars2, rates2):
        axes[1].text(bar.get_x() + bar.get_width()/2, bar.get_height() + 0.01,
                     fmt_pct(rate), ha="center", va="bottom", fontweight="bold")
    axes[1].set_ylim(0, 1.1); axes[1].set_ylabel("Success Rate")
    axes[1].set_title("Success Rate by Complexity\n& Pipeline")

    fig.suptitle("Figure 1 — Generation Success Rate Comparison", fontsize=13, fontweight="bold")
    save_fig(fig, out_dir, "01_success_rate_pipeline", pdf)


def chart_vlm_score_distribution(df, out_dir, pdf):
    fig, ax = plt.subplots(figsize=(10, 6))
    plot_df = df[["pipeline","complexity","final_vlm_score"]].copy()
    plot_df["Group"] = plot_df["pipeline"] + " / " + plot_df["complexity"]
    order = ["RAG / Simple", "NoRAG / Simple", "RAG / Complex", "NoRAG / Complex"]
    colors_map = {"RAG / Simple": C_RAG, "NoRAG / Simple": C_NORAG,
                  "RAG / Complex": C_RAG, "NoRAG / Complex": C_NORAG}
    palette_list = [colors_map.get(g, "#888") for g in order]
    avail = [g for g in order if g in plot_df["Group"].values]
    if avail:
        sns.boxplot(data=plot_df[plot_df.Group.isin(avail)], x="Group", y="final_vlm_score",
                    order=avail, palette=[colors_map.get(g, "#888") for g in avail],
                    width=0.5, ax=ax, flierprops={"marker":"o","markersize":4,"alpha":0.5})
        sns.stripplot(data=plot_df[plot_df.Group.isin(avail)], x="Group", y="final_vlm_score",
                      order=avail, color="black", alpha=0.35, size=3.5, jitter=True, ax=ax)
    ax.axhline(7, color=C_FAIL, linestyle="--", linewidth=1.5, label="Success threshold (7)")
    ax.set_ylim(0, 11); ax.set_ylabel("Final VLM Score (1–10)"); ax.set_xlabel("")
    ax.set_title("Figure 2 — VLM Score Distribution by Pipeline & Complexity", fontweight="bold")
    ax.legend()
    save_fig(fig, out_dir, "02_vlm_score_distribution", pdf)


def chart_avg_iterations(df, out_dir, pdf):
    fig, ax = plt.subplots(figsize=(8, 5))
    success_df = df[df.success == 1]
    combos = [("RAG","Simple"), ("RAG","Complex"), ("NoRAG","Simple"), ("NoRAG","Complex")]
    labels = ["RAG\nSimple", "RAG\nComplex", "No-RAG\nSimple", "No-RAG\nComplex"]
    colors = [C_RAG, C_RAG, C_NORAG, C_NORAG]
    means, sems = [], []
    for pip, comp in combos:
        sub = success_df[(success_df.pipeline == pip) & (success_df.complexity == comp)]
        means.append(sub.iterations_used.mean() if len(sub) > 0 else 0)
        sems.append(sub.iterations_used.sem()   if len(sub) > 1 else 0)
    bars = ax.bar(labels, means, color=colors, width=0.45, edgecolor="white",
                  yerr=sems, capsize=4, error_kw={"elinewidth":1.5})
    for bar, m in zip(bars, means):
        if m > 0:
            ax.text(bar.get_x() + bar.get_width()/2, bar.get_height() + 0.05,
                    f"{m:.2f}", ha="center", va="bottom", fontsize=9)
    ax.set_ylabel("Avg Iterations to Success (±SEM)")
    ax.set_title("Figure 3 — Average Iterations to Reach Success", fontweight="bold")
    ax.set_ylim(0, max(means or [1]) * 1.4 + 0.5)
    ax.legend(handles=[mpatches.Patch(color=C_RAG,   label="RAG (Phase 2)"),
                        mpatches.Patch(color=C_NORAG, label="No-RAG (Phase 1)")])
    save_fig(fig, out_dir, "03_avg_iterations", pdf)


def chart_time_violin(df, out_dir, pdf):
    fig, ax = plt.subplots(figsize=(10, 6))
    plot_df = df[["pipeline","complexity","total_time_s"]].copy()
    plot_df["Group"] = plot_df["pipeline"] + "\n" + plot_df["complexity"]
    order = ["RAG\nSimple", "RAG\nComplex", "NoRAG\nSimple", "NoRAG\nComplex"]
    colors_map = {"RAG\nSimple": C_RAG, "RAG\nComplex": "#1565C0",
                  "NoRAG\nSimple": C_NORAG, "NoRAG\nComplex": "#E65100"}
    sub = plot_df[plot_df.Group.isin(order)]
    if len(sub) > 1:
        avail = [g for g in order if g in sub["Group"].values]
        sns.violinplot(data=sub[sub.Group.isin(avail)], x="Group", y="total_time_s",
                       order=avail, palette=[colors_map.get(g,"#888") for g in avail],
                       cut=0, inner="box", ax=ax)
    else:
        ax.text(0.5, 0.5, "Insufficient data for violin plot",
                ha="center", va="center", transform=ax.transAxes)
    ax.set_ylabel("Total Generation Time (s)"); ax.set_xlabel("")
    ax.set_title("Figure 4 — Generation Time Distribution (Violin)", fontweight="bold")
    save_fig(fig, out_dir, "04_time_violin", pdf)


def chart_compile_rate(df, out_dir, pdf):
    fig, ax = plt.subplots(figsize=(9, 5))
    groups = [("RAG","Simple"), ("RAG","Complex"), ("NoRAG","Simple"), ("NoRAG","Complex")]
    labels = ["RAG / Simple", "RAG / Complex", "No-RAG / Simple", "No-RAG / Complex"]
    colors = [C_RAG, C_RAG, C_NORAG, C_NORAG]
    rates  = []
    for pip, comp in groups:
        sub = df[(df.pipeline == pip) & (df.complexity == comp)]
        rates.append(sub.first_pass_compile.mean() if len(sub) > 0 else 0)
    bars = ax.bar(labels, rates, color=colors, width=0.45, edgecolor="white", linewidth=1.5)
    for bar, rate in zip(bars, rates):
        ax.text(bar.get_x() + bar.get_width()/2, bar.get_height() + 0.01,
                fmt_pct(rate), ha="center", va="bottom", fontweight="bold")
    ax.set_ylim(0, 1.15); ax.set_ylabel("First-Pass Compile Rate")
    ax.set_title("Figure 5 — First-Pass HLSL Compile Success Rate", fontweight="bold")
    ax.legend(handles=[mpatches.Patch(color=C_RAG,   label="Phase 2 (RAG)"),
                        mpatches.Patch(color=C_NORAG, label="Phase 1 (No-RAG)")])
    save_fig(fig, out_dir, "05_compile_rate", pdf)


def chart_score_vs_time_scatter(df, out_dir, pdf):
    fig, ax = plt.subplots(figsize=(9, 6))
    for pip, color, label in [("RAG", C_RAG, "Phase 2 (RAG)"),
                                ("NoRAG", C_NORAG, "Phase 1 (No-RAG)")]:
        sub = df[df.pipeline == pip]
        if len(sub) == 0: continue
        ax.scatter(sub.total_time_s, sub.final_vlm_score, c=color, alpha=0.55,
                   s=50, label=label, edgecolors="white", linewidths=0.5)
        if len(sub) > 2:
            m, b, r, p, _ = stats.linregress(sub.total_time_s, sub.final_vlm_score)
            xs = np.linspace(sub.total_time_s.min(), sub.total_time_s.max(), 100)
            ax.plot(xs, m*xs + b, color=color, linewidth=2, linestyle="--", alpha=0.8)
    ax.axhline(7, color=C_FAIL, linestyle=":", linewidth=1.5, label="Success threshold")
    ax.set_xlabel("Total Generation Time (s)"); ax.set_ylabel("Final VLM Score (1–10)")
    ax.set_title("Figure 6 — VLM Score vs Generation Time", fontweight="bold")
    ax.legend()
    save_fig(fig, out_dir, "06_score_vs_time_scatter", pdf)


def chart_score_histogram(df, out_dir, pdf):
    fig, ax = plt.subplots(figsize=(9, 5))
    bins = range(1, 12)
    for pip, color, label in [("RAG", C_RAG, "Phase 2 (RAG)"),
                                ("NoRAG", C_NORAG, "Phase 1 (No-RAG)")]:
        sub = df[df.pipeline == pip]["final_vlm_score"]
        if len(sub) == 0: continue
        ax.hist(sub, bins=bins, color=color, alpha=0.55, label=label, edgecolor="white")
    ax.axvline(7, color=C_FAIL, linestyle="--", linewidth=1.5, label="Success threshold (7)")
    ax.set_xlabel("Final VLM Score (1–10)"); ax.set_ylabel("Count")
    ax.set_title("Figure 7 — VLM Score Frequency Distribution", fontweight="bold")
    ax.legend()
    save_fig(fig, out_dir, "07_score_histogram", pdf)


def chart_in_kb_comparison(df, out_dir, pdf):
    rag_df = df[df.pipeline == "RAG"]
    if len(rag_df) == 0:
        print("  WARNING  No RAG data — skipping In-KB comparison chart.")
        return
    fig, axes = plt.subplots(1, 2, figsize=(11, 5))
    for ax, metric, ylabel, title_suffix in [
        (axes[0], "success",       "Success Rate",  "Success Rate"),
        (axes[1], "final_vlm_score","Avg VLM Score","Avg VLM Score")
    ]:
        in_kb  = rag_df[rag_df.in_kb == True][metric]
        out_kb = rag_df[rag_df.in_kb == False][metric]
        vals = [in_kb.mean() if len(in_kb) > 0 else 0,
                out_kb.mean() if len(out_kb) > 0 else 0]
        errs = [0, 0] if metric == "success" else [
            in_kb.sem() if len(in_kb) > 1 else 0,
            out_kb.sem() if len(out_kb) > 1 else 0]
        bars = ax.bar(["In-KB", "Out-of-KB"], vals, color=[C_IN_KB, C_OUT_KB],
                      width=0.4, edgecolor="white", yerr=errs, capsize=5)
        for bar, v in zip(bars, vals):
            label = fmt_pct(v) if metric == "success" else fmt_n(v)
            ax.text(bar.get_x() + bar.get_width()/2,
                    bar.get_height() + (0.01 if metric == "success" else 0.05),
                    label, ha="center", va="bottom", fontweight="bold")
        ax.set_ylim(0, 1.15 if metric == "success" else 11)
        ax.set_ylabel(ylabel)
        ax.set_title(f"RAG — {title_suffix}\nIn-KB vs Out-of-KB")
        ax.set_xlabel(f"(n_in={len(in_kb)}, n_out={len(out_kb)})")
    fig.suptitle("Figure 8 — Impact of Knowledge-Base Coverage (RAG Only)",
                 fontsize=13, fontweight="bold")
    save_fig(fig, out_dir, "08_in_kb_comparison", pdf)


def chart_rag_similarity_vs_score(df, out_dir, pdf):
    rag_df = df[(df.pipeline == "RAG") & (df.rag_avg_sim > 0)]
    if len(rag_df) < 3:
        print("  WARNING  Insufficient RAG similarity data — skipping chart.")
        return
    fig, ax = plt.subplots(figsize=(8, 6))
    ax.scatter(rag_df.rag_avg_sim, rag_df.final_vlm_score,
               c=rag_df.complexity.map({"Simple": C_SIMPLE, "Complex": C_COMPLEX}).fillna("#888"),
               s=60, alpha=0.65, edgecolors="white", linewidths=0.5)
    if len(rag_df) > 2:
        m, b, r, p, _ = stats.linregress(rag_df.rag_avg_sim, rag_df.final_vlm_score)
        xs = np.linspace(rag_df.rag_avg_sim.min(), rag_df.rag_avg_sim.max(), 100)
        ax.plot(xs, m*xs + b, color=C_RAG, linewidth=2, linestyle="--",
                label=f"Trend  r={r:.2f}  p={p:.3f}")
    ax.axhline(7, color=C_FAIL, linestyle=":", linewidth=1.2, label="Success threshold")
    ax.set_xlabel("Avg RAG Retrieval Similarity Score"); ax.set_ylabel("Final VLM Score")
    ax.set_title("Figure 9 — Retrieval Similarity vs Generation Quality (RAG)", fontweight="bold")
    ax.legend(handles=[mpatches.Patch(color=C_SIMPLE, label="Simple"),
                        mpatches.Patch(color=C_COMPLEX, label="Complex")]
              + [l for l in ax.get_lines() if l.get_label().startswith("Trend")])
    save_fig(fig, out_dir, "09_rag_similarity_vs_score", pdf)


def chart_rag_components(df, out_dir, pdf):
    rag_df = df[df.pipeline == "RAG"]
    if len(rag_df) == 0 or rag_df.rag_components.max() == 0:
        print("  WARNING  No RAG component data — skipping chart.")
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
    ax.set_xlabel("Number of Decomposed Components"); ax.set_ylabel("Success Rate")
    ax.set_title("Figure 10 — RAG: Decomposition Complexity vs Success Rate", fontweight="bold")
    save_fig(fig, out_dir, "10_rag_components_vs_success", pdf)


def chart_iteration_convergence(df, out_dir, pdf):
    """Line chart: average VLM score per iteration number — RAG vs No-RAG."""
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
            sc = iter_scores[i]
            if sc:
                xs.append(i); ys.append(np.mean(sc))
                errs.append(np.std(sc) / np.sqrt(len(sc)))
        if xs:
            ax.plot(xs, ys, marker="o", color=color, linewidth=2, label=label, markersize=7)
            ax.fill_between(xs, [y-e for y,e in zip(ys,errs)], [y+e for y,e in zip(ys,errs)],
                             color=color, alpha=0.15)
    ax.axhline(7, color=C_FAIL, linestyle="--", linewidth=1.5, label="Success threshold")
    ax.set_xlabel("Iteration Number"); ax.set_ylabel("Avg VLM Score (±1 SEM)")
    ax.set_xticks(range(1, max_iter + 1)); ax.set_ylim(0, 11)
    ax.set_title("Figure 11 — Score Convergence Across Iterations", fontweight="bold")
    ax.legend()
    save_fig(fig, out_dir, "11_iteration_convergence", pdf)


def chart_model_comparison_heatmap(df, out_dir, pdf):
    """Heatmap: (llm_model × eval_provider) vs success rate."""
    if len(df) == 0: return
    pivot = df.groupby(["llm_model","eval_provider"])["success"].mean().unstack(fill_value=0)
    if pivot.empty:
        print("  WARNING  Not enough provider variation for heatmap — skipping.")
        return
    fig, ax = plt.subplots(figsize=(max(6, len(pivot.columns)*2), max(4, len(pivot)*1.2)))
    sns.heatmap(pivot, annot=True, fmt=".2f", cmap="YlOrRd", vmin=0, vmax=1,
                linewidths=0.5, ax=ax, annot_kws={"size": 11, "fontweight": "bold"})
    ax.set_xlabel("Eval Provider"); ax.set_ylabel("Code LLM")
    ax.set_title("Figure 12 — Success Rate by Code LLM × Eval Provider", fontweight="bold")
    save_fig(fig, out_dir, "12_model_heatmap", pdf)


def chart_vlm_vs_human_scatter(df, out_dir, pdf):
    scored = df[df.human_score > 0]
    if len(scored) < 3:
        print("  WARNING  Insufficient human scores — skipping VLM vs Human chart.")
        return
    fig, ax = plt.subplots(figsize=(7, 6))
    for pip, color, marker in [("RAG", C_RAG, "o"), ("NoRAG", C_NORAG, "s")]:
        sub = scored[scored.pipeline == pip]
        if len(sub) == 0: continue
        ax.scatter(sub.final_vlm_score, sub.human_score, c=color, marker=marker,
                   s=60, alpha=0.7, label=pip, edgecolors="white")
    all_s = pd.concat([scored.final_vlm_score, scored.human_score])
    lo, hi = all_s.min()-0.5, all_s.max()+0.5
    ax.plot([lo,hi],[lo,hi], "k--", linewidth=1, alpha=0.4, label="Perfect agreement")
    if len(scored) > 2:
        m, b, r, p, _ = stats.linregress(scored.final_vlm_score, scored.human_score)
        xs = np.linspace(scored.final_vlm_score.min(), scored.final_vlm_score.max(), 100)
        ax.plot(xs, m*xs+b, color="gray", linewidth=2, linestyle="-.",
                label=f"Regression r={r:.2f}")
    ax.set_xlabel("VLM Score (automated)"); ax.set_ylabel("Human Score")
    ax.set_title("Figure 13 — VLM Score vs Human Evaluation", fontweight="bold")
    ax.legend()
    save_fig(fig, out_dir, "13_vlm_vs_human", pdf)


def chart_phase_comparison_summary(df, out_dir, pdf):
    metrics = [
        ("success",          "Success Rate",          True),
        ("final_vlm_score",  "Avg VLM Score",         False),
        ("total_time_s",     "Avg Gen Time (s)",       False),
        ("first_pass_compile","1st-Pass Compile Rate", True),
    ]
    fig, axes = plt.subplots(2, 2, figsize=(12, 9))
    axes = axes.flatten()
    for ax, (col, ylabel, is_rate) in zip(axes, metrics):
        values, labels, colors = [], [], []
        for pip, label, color in [("RAG","Phase 2\n(RAG)",C_RAG),
                                   ("NoRAG","Phase 1\n(No-RAG)",C_NORAG)]:
            sub = df[df.pipeline == pip][col]
            if len(sub) == 0: continue
            values.append(sub.mean()); labels.append(label); colors.append(color)
        if not values: continue
        bars = ax.bar(labels, values, color=colors, width=0.4, edgecolor="white", linewidth=1.5)
        for bar, v in zip(bars, values):
            text = fmt_pct(v) if is_rate else f"{v:.2f}"
            ax.text(bar.get_x()+bar.get_width()/2, bar.get_height()*1.03,
                    text, ha="center", va="bottom", fontweight="bold", fontsize=11)
        if is_rate: ax.set_ylim(0, 1.2)
        ax.set_ylabel(ylabel); ax.set_title(ylabel)
    fig.suptitle("Figure 14 — Phase 1 vs Phase 2 Key Metrics Summary",
                 fontsize=13, fontweight="bold")
    save_fig(fig, out_dir, "14_phase_comparison_summary", pdf)


def chart_correlation_heatmap(df, out_dir, pdf):
    numeric_cols = [
        "success","iterations_used","total_time_s","final_vlm_score",
        "first_pass_compile","rag_components","rag_retrieved","rag_avg_sim",
        "compile_rate","human_score"
    ]
    avail = [c for c in numeric_cols if c in df.columns]
    sub = df[avail].dropna()
    if sub.shape[0] < 5 or sub.shape[1] < 3:
        print("  WARNING  Insufficient data for correlation heatmap — skipping.")
        return
    corr = sub.corr()
    fig, ax = plt.subplots(figsize=(10, 8))
    mask = np.triu(np.ones_like(corr, dtype=bool))
    sns.heatmap(corr, mask=mask, annot=True, fmt=".2f", cmap="coolwarm",
                center=0, linewidths=0.5, ax=ax, annot_kws={"size": 8})
    ax.set_title("Figure 15 — Metric Correlation Heatmap (Generation)", fontweight="bold")
    save_fig(fig, out_dir, "15_correlation_heatmap", pdf)


def chart_radar_pipeline_comparison(df, out_dir, pdf):
    metrics_def = [
        ("success",            "Success Rate",    True,  None),
        ("first_pass_compile", "1st-Pass Compile",True,  None),
        ("final_vlm_score",    "Avg VLM Score",   False, 10),
        ("iterations_used",    "Iter Efficiency", False, 6),
    ]
    def normalise(val, is_rate, max_val):
        return float(val) if is_rate else float(val) / (max_val or 1.0)
    cats, vals_rag, vals_norag = [], [], []
    for col, label, is_rate, max_val in metrics_def:
        cats.append(label)
        rag_s   = df[df.pipeline == "RAG"][col]
        norag_s = df[df.pipeline == "NoRAG"][col]
        if col == "iterations_used":
            v_rag   = 1 - normalise(rag_s.mean()   if len(rag_s)   > 0 else 0, False, max_val)
            v_norag = 1 - normalise(norag_s.mean() if len(norag_s) > 0 else 0, False, max_val)
        else:
            v_rag   = normalise(rag_s.mean()   if len(rag_s)   > 0 else 0, is_rate, max_val)
            v_norag = normalise(norag_s.mean() if len(norag_s) > 0 else 0, is_rate, max_val)
        vals_rag.append(v_rag); vals_norag.append(v_norag)
    N = len(cats)
    if N == 0: return
    angles = [n / float(N) * 2 * np.pi for n in range(N)] + [0]
    vals_rag   = vals_rag   + vals_rag[:1]
    vals_norag = vals_norag + vals_norag[:1]
    fig, ax = plt.subplots(figsize=(7, 7), subplot_kw={"polar": True})
    ax.plot(angles, vals_rag,   color=C_RAG,   linewidth=2.5, label="Phase 2 (RAG)")
    ax.fill(angles, vals_rag,   color=C_RAG,   alpha=0.2)
    ax.plot(angles, vals_norag, color=C_NORAG, linewidth=2.5, linestyle="--", label="Phase 1 (No-RAG)")
    ax.fill(angles, vals_norag, color=C_NORAG, alpha=0.2)
    ax.set_xticks(angles[:-1]); ax.set_xticklabels(cats, fontsize=11)
    ax.set_ylim(0, 1); ax.set_yticks([0.25,0.5,0.75,1.0])
    ax.set_yticklabels(["0.25","0.5","0.75","1.0"], fontsize=8)
    ax.set_title("Figure 16 — Radar: Phase 1 vs Phase 2\nNormalised Metrics",
                 fontweight="bold", pad=20)
    ax.legend(loc="upper right", bbox_to_anchor=(1.35, 1.1))
    save_fig(fig, out_dir, "16_radar_pipeline_comparison", pdf)


# ─── EDIT CHARTS ─────────────────────────────────────────────────────────────

def chart_edit_type_distribution(edit_df, out_dir, pdf):
    if len(edit_df) == 0: return
    counts = edit_df["edit_type"].value_counts()
    if len(counts) == 0: return
    fig, axes = plt.subplots(1, 2, figsize=(12, 5))
    colors = [PALETTE.get(t, "#888") for t in counts.index]
    axes[0].pie(counts.values, labels=counts.index, colors=colors,
                autopct="%1.1f%%", startangle=90,
                wedgeprops={"edgecolor":"white","linewidth":2})
    axes[0].set_title("Edit Type Distribution")
    success_by_type = edit_df.groupby("edit_type")["success"].mean()
    bars = axes[1].bar(success_by_type.index, success_by_type.values,
                       color=[PALETTE.get(t,"#888") for t in success_by_type.index],
                       width=0.4, edgecolor="white")
    for bar, v in zip(bars, success_by_type.values):
        axes[1].text(bar.get_x()+bar.get_width()/2, bar.get_height()+0.01,
                     fmt_pct(v), ha="center", va="bottom", fontweight="bold")
    axes[1].set_ylim(0, 1.15); axes[1].set_ylabel("Success Rate")
    axes[1].set_title("Edit Success Rate by Type")
    fig.suptitle("Figure 17 — Edit Pipeline: Type Distribution & Success Rate",
                 fontsize=13, fontweight="bold")
    save_fig(fig, out_dir, "17_edit_type_distribution", pdf)


def chart_edit_score_improvement(edit_df, out_dir, pdf):
    if len(edit_df) == 0: return
    fig, axes = plt.subplots(1, 2, figsize=(12, 5))
    for ax, grouped_by, title_suffix in [
        (axes[0], "edit_type",  "by Edit Type"),
        (axes[1], "success",    "Success vs Failure")
    ]:
        local_df = edit_df.copy()
        if grouped_by == "success":
            local_df["success_label"] = local_df["success"].map({1:"Success",0:"Failure"})
            grouped_by = "success_label"
        groups = local_df[grouped_by].unique()
        x = np.arange(len(groups)); width = 0.3
        ax.bar(x-width/2,
               [local_df[local_df[grouped_by]==g]["vlm_before"].mean() for g in groups],
               width, label="Before", color="#78909C", edgecolor="white")
        ax.bar(x+width/2,
               [local_df[local_df[grouped_by]==g]["vlm_after"].mean() for g in groups],
               width, label="After",  color="#26A69A", edgecolor="white")
        ax.set_xticks(x); ax.set_xticklabels(groups); ax.set_ylim(0, 11)
        ax.axhline(7, color=C_FAIL, linestyle="--", linewidth=1.2)
        ax.set_ylabel("Avg VLM Score"); ax.set_title(f"Before vs After {title_suffix}")
        ax.legend()
    fig.suptitle("Figure 18 — Edit Pipeline: VLM Score Before vs After",
                 fontsize=13, fontweight="bold")
    save_fig(fig, out_dir, "18_edit_score_improvement", pdf)


def chart_edit_improvement_dist(edit_df, out_dir, pdf):
    if len(edit_df) == 0: return
    fig, ax = plt.subplots(figsize=(9, 5))
    for et, color in [("PropertyChange",PALETTE["PropertyChange"]),
                       ("HLSLUpdate",PALETTE["HLSLUpdate"])]:
        sub = edit_df[edit_df.edit_type == et]["improvement"].dropna()
        if len(sub) < 2: continue
        ax.hist(sub, bins=range(-5,11), alpha=0.55, color=color, label=et, edgecolor="white")
    ax.axvline(0, color="black", linewidth=1.2, label="No change")
    ax.set_xlabel("VLM Score Improvement (After − Before)"); ax.set_ylabel("Count")
    ax.set_title("Figure 19 — Edit Score Improvement Distribution", fontweight="bold")
    ax.legend()
    save_fig(fig, out_dir, "19_edit_improvement_dist", pdf)


def chart_edit_time_by_type(edit_df, out_dir, pdf):
    if len(edit_df) == 0: return
    types = [t for t in ["PropertyChange","HLSLUpdate"] if t in edit_df.edit_type.values]
    if not types: return
    fig, ax = plt.subplots(figsize=(7, 5))
    sns.boxplot(data=edit_df[edit_df.edit_type.isin(types)],
                x="edit_type", y="total_time_s", order=types,
                palette=[PALETTE.get(t,"#888") for t in types], width=0.4, ax=ax)
    sns.stripplot(data=edit_df[edit_df.edit_type.isin(types)],
                  x="edit_type", y="total_time_s", order=types,
                  color="black", alpha=0.4, size=4, jitter=True, ax=ax)
    ax.set_xlabel("Edit Type"); ax.set_ylabel("Total Edit Time (s)")
    ax.set_title("Figure 20 — Edit Time by Edit Type", fontweight="bold")
    save_fig(fig, out_dir, "20_edit_time_by_type", pdf)


# ─── ANIMATION CHARTS ────────────────────────────────────────────────────────

def chart_animation_results(anim_df, out_dir, pdf):
    if len(anim_df) == 0:
        print("  WARNING  No animation data — skipping animation charts.")
        return
    fig, axes = plt.subplots(1, 2, figsize=(11, 5))
    rate = anim_df["success"].mean()
    axes[0].bar(["Animation\nGeneration"], [rate], color=C_RAG, width=0.35, edgecolor="white")
    axes[0].text(0, rate+0.02, fmt_pct(rate), ha="center", va="bottom",
                 fontweight="bold", fontsize=13)
    axes[0].set_ylim(0, 1.2); axes[0].set_ylabel("Success Rate")
    axes[0].set_title("Animation Pipeline Success Rate")
    axes[1].hist(anim_df["total_time_s"], bins=10, color=C_RAG, edgecolor="white", alpha=0.8)
    axes[1].axvline(anim_df["total_time_s"].mean(), color=C_FAIL, linestyle="--", linewidth=2,
                    label=f"Mean {anim_df['total_time_s'].mean():.1f}s")
    axes[1].set_xlabel("Generation Time (s)"); axes[1].set_ylabel("Count")
    axes[1].set_title("Animation Script Generation Time"); axes[1].legend()
    fig.suptitle("Figure 21 — Animation Pipeline: Success Rate & Generation Time",
                 fontsize=13, fontweight="bold")
    save_fig(fig, out_dir, "21_animation_results", pdf)


def chart_animation_human_scores(anim_df, out_dir, pdf):
    scored = anim_df[anim_df.human_score > 0]
    if len(scored) < 2: return
    fig, ax = plt.subplots(figsize=(8, 5))
    counts = scored["human_score"].value_counts().sort_index()
    ax.bar(counts.index.astype(str), counts.values, color=C_RAG, width=0.5, edgecolor="white")
    ax.axvline(str(7), color=C_FAIL, linestyle="--", linewidth=1.5, label="Threshold (7)")
    ax.set_xlabel("Human Score (1–10)"); ax.set_ylabel("Count")
    ax.set_title("Figure 22 — Animation: Human Score Distribution", fontweight="bold")
    ax.legend()
    save_fig(fig, out_dir, "22_animation_human_scores", pdf)


# ─── COMBINED OVERVIEW ────────────────────────────────────────────────────────

def chart_all_experiment_types_summary(gen_df, edit_df, anim_df, out_dir, pdf):
    labels, rates, colors = [], [], []
    if len(gen_df) > 0:
        for pip, color, label in [("RAG",C_RAG,"Generation\n(Phase 2 RAG)"),
                                   ("NoRAG",C_NORAG,"Generation\n(Phase 1 No-RAG)")]:
            sub = gen_df[gen_df.pipeline == pip]
            if len(sub) > 0:
                labels.append(label); rates.append(sub.success.mean()); colors.append(color)
    if len(edit_df) > 0:
        labels.append("Edit\n(Phase 2 only)")
        rates.append(edit_df.success.mean()); colors.append("#00BCD4")
    if len(anim_df) > 0:
        labels.append("Animation\n(Phase 2 only)")
        rates.append(anim_df.success.mean()); colors.append("#8BC34A")
    if not labels:
        print("  WARNING  No data for overview chart."); return
    fig, ax = plt.subplots(figsize=(10, 6))
    bars = ax.bar(labels, rates, color=colors, width=0.5, edgecolor="white", linewidth=1.5)
    for bar, rate in zip(bars, rates):
        ax.text(bar.get_x()+bar.get_width()/2, bar.get_height()+0.01,
                fmt_pct(rate), ha="center", va="bottom", fontweight="bold", fontsize=12)
    ax.set_ylim(0, 1.2); ax.set_ylabel("Success Rate")
    ax.set_title("Figure 23 — Overall Success Rate: All Experiment Types",
                 fontsize=13, fontweight="bold")
    ax.axhline(0.75, color=C_OK, linestyle=":", linewidth=1.5, label="75% baseline")
    ax.legend()
    save_fig(fig, out_dir, "23_all_experiments_summary", pdf)


# ─── MODEL COMPARISON CHARTS (Figures 24–29) ─────────────────────────────────

def _model_order(df):
    """Return models ordered by overall success rate descending."""
    models = df["llm_model"].unique().tolist()
    means  = {m: df[df.llm_model == m]["success"].mean() for m in models}
    return sorted(models, key=lambda m: means[m], reverse=True)


def chart_model_success_rate(df, out_dir, pdf):
    """Bar chart: success rate per LLM, split by pipeline (RAG / NoRAG)."""
    models = _model_order(df)
    if len(models) < 1: return

    pipelines = [p for p in ["RAG","NoRAG"] if p in df.pipeline.values]
    x         = np.arange(len(models))
    width     = 0.35 / max(len(pipelines), 1)
    offsets   = np.linspace(-width*(len(pipelines)-1)/2, width*(len(pipelines)-1)/2, len(pipelines))

    fig, ax = plt.subplots(figsize=(max(10, len(models)*2), 6))
    for offset, pip in zip(offsets, pipelines):
        color = C_RAG if pip == "RAG" else C_NORAG
        label = "Phase 2 (RAG)" if pip == "RAG" else "Phase 1 (No-RAG)"
        rates = []
        for m in models:
            sub = df[(df.llm_model == m) & (df.pipeline == pip)]
            rates.append(sub["success"].mean() if len(sub) > 0 else float("nan"))
        bars = ax.bar(x + offset, rates, width*0.9, color=color,
                      alpha=0.85, label=label, edgecolor="white")
        for bar, r in zip(bars, rates):
            if not np.isnan(r):
                ax.text(bar.get_x()+bar.get_width()/2, bar.get_height()+0.01,
                        fmt_pct(r), ha="center", va="bottom", fontsize=8, fontweight="bold")

    ax.set_xticks(x); ax.set_xticklabels(models, rotation=15, ha="right")
    ax.set_ylim(0, 1.15); ax.set_ylabel("Success Rate"); ax.legend()
    ax.set_title("Figure 24 — Success Rate by LLM Model & Pipeline", fontweight="bold")
    save_fig(fig, out_dir, "24_model_success_rate", pdf)


def chart_model_vlm_score(df, out_dir, pdf):
    """Box plot: VLM score distribution per model."""
    models = _model_order(df)
    if len(models) < 1: return

    fig, ax = plt.subplots(figsize=(max(10, len(models)*2), 6))
    palette = {m: model_color(m) for m in models}
    sns.boxplot(data=df, x="llm_model", y="final_vlm_score", order=models,
                palette=palette, width=0.5, ax=ax,
                flierprops={"marker":"o","markersize":4,"alpha":0.5})
    sns.stripplot(data=df, x="llm_model", y="final_vlm_score", order=models,
                  color="black", alpha=0.3, size=3.5, jitter=True, ax=ax)
    ax.axhline(7, color=C_FAIL, linestyle="--", linewidth=1.5, label="Success threshold (7)")
    ax.set_ylim(0, 11); ax.set_ylabel("Final VLM Score (1–10)")
    ax.set_xlabel(""); ax.tick_params(axis="x", rotation=15)
    ax.set_title("Figure 25 — VLM Score Distribution by LLM Model", fontweight="bold")
    ax.legend()
    save_fig(fig, out_dir, "25_model_vlm_score", pdf)


def chart_model_compile_rate(df, out_dir, pdf):
    """Bar chart: first-pass compile rate per model, split by pipeline."""
    models = _model_order(df)
    if len(models) < 1: return

    pipelines = [p for p in ["RAG","NoRAG"] if p in df.pipeline.values]
    x         = np.arange(len(models))
    width     = 0.35 / max(len(pipelines), 1)
    offsets   = np.linspace(-width*(len(pipelines)-1)/2, width*(len(pipelines)-1)/2, len(pipelines))

    fig, ax = plt.subplots(figsize=(max(10, len(models)*2), 6))
    for offset, pip in zip(offsets, pipelines):
        color = C_RAG if pip == "RAG" else C_NORAG
        label = "Phase 2 (RAG)" if pip == "RAG" else "Phase 1 (No-RAG)"
        rates = []
        for m in models:
            sub = df[(df.llm_model == m) & (df.pipeline == pip)]
            rates.append(sub["first_pass_compile"].mean() if len(sub) > 0 else float("nan"))
        bars = ax.bar(x+offset, rates, width*0.9, color=color,
                      alpha=0.85, label=label, edgecolor="white")
        for bar, r in zip(bars, rates):
            if not np.isnan(r):
                ax.text(bar.get_x()+bar.get_width()/2, bar.get_height()+0.01,
                        fmt_pct(r), ha="center", va="bottom", fontsize=8, fontweight="bold")

    ax.set_xticks(x); ax.set_xticklabels(models, rotation=15, ha="right")
    ax.set_ylim(0, 1.15); ax.set_ylabel("First-Pass Compile Rate"); ax.legend()
    ax.set_title("Figure 26 — First-Pass HLSL Compile Rate by LLM Model", fontweight="bold")
    save_fig(fig, out_dir, "26_model_compile_rate", pdf)


def chart_model_iterations(df, out_dir, pdf):
    """Bar chart: avg iterations to success per model."""
    models   = _model_order(df)
    success  = df[df.success == 1]
    if len(models) < 1 or len(success) == 0: return

    means = []; sems = []; colors = []
    for m in models:
        sub = success[success.llm_model == m]["iterations_used"]
        means.append(sub.mean() if len(sub) > 0 else 0)
        sems.append(sub.sem()   if len(sub) > 1 else 0)
        colors.append(model_color(m))

    fig, ax = plt.subplots(figsize=(max(10, len(models)*2), 6))
    bars = ax.bar(models, means, color=colors, width=0.5, edgecolor="white",
                  yerr=sems, capsize=4, error_kw={"elinewidth":1.5})
    for bar, m_val in zip(bars, means):
        if m_val > 0:
            ax.text(bar.get_x()+bar.get_width()/2, bar.get_height()+0.05,
                    f"{m_val:.2f}", ha="center", va="bottom", fontsize=9)
    ax.set_ylabel("Avg Iterations to Success (±SEM)")
    ax.tick_params(axis="x", rotation=15)
    ax.set_title("Figure 27 — Average Iterations to Success by LLM Model", fontweight="bold")
    ax.set_ylim(0, max(means or [1])*1.5+0.5)
    save_fig(fig, out_dir, "27_model_iterations", pdf)


def chart_model_time(df, out_dir, pdf):
    """Box plot: generation time per model."""
    models = _model_order(df)
    if len(models) < 1: return

    fig, ax = plt.subplots(figsize=(max(10, len(models)*2), 6))
    palette = {m: model_color(m) for m in models}
    sns.boxplot(data=df, x="llm_model", y="total_time_s", order=models,
                palette=palette, width=0.5, ax=ax)
    sns.stripplot(data=df, x="llm_model", y="total_time_s", order=models,
                  color="black", alpha=0.3, size=3, jitter=True, ax=ax)
    ax.set_ylabel("Total Generation Time (s)"); ax.set_xlabel("")
    ax.tick_params(axis="x", rotation=15)
    ax.set_title("Figure 28 — Generation Time by LLM Model", fontweight="bold")
    save_fig(fig, out_dir, "28_model_time", pdf)


def chart_model_cost_tokens(df, out_dir, pdf):
    """Bar chart: avg cost and tokens per shape per model.

    If all token counts are 0 (token tracking not yet enabled), the chart
    shows the theoretical cost using the known pricing table and a note
    explaining that actual token counts are pending.
    """
    models = _model_order(df)
    if len(models) < 1: return

    has_real_tokens = df["total_tokens"].sum() > 0

    if has_real_tokens:
        cost_col   = "cost_usd"
        token_col  = "total_tokens"
        cost_note  = "Avg Cost per Shape (USD)"
        token_note = "Avg Total Tokens per Shape"
    else:
        # Estimate cost from pricing table using a typical token count placeholder
        # (token tracking not yet wired in C# — these are theoretical minimums)
        def est_cost(model_id):
            p = PRICING.get(model_id)
            if p is None: return 0.0
            # assume ~2000 in + ~500 out tokens as rough estimate for a typical shader
            return (2000/1_000_000)*p[0] + (500/1_000_000)*p[1]

        df = df.copy()
        df["est_cost"] = df["llm_id"].apply(est_cost)
        cost_col   = "est_cost"
        token_col  = None
        cost_note  = "Estimated Cost per Shape (USD)\n[token tracking pending — see thesis note]"
        token_note = None

    fig, axes = plt.subplots(1, 2 if token_col else 1, figsize=(max(10, len(models)*2), 6))
    if not isinstance(axes, np.ndarray):
        axes = [axes]

    # Cost bar
    costs  = [df[df.llm_model == m][cost_col].mean() for m in models]
    colors = [model_color(m) for m in models]
    bars   = axes[0].bar(models, costs, color=colors, width=0.5, edgecolor="white")
    for bar, v in zip(bars, costs):
        axes[0].text(bar.get_x()+bar.get_width()/2, bar.get_height()*1.03,
                     f"${v:.4f}", ha="center", va="bottom", fontsize=8, fontweight="bold")
    axes[0].set_ylabel(cost_note)
    axes[0].tick_params(axis="x", rotation=15)
    axes[0].set_title("Cost per Shape")

    # Token bar (only if real data)
    if token_col and len(axes) > 1:
        tokens = [df[df.llm_model == m][token_col].mean() for m in models]
        bars2  = axes[1].bar(models, tokens, color=colors, width=0.5, edgecolor="white")
        for bar, v in zip(bars2, tokens):
            axes[1].text(bar.get_x()+bar.get_width()/2, bar.get_height()*1.03,
                         f"{int(v):,}", ha="center", va="bottom", fontsize=8, fontweight="bold")
        axes[1].set_ylabel(token_note)
        axes[1].tick_params(axis="x", rotation=15)
        axes[1].set_title("Tokens per Shape")

    fig.suptitle("Figure 29 — Cost & Token Usage by LLM Model", fontsize=13, fontweight="bold")
    save_fig(fig, out_dir, "29_model_cost_tokens", pdf)


# ─── ITERATION STABILITY CHARTS (Figures 30–32) ───────────────────────────────

def chart_compile_stability_by_model(df, iter_df, out_dir, pdf):
    """Line chart: compile rate at each iteration index, one line per model."""
    models  = _model_order(df)
    if len(models) < 1 or len(iter_df) == 0: return

    max_iter = int(iter_df["iter_index"].max()) if len(iter_df) > 0 else 3
    fig, ax  = plt.subplots(figsize=(10, 6))

    for m in models:
        sub = iter_df[iter_df.llm_model == m]
        if len(sub) == 0: continue
        xs, ys, errs = [], [], []
        for i in range(1, max_iter+1):
            slice_i = sub[sub.iter_index == i]["compile_ok"]
            if len(slice_i) >= 1:
                xs.append(i)
                ys.append(slice_i.mean())
                errs.append(slice_i.sem() if len(slice_i) > 1 else 0)
        if xs:
            ax.plot(xs, ys, marker="o", color=model_color(m), linewidth=2,
                    label=m, markersize=7)
            ax.fill_between(xs, [y-e for y,e in zip(ys,errs)],
                             [y+e for y,e in zip(ys,errs)],
                             color=model_color(m), alpha=0.12)

    ax.axhline(1.0, color="#9E9E9E", linestyle=":", linewidth=1, alpha=0.5)
    ax.set_xlabel("Iteration Number"); ax.set_ylabel("HLSL Compile Rate")
    ax.set_xticks(range(1, max_iter+1)); ax.set_ylim(-0.05, 1.1)
    ax.set_title("Figure 30 — HLSL Compile Rate per Iteration by LLM Model", fontweight="bold")
    ax.legend(loc="lower right")
    save_fig(fig, out_dir, "30_compile_stability_by_model", pdf)


def chart_score_stability_by_model(df, iter_df, out_dir, pdf):
    """Line chart: avg VLM score at each iteration index, one line per model."""
    models  = _model_order(df)
    if len(models) < 1 or len(iter_df) == 0: return

    max_iter = int(iter_df["iter_index"].max()) if len(iter_df) > 0 else 3
    fig, ax  = plt.subplots(figsize=(10, 6))

    for m in models:
        sub = iter_df[iter_df.llm_model == m]
        if len(sub) == 0: continue
        xs, ys, errs = [], [], []
        for i in range(1, max_iter+1):
            slice_i = sub[sub.iter_index == i]["vlm_score"]
            if len(slice_i) >= 1:
                xs.append(i)
                ys.append(slice_i.mean())
                errs.append(slice_i.sem() if len(slice_i) > 1 else 0)
        if xs:
            ax.plot(xs, ys, marker="o", color=model_color(m), linewidth=2,
                    label=m, markersize=7)
            ax.fill_between(xs, [y-e for y,e in zip(ys,errs)],
                             [y+e for y,e in zip(ys,errs)],
                             color=model_color(m), alpha=0.12)

    ax.axhline(7, color=C_FAIL, linestyle="--", linewidth=1.5, label="Success threshold (7)")
    ax.set_xlabel("Iteration Number"); ax.set_ylabel("Avg VLM Score (±1 SEM)")
    ax.set_xticks(range(1, max_iter+1)); ax.set_ylim(0, 11)
    ax.set_title("Figure 31 — VLM Score Convergence per Iteration by LLM Model", fontweight="bold")
    ax.legend(loc="lower right")
    save_fig(fig, out_dir, "31_score_stability_by_model", pdf)


def chart_recovery_rate_by_model(df, out_dir, pdf):
    """Bar chart: if iteration 1 did NOT compile, what % compiled at iteration 2?

    This shows stability / resilience: a model that recovers quickly after a
    first failure is more robust in practice.
    """
    models = _model_order(df)
    if len(models) < 1: return

    # For each shape with >= 2 iterations where iter 1 failed to compile:
    # recovery = iter_compile[1] is True
    recoveries = {}
    totals     = {}
    for m in models:
        sub = df[df.llm_model == m]
        n_failed  = 0
        n_recover = 0
        for _, row in sub.iterrows():
            compile_list = row.get("iter_compile", [])
            if len(compile_list) >= 2 and compile_list[0] == False:
                n_failed  += 1
                if compile_list[1]:
                    n_recover += 1
        recoveries[m] = n_recover / n_failed if n_failed > 0 else float("nan")
        totals[m]     = n_failed

    valid = [(m, recoveries[m]) for m in models if not np.isnan(recoveries[m])]
    if not valid:
        print("  WARNING  No iter-1-fail shapes found — skipping recovery chart.")
        return

    labels = [v[0] for v in valid]
    rates  = [v[1] for v in valid]
    colors = [model_color(m) for m in labels]
    ns     = [totals[m] for m in labels]

    fig, ax = plt.subplots(figsize=(max(8, len(labels)*2), 6))
    bars = ax.bar(labels, rates, color=colors, width=0.5, edgecolor="white", linewidth=1.5)
    for bar, r, n in zip(bars, rates, ns):
        ax.text(bar.get_x()+bar.get_width()/2, bar.get_height()+0.01,
                f"{fmt_pct(r)}\n(n={n})", ha="center", va="bottom",
                fontsize=9, fontweight="bold")
    ax.set_ylim(0, 1.2); ax.set_ylabel("Recovery Rate (iter 2 compiles | iter 1 failed)")
    ax.set_xlabel("")
    ax.tick_params(axis="x", rotation=15)
    ax.axhline(0.5, color="#9E9E9E", linestyle=":", linewidth=1.2, alpha=0.7, label="50% line")
    ax.set_title("Figure 32 — Iteration Recovery Rate by LLM Model\n"
                 "(Shapes where Iter 1 failed to compile — did Iter 2 compile?)",
                 fontweight="bold")
    ax.legend()
    save_fig(fig, out_dir, "32_recovery_rate_by_model", pdf)


# ─── SUMMARY CSV ─────────────────────────────────────────────────────────────

def write_summary_csv(gen_df, edit_df, anim_df, out_dir):
    rows = []

    if len(gen_df) > 0:
        # Pipeline × complexity breakdown (original)
        for pip in gen_df.pipeline.unique():
            for comp in gen_df.complexity.unique():
                sub = gen_df[(gen_df.pipeline == pip) & (gen_df.complexity == comp)]
                if len(sub) == 0: continue
                rows.append({
                    "experiment": "generation",
                    "group_by": "pipeline_complexity",
                    "pipeline": pip, "complexity": comp, "llm_model": "ALL",
                    "n": len(sub),
                    "success_rate":    sub.success.mean(),
                    "avg_vlm_score":   sub.final_vlm_score.mean(),
                    "avg_iterations":  sub.iterations_used.mean(),
                    "avg_time_s":      sub.total_time_s.mean(),
                    "compile_rate":    sub.first_pass_compile.mean(),
                    "avg_cost_usd":    sub.cost_usd.mean() if sub.cost_usd.sum() > 0 else None,
                    "avg_total_tokens":sub.total_tokens.mean() if sub.total_tokens.sum() > 0 else None,
                    "avg_human_score": sub[sub.human_score > 0].human_score.mean()
                                       if any(sub.human_score > 0) else None,
                })
        # Model breakdown
        for m in gen_df.llm_model.unique():
            sub = gen_df[gen_df.llm_model == m]
            rows.append({
                "experiment": "generation",
                "group_by": "model",
                "pipeline": "ALL", "complexity": "ALL", "llm_model": m,
                "n": len(sub),
                "success_rate":    sub.success.mean(),
                "avg_vlm_score":   sub.final_vlm_score.mean(),
                "avg_iterations":  sub.iterations_used.mean(),
                "avg_time_s":      sub.total_time_s.mean(),
                "compile_rate":    sub.first_pass_compile.mean(),
                "avg_cost_usd":    sub.cost_usd.mean() if sub.cost_usd.sum() > 0 else None,
                "avg_total_tokens":sub.total_tokens.mean() if sub.total_tokens.sum() > 0 else None,
                "avg_human_score": sub[sub.human_score > 0].human_score.mean()
                                   if any(sub.human_score > 0) else None,
            })

    if len(edit_df) > 0:
        for et in edit_df.edit_type.unique():
            sub = edit_df[edit_df.edit_type == et]
            rows.append({
                "experiment": "edit", "group_by": "edit_type",
                "pipeline": "RAG", "complexity": et, "llm_model": "ALL",
                "n": len(sub),
                "success_rate":    sub.success.mean(),
                "avg_vlm_score":   sub.vlm_after.mean(),
                "avg_iterations":  sub.iterations_used.mean(),
                "avg_time_s":      sub.total_time_s.mean(),
                "compile_rate": None, "avg_cost_usd": None, "avg_total_tokens": None,
                "avg_human_score": sub[sub.human_score > 0].human_score.mean()
                                   if any(sub.human_score > 0) else None,
            })

    if len(anim_df) > 0:
        rows.append({
            "experiment": "animation", "group_by": "all",
            "pipeline": "RAG", "complexity": "N/A", "llm_model": "ALL",
            "n": len(anim_df),
            "success_rate":    anim_df.success.mean(),
            "avg_vlm_score":   None,
            "avg_iterations":  None,
            "avg_time_s":      anim_df.total_time_s.mean(),
            "compile_rate": None, "avg_cost_usd": None, "avg_total_tokens": None,
            "avg_human_score": anim_df[anim_df.human_score > 0].human_score.mean()
                               if any(anim_df.human_score > 0) else None,
        })

    csv_path = out_dir / "summary_stats.csv"
    pd.DataFrame(rows).to_csv(csv_path, index=False, float_format="%.4f")
    print(f"  OK {csv_path.name}")


# ─── MAIN ────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="Visualise Phase 2 Experiment Results")
    parser.add_argument("--results_dir", type=Path,
                        default=Path("Assets/Experiment/Results"))
    parser.add_argument("--out_dir", type=Path,
                        default=Path("Assets/Experiment/Visualization/Charts"))
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

    print("Loading results...")
    gen_df, iter_df, edit_df, anim_df = load_results(args.results_dir)
    print(f"  Generation rows : {len(gen_df)}")
    print(f"  Iteration rows  : {len(iter_df)}")
    print(f"  Edit rows       : {len(edit_df)}")
    print(f"  Animation rows  : {len(anim_df)}")

    if len(gen_df) > 0:
        models_found = gen_df["llm_model"].unique().tolist()
        print(f"  LLM models      : {', '.join(models_found)}")

    if len(gen_df) == 0 and len(edit_df) == 0 and len(anim_df) == 0:
        print("\nNo data found. Run experiments in Unity first.")
        sys.exit(0)

    print("\nGenerating charts...")
    pdf_path = args.out_dir / "thesis_charts.pdf"

    with PdfPages(pdf_path) as pdf:

        # ── Pipeline-level generation charts (Figs 1–16) ──
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

        # ── Edit charts (Figs 17–20) ──
        if len(edit_df) > 0:
            chart_edit_type_distribution(edit_df, args.out_dir, pdf)
            chart_edit_score_improvement(edit_df, args.out_dir, pdf)
            chart_edit_improvement_dist(edit_df, args.out_dir, pdf)
            chart_edit_time_by_type(edit_df, args.out_dir, pdf)

        # ── Animation charts (Figs 21–22) ──
        if len(anim_df) > 0:
            chart_animation_results(anim_df, args.out_dir, pdf)
            chart_animation_human_scores(anim_df, args.out_dir, pdf)

        # ── Combined overview (Fig 23) ──
        chart_all_experiment_types_summary(gen_df, edit_df, anim_df, args.out_dir, pdf)

        # ── Model comparison charts (Figs 24–29) ──
        if len(gen_df) > 0:
            chart_model_success_rate(gen_df, args.out_dir, pdf)
            chart_model_vlm_score(gen_df, args.out_dir, pdf)
            chart_model_compile_rate(gen_df, args.out_dir, pdf)
            chart_model_iterations(gen_df, args.out_dir, pdf)
            chart_model_time(gen_df, args.out_dir, pdf)
            chart_model_cost_tokens(gen_df, args.out_dir, pdf)

        # ── Iteration stability charts (Figs 30–32) ──
        if len(gen_df) > 0 and len(iter_df) > 0:
            chart_compile_stability_by_model(gen_df, iter_df, args.out_dir, pdf)
            chart_score_stability_by_model(gen_df, iter_df, args.out_dir, pdf)
            chart_recovery_rate_by_model(gen_df, args.out_dir, pdf)

    print(f"\n  OK Combined PDF : {pdf_path.name}")

    print("\nWriting summary CSV...")
    write_summary_csv(gen_df, edit_df, anim_df, args.out_dir)

    print(f"\n{'='*60}")
    print(f"  Done!  Charts saved to: {args.out_dir.resolve()}")
    print(f"  Open thesis_charts.pdf for all 32 figures in one file.")
    print(f"{'='*60}\n")


if __name__ == "__main__":
    main()
