"""
Rakan - Posture accuracy study: analysis
========================================

Reads every CSV produced by capture.py (tools/posture_study/data/*.csv) and
produces the numbers Objective 2 needs:

  * Classification accuracy per exercise + overall, with a 95% Wilson
    confidence interval (small-sample honest - 20-60 reps per exercise is
    small, so a bare "82%" without an interval overstates certainty).
  * Confusion matrix per exercise.
  * Precision / recall / F1 / specificity, treating "INCORRECT form" as the
    POSITIVE class - the thing the system exists to catch. A recall of 0.60
    means the app caught 60% of the genuinely bad reps.
  * Rep-detection rate (reps the app counted vs. reps the observer saw),
    reported separately because a missed rep has no prediction to score.
  * Per-tester and per-fault-tag breakdowns.
  * Pass/fail against the 75% target.

Outputs go to tools/posture_study/results/:
  summary.md                       - paste-ready tables for the dissertation
  metrics.csv                      - one row per exercise + overall
  confusion_<exercise>.csv         - raw confusion matrices
  all_reps_combined.csv            - every labelled rep from every tester

USAGE (backend venv already has pandas):
    backend\\venv\\Scripts\\python tools/posture_study/analyse.py
"""

import argparse
import glob
import math
import os
import sys

import pandas as pd

TARGET = 0.75
HERE = os.path.dirname(os.path.abspath(__file__))


def wilson_ci(k, n, z=1.96):
    if n == 0:
        return (float("nan"), float("nan"))
    p = k / n
    denom = 1 + z * z / n
    centre = (p + z * z / (2 * n)) / denom
    half = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / denom
    return (max(0.0, centre - half), min(1.0, centre + half))


def safe_div(a, b):
    return a / b if b else float("nan")


def metrics_for(df):
    """df: labelled, app-counted reps. Positive class = incorrect form."""
    gt_bad = df["ground_truth_correct"] == False  # noqa: E712
    pr_bad = df["predicted_correct"] == False     # noqa: E712
    tp = int((gt_bad & pr_bad).sum())
    tn = int((~gt_bad & ~pr_bad).sum())
    fp = int((~gt_bad & pr_bad).sum())
    fn = int((gt_bad & ~pr_bad).sum())
    n = tp + tn + fp + fn
    acc = safe_div(tp + tn, n)
    lo, hi = wilson_ci(tp + tn, n)
    prec = safe_div(tp, tp + fp)
    rec = safe_div(tp, tp + fn)
    spec = safe_div(tn, tn + fp)
    f1 = safe_div(2 * prec * rec, prec + rec) if not (math.isnan(prec) or math.isnan(rec)) else float("nan")
    return {
        "n_reps": n, "n_correct_gt": int((~gt_bad).sum()), "n_incorrect_gt": int(gt_bad.sum()),
        "TP": tp, "TN": tn, "FP": fp, "FN": fn,
        "accuracy": acc, "ci95_low": lo, "ci95_high": hi,
        "precision_incorrect": prec, "recall_incorrect": rec,
        "specificity": spec, "f1_incorrect": f1,
        "meets_75pct": (acc >= TARGET) if n else False,
    }


def to_bool(series):
    return series.astype(str).str.strip().str.lower().map({"true": True, "false": False})


