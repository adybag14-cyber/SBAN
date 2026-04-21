import json
from pathlib import Path

root = Path(__file__).resolve().parents[1]
res = root / "docs" / "results"

def load(name: str):
    return json.load(open(res / name))["models"][0]

def acc(model):
    return model["total_correct"] / model["total_predictions"] * 100.0

pairs = [
    ("prefix", load("variant_prefix_v7_best_7bit.json"), load("variant_prefix_v7_best_7bit_fixed.json"), load("variant_prefix_v7_baseline_4bit.json")),
    ("drift", load("variant_drift_v7_best_6bit.json"), load("variant_drift_v7_best_6bit_fixed.json"), load("variant_drift_v7_baseline_4bit.json")),
    ("probe", load("variant_probe_v7_best_6bit.json"), load("variant_probe_v7_best_6bit_fixed.json"), load("variant_probe_v7_baseline_4bit.json")),
]

for name, best, fixed, base in pairs:
    print(f"{name}: best={acc(best):.3f}% fixed={acc(fixed):.3f}% baseline4={acc(base):.3f}%")
    print(f"  delta_vs_fixed={acc(best)-acc(fixed):+.3f} pp")
    print(f"  delta_vs_baseline4={acc(best)-acc(base):+.3f} pp")