def fmt(x, pct=True):
    if isinstance(x, float) and math.isnan(x):
        return "-"
    return f"{x:.1%}" if pct else f"{x:.2f}"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--data-dir", default=os.path.join(HERE, "data"))
    ap.add_argument("--out-dir", default=os.path.join(HERE, "results"))
    args = ap.parse_args()

    files = sorted(glob.glob(os.path.join(args.data_dir, "*.csv")))
    if not files:
        sys.exit(f"No CSVs found in {args.data_dir}. Run capture.py first.")

    frames = []
    for f in files:
        d = pd.read_csv(f, dtype=str, keep_default_na=False)
        d["source_file"] = os.path.basename(f)
        frames.append(d)
    raw = pd.concat(frames, ignore_index=True)

    raw["app_counted_b"] = to_bool(raw["app_counted"])
    raw["ground_truth_correct"] = to_bool(raw["ground_truth_correct"])
    raw["predicted_correct"] = to_bool(raw["predicted_correct"])

    counted = raw[raw["app_counted_b"] == True]      # noqa: E712
    missed = raw[raw["app_counted_b"] == False]      # noqa: E712
    unlabelled = counted[counted["ground_truth_correct"].isna()]
    scored = counted[counted["ground_truth_correct"].notna()].copy()
    scored["ground_truth_correct"] = scored["ground_truth_correct"].astype(bool)
    scored["predicted_correct"] = scored["predicted_correct"].astype(bool)
    scored["hit"] = scored["ground_truth_correct"] == scored["predicted_correct"]

    os.makedirs(args.out_dir, exist_ok=True)
    scored.drop(columns=["app_counted_b"]).to_csv(os.path.join(args.out_dir, "all_reps_combined.csv"), index=False)

    # ---- per-exercise metrics ------------------------------------------------
    rows = []
    for ex, g in sorted(scored.groupby("exercise")):
        m = metrics_for(g)
        seen = len(counted[counted["exercise"] == ex]) + len(missed[missed["exercise"] == ex])
        m["rep_detection_rate"] = safe_div(len(counted[counted["exercise"] == ex]), seen)
        m["exercise"] = ex
        m["testers"] = g["tester_id"].nunique()
        rows.append(m)
        cm = pd.DataFrame(
            [[m["TN"], m["FP"]], [m["FN"], m["TP"]]],
            index=["actual: correct", "actual: incorrect"],
            columns=["predicted: correct", "predicted: incorrect"],
        )
        cm.to_csv(os.path.join(args.out_dir, f"confusion_{ex}.csv"))
    overall = metrics_for(scored)
    overall["exercise"] = "OVERALL"
    overall["testers"] = scored["tester_id"].nunique()
    overall["rep_detection_rate"] = safe_div(len(counted), len(counted) + len(missed))
    rows.append(overall)
    metrics = pd.DataFrame(rows).set_index("exercise")
    metrics.to_csv(os.path.join(args.out_dir, "metrics.csv"))

    # ---- breakdowns -------------------------------------------------------------
    by_tester = scored.groupby(["exercise", "tester_id"])["hit"].agg(["sum", "count"])
    by_tester["accuracy"] = by_tester["sum"] / by_tester["count"]
    faults = scored[scored["ground_truth_correct"] == False]  # noqa: E712
    by_fault = (faults.assign(caught=~faults["predicted_correct"])
                .groupby(["exercise", "fault_tag"])["caught"].agg(["sum", "count"]))
    by_fault["detection_rate"] = by_fault["sum"] / by_fault["count"]

    # ---- markdown report --------------------------------------------------------
    L = []
    L.append("# Posture Detection Accuracy - Results\n")
    L.append(f"Source files: {len(files)} | testers: {scored['tester_id'].nunique()} | "
             f"scored reps: {len(scored)} | unlabelled (excluded): {len(unlabelled)} | "
             f"missed by app: {len(missed)}\n")
    L.append("Positive class = **incorrect form** (what the system is meant to catch). "
             f"Target accuracy = {TARGET:.0%}.\n")
    L.append("## Summary\n")
    L.append("| Exercise | Testers | Reps | Accuracy | 95% CI | Precision | Recall | Specificity | F1 | Rep detection | ≥75%? |")
    L.append("|---|---|---|---|---|---|---|---|---|---|---|")
    for ex, m in metrics.iterrows():
        L.append(f"| {ex} | {m['testers']} | {m['n_reps']} | {fmt(m['accuracy'])} | "
                 f"{fmt(m['ci95_low'])}-{fmt(m['ci95_high'])} | {fmt(m['precision_incorrect'])} | "
                 f"{fmt(m['recall_incorrect'])} | {fmt(m['specificity'])} | {fmt(m['f1_incorrect'], False)} | "
                 f"{fmt(m['rep_detection_rate'])} | {'Yes' if m['meets_75pct'] else 'No'} |")
    L.append("")
    L.append("## Confusion matrices\n")
    for ex, m in metrics.iterrows():
        if ex == "OVERALL":
            continue
        L.append(f"**{ex}** (n={m['n_reps']}; {m['n_correct_gt']} correct-form, {m['n_incorrect_gt']} incorrect-form)\n")
        L.append("| | Predicted correct | Predicted incorrect |")
        L.append("|---|---|---|")
        L.append(f"| **Actual correct** | {m['TN']} (TN) | {m['FP']} (FP) |")
        L.append(f"| **Actual incorrect** | {m['FN']} (FN) | {m['TP']} (TP) |")
        L.append("")
    L.append("## Accuracy by tester\n")
    L.append("| Exercise | Tester | Hits | Reps | Accuracy |")
    L.append("|---|---|---|---|---|")
    for (ex, t), r in by_tester.iterrows():
        L.append(f"| {ex} | {t} | {int(r['sum'])} | {int(r['count'])} | {fmt(r['accuracy'])} |")
    L.append("")
    if len(by_fault):
        L.append("## Detection rate by fault type\n")
        L.append("| Exercise | Fault | Caught | Reps | Detection rate |")
        L.append("|---|---|---|---|---|")
        for (ex, ft), r in by_fault.iterrows():
            L.append(f"| {ex} | {ft or '(untagged)'} | {int(r['sum'])} | {int(r['count'])} | {fmt(r['detection_rate'])} |")
        L.append("")
    flipped = int((scored["gt_flipped"].str.lower() == "true").sum())
    L.append(f"_Ground-truth corrections by observer (gt_flipped): {flipped} reps._\n")

    report = "\n".join(L)
    with open(os.path.join(args.out_dir, "summary.md"), "w", encoding="utf-8") as f:
        f.write(report)

    # console
    pd.set_option("display.width", 160)
    cols = ["testers", "n_reps", "accuracy", "ci95_low", "ci95_high", "precision_incorrect",
            "recall_incorrect", "specificity", "rep_detection_rate", "meets_75pct"]
    print(metrics[cols].to_string(float_format=lambda v: f"{v:.3f}"))
    if len(unlabelled):
        print(f"\nWARNING: {len(unlabelled)} reps had no ground-truth label and were excluded.")
    print(f"\nReport written to {os.path.join(args.out_dir, 'summary.md')}")


if __name__ == "__main__":
    main()
