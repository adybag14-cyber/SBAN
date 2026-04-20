#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import subprocess
import time
import zipfile
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any

import matplotlib.pyplot as plt
from matplotlib.patches import FancyArrowPatch, FancyBboxPatch
from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_JUSTIFY
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.lib.utils import ImageReader
from reportlab.platypus import (
    Image,
    KeepTogether,
    PageBreak,
    Paragraph,
    Preformatted,
    SimpleDocTemplate,
    Spacer,
    Table,
    TableStyle,
)

ROOT = Path(__file__).resolve().parents[1]
DATA_DIR = ROOT / "data"
DOCS_DIR = ROOT / "docs"
RESULTS_DIR = DOCS_DIR / "results"
FIGURES_DIR = DOCS_DIR / "figures"
SUMMARY_JSON = RESULTS_DIR / "v4_summary.json"
PAPER_PATH = DOCS_DIR / "research_paper.pdf"
EXEC_SUMMARY_PATH = ROOT / "EXECUTIVE_SUMMARY.md"
README_PATH = ROOT / "README.md"
DEFAULT_ZIG = Path("/mnt/data/zig_toolchain/zig-x86_64-linux-0.17.0-dev.87+9b177a7d2/zig")
DEFAULT_DATASET = Path("/mnt/data/enwik8.zip")
DEFAULT_V3_PREFIX_REF = RESULTS_DIR / "enwik_prefix_v3.json"
DEFAULT_V3_DRIFT_REF = RESULTS_DIR / "enwik_drift_v3.json"

PREFIX_JSON = RESULTS_DIR / "enwik_prefix_v4.json"
DRIFT_JSON = RESULTS_DIR / "enwik_drift_v4.json"
PREFIX_ABLATION_JSON = RESULTS_DIR / "enwik_prefix_ablation_v4.json"
DRIFT_ABLATION_JSON = RESULTS_DIR / "enwik_drift_ablation_v4.json"
LONG_PREFIX_ABLATION_JSON = RESULTS_DIR / "enwik_prefix_long_ablation_v4.json"
ELASTIC_PROBE_JSON = RESULTS_DIR / "elastic_probe_ablation_v4.json"
ELASTIC_PROBE_PATH = DATA_DIR / "elastic_probe.bin"

SWEEP_SEGMENT_LEN = 30_000
LONG_SEGMENT_LEN = 40_000
PROBE_SEGMENT_LEN = 30_000
CHECKPOINT_INTERVAL = 5_000
ROLLING_WINDOW = 4_096
ABLATION_BITS = 4
ELASTIC_START_TARGET = 2_048
ELASTIC_MAX_TARGET = 8_192
ELASTIC_PROBE_SPLIT = 60_050
ELASTIC_PROBE_TOTAL = 120_100


def run(cmd: list[str], cwd: Path = ROOT) -> float:
    print("[run]", " ".join(cmd), flush=True)
    t0 = time.perf_counter()
    subprocess.run(cmd, cwd=cwd, check=True)
    return time.perf_counter() - t0


def ensure_dirs() -> None:
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    RESULTS_DIR.mkdir(parents=True, exist_ok=True)
    FIGURES_DIR.mkdir(parents=True, exist_ok=True)


def ensure_dataset(dataset_arg: Path) -> Path:
    unpacked = DATA_DIR / "enwik8"
    if unpacked.exists() and unpacked.stat().st_size > 0:
        return unpacked
    if dataset_arg.suffix == ".zip":
        with zipfile.ZipFile(dataset_arg, "r") as zf:
            if "enwik8" not in zf.namelist():
                raise RuntimeError("dataset zip did not contain enwik8")
            zf.extract("enwik8", path=DATA_DIR)
        return unpacked
    if dataset_arg.exists() and dataset_arg.name == "enwik8":
        return dataset_arg
    raise FileNotFoundError(dataset_arg)


def ensure_built(zig_bin: Path) -> None:
    run([str(zig_bin), "build", "test"])
    run([str(zig_bin), "build", "-Doptimize=ReleaseFast"])


@dataclass
class ModelStats:
    name: str
    kind: str
    variant: str
    weight_bits: int
    acc: float
    top5: float
    births: int
    bridge_births: int
    short_memories: int
    long_memories: int
    bridge_memories: int
    total_memories: int
    final_regions: int
    final_target_short: int
    synapses: int
    promotions: int
    demotions: int
    recycled_slots: int
    elastic_grows: int
    elastic_shrinks: int
    max_active_regions: int


styles = getSampleStyleSheet()
STYLES = {
    "title": ParagraphStyle(
        "title",
        parent=styles["Title"],
        fontName="Helvetica-Bold",
        fontSize=22,
        leading=26,
        alignment=TA_CENTER,
        textColor=colors.HexColor("#163b66"),
        spaceAfter=6,
    ),
    "subtitle": ParagraphStyle(
        "subtitle",
        parent=styles["BodyText"],
        fontName="Helvetica",
        fontSize=10.5,
        leading=14,
        alignment=TA_CENTER,
        textColor=colors.HexColor("#5b6776"),
        spaceAfter=10,
    ),
    "h1": ParagraphStyle(
        "h1",
        parent=styles["Heading1"],
        fontName="Helvetica-Bold",
        fontSize=16,
        leading=20,
        textColor=colors.HexColor("#163b66"),
        spaceBefore=8,
        spaceAfter=6,
    ),
    "body": ParagraphStyle(
        "body",
        parent=styles["BodyText"],
        fontName="Helvetica",
        fontSize=10.2,
        leading=14,
        alignment=TA_JUSTIFY,
        textColor=colors.HexColor("#222222"),
        spaceAfter=6,
    ),
    "caption": ParagraphStyle(
        "caption",
        parent=styles["BodyText"],
        fontName="Helvetica-Oblique",
        fontSize=8.8,
        leading=11,
        textColor=colors.HexColor("#555555"),
        alignment=TA_JUSTIFY,
        spaceAfter=6,
    ),
    "callout": ParagraphStyle(
        "callout",
        parent=styles["BodyText"],
        fontName="Helvetica",
        fontSize=10.2,
        leading=13.4,
        textColor=colors.HexColor("#1b1f24"),
        alignment=TA_JUSTIFY,
    ),
    "mono": ParagraphStyle(
        "mono",
        parent=styles["Code"],
        fontName="Courier",
        fontSize=8.3,
        leading=10.5,
        textColor=colors.HexColor("#1f2937"),
    ),
    "mono_wrap": ParagraphStyle(
        "mono_wrap",
        parent=styles["BodyText"],
        fontName="Courier",
        fontSize=7.0,
        leading=8.6,
        textColor=colors.HexColor("#1f2937"),
        spaceAfter=4,
    ),
}


def acc(model: dict[str, Any]) -> float:
    return model["total_correct"] / model["total_predictions"]


def top5(model: dict[str, Any]) -> float:
    return model["top5_correct"] / model["total_predictions"]


def pct(value: float) -> str:
    return f"{value * 100:.2f}%"


def pp(value: float) -> str:
    return f"{value * 100:.2f} pp"


def sban_models(experiment: dict[str, Any]) -> list[dict[str, Any]]:
    return [model for model in experiment["models"] if model["kind"] == "sban"]


def model_by_name(experiment: dict[str, Any], name: str) -> dict[str, Any]:
    return next(model for model in experiment["models"] if model["name"] == name)


def maybe_load_json(path: Path) -> dict[str, Any] | None:
    if path.exists():
        return json.loads(path.read_text())
    return None


def model_stats(model: dict[str, Any]) -> ModelStats:
    short_memories = int(model.get("final_short_memories", 0))
    long_memories = int(model.get("final_long_memories", 0))
    total_memories = int(model.get("final_memories", short_memories + long_memories))
    return ModelStats(
        name=model["name"],
        kind=model["kind"],
        variant=model.get("variant", "default"),
        weight_bits=int(model.get("weight_bits", 0)),
        acc=acc(model),
        top5=top5(model),
        births=int(model.get("births", 0)),
        bridge_births=int(model.get("bridge_births", 0)),
        short_memories=short_memories,
        long_memories=long_memories,
        bridge_memories=int(model.get("final_bridge_memories", 0)),
        total_memories=total_memories,
        final_regions=int(model.get("final_regions", 0)),
        final_target_short=int(model.get("final_target_short", 0)),
        synapses=int(model.get("final_synapses", 0)),
        promotions=int(model.get("promotions", 0)),
        demotions=int(model.get("demotions", 0)),
        recycled_slots=int(model.get("recycled_slots", 0)),
        elastic_grows=int(model.get("elastic_grows", 0)),
        elastic_shrinks=int(model.get("elastic_shrinks", 0)),
        max_active_regions=int(model.get("max_active_regions", 0)),
    )


def run_bit_sweep(dataset_path: Path, output_json: Path, mode: str, segment_len: int) -> tuple[dict[str, Any], float]:
    duration = run(
        [
            str(ROOT / "zig-out" / "bin" / "zig_sban"),
            "eval-enwik",
            str(dataset_path),
            str(output_json),
            mode,
            str(segment_len),
            str(CHECKPOINT_INTERVAL),
            str(ROLLING_WINDOW),
        ]
    )
    return json.loads(output_json.read_text()), duration


def run_ablation(dataset_path: Path, output_json: Path, mode: str, bits: int, segment_len: int) -> tuple[dict[str, Any], float]:
    duration = run(
        [
            str(ROOT / "zig-out" / "bin" / "zig_sban"),
            "eval-ablations",
            str(dataset_path),
            str(output_json),
            mode,
            str(bits),
            str(segment_len),
            str(CHECKPOINT_INTERVAL),
            str(ROLLING_WINDOW),
        ]
    )
    return json.loads(output_json.read_text()), duration


def make_elastic_probe(dataset_path: Path) -> Path:
    raw = dataset_path.read_bytes()
    if len(raw) < ELASTIC_PROBE_SPLIT:
        raise RuntimeError("dataset too small for elasticity probe")
    hard = raw[:ELASTIC_PROBE_SPLIT]
    pattern = b"SBANelasticityprobe-"
    easy_len = ELASTIC_PROBE_TOTAL - len(hard)
    easy = (pattern * ((easy_len // len(pattern)) + 1))[:easy_len]
    ELASTIC_PROBE_PATH.write_bytes(hard + easy)
    return ELASTIC_PROBE_PATH


def checkpoint_series(model: dict[str, Any]) -> list[dict[str, int]]:
    return [
        {
            "step": int(cp["step"]),
            "target_short": int(cp.get("target_short", 0)),
            "short_memories": int(cp.get("short_memories", 0)),
            "regions": int(cp.get("regions", 0)),
        }
        for cp in model.get("checkpoints", [])
    ]


def build_summary(
    prefix: dict[str, Any],
    drift: dict[str, Any],
    prefix_ablation: dict[str, Any],
    drift_ablation: dict[str, Any],
    long_prefix_ablation: dict[str, Any],
    probe_ablation: dict[str, Any],
    v3_prefix_ref: dict[str, Any] | None,
    v3_drift_ref: dict[str, Any] | None,
    runtimes: dict[str, float],
) -> dict[str, Any]:
    prefix_rows = [asdict(model_stats(model)) for model in prefix["models"]]
    drift_rows = [asdict(model_stats(model)) for model in drift["models"]]

    prefix_best = max([model_stats(m) for m in sban_models(prefix)], key=lambda row: row.acc)
    drift_best = max([model_stats(m) for m in sban_models(drift)], key=lambda row: row.acc)
    order2_prefix = model_stats(model_by_name(prefix, "markov_order2"))
    order2_drift = model_stats(model_by_name(drift, "markov_order2"))

    default_prefix = model_stats(model_by_name(prefix_ablation, "sban_v4_4bit"))
    no_bridge_prefix = model_stats(model_by_name(prefix_ablation, "sban_v4_4bit_no_bridge"))
    fixed_prefix = model_stats(model_by_name(prefix_ablation, "sban_v4_4bit_fixed_capacity"))
    single_prefix = model_stats(model_by_name(prefix_ablation, "sban_v4_4bit_single_region"))
    no_rep_prefix = model_stats(model_by_name(prefix_ablation, "sban_v4_4bit_no_reputation"))

    default_drift = model_stats(model_by_name(drift_ablation, "sban_v4_4bit"))
    no_bridge_drift = model_stats(model_by_name(drift_ablation, "sban_v4_4bit_no_bridge"))
    fixed_drift = model_stats(model_by_name(drift_ablation, "sban_v4_4bit_fixed_capacity"))
    single_drift = model_stats(model_by_name(drift_ablation, "sban_v4_4bit_single_region"))
    no_rep_drift = model_stats(model_by_name(drift_ablation, "sban_v4_4bit_no_reputation"))

    long_default = model_stats(model_by_name(long_prefix_ablation, "sban_v4_4bit"))
    long_no_bridge = model_stats(model_by_name(long_prefix_ablation, "sban_v4_4bit_no_bridge"))
    long_fixed = model_stats(model_by_name(long_prefix_ablation, "sban_v4_4bit_fixed_capacity"))
    long_single = model_stats(model_by_name(long_prefix_ablation, "sban_v4_4bit_single_region"))
    long_no_rep = model_stats(model_by_name(long_prefix_ablation, "sban_v4_4bit_no_reputation"))
    long_order2 = model_stats(model_by_name(long_prefix_ablation, "markov_order2"))

    probe_default_model = model_by_name(probe_ablation, "sban_v4_4bit")
    probe_no_bridge_model = model_by_name(probe_ablation, "sban_v4_4bit_no_bridge")
    probe_fixed_model = model_by_name(probe_ablation, "sban_v4_4bit_fixed_capacity")
    probe_single_model = model_by_name(probe_ablation, "sban_v4_4bit_single_region")
    probe_no_rep_model = model_by_name(probe_ablation, "sban_v4_4bit_no_reputation")
    probe_order2 = model_stats(model_by_name(probe_ablation, "markov_order2"))
    probe_default = model_stats(probe_default_model)
    probe_no_bridge = model_stats(probe_no_bridge_model)
    probe_fixed = model_stats(probe_fixed_model)
    probe_single = model_stats(probe_single_model)
    probe_no_rep = model_stats(probe_no_rep_model)

    probe_default_series = checkpoint_series(probe_default_model)
    probe_fixed_series = checkpoint_series(probe_fixed_model)
    probe_default_peak_short = max((cp["short_memories"] for cp in probe_default_series), default=0)
    probe_default_final_short = probe_default.short_memories

    payload: dict[str, Any] = {
        "protocol": {
            "main_sweep_segment_len": SWEEP_SEGMENT_LEN,
            "main_segment_count": 4,
            "long_segment_len": LONG_SEGMENT_LEN,
            "probe_segment_len": PROBE_SEGMENT_LEN,
            "checkpoint_interval": CHECKPOINT_INTERVAL,
            "rolling_window": ROLLING_WINDOW,
            "ablation_bits": ABLATION_BITS,
        },
        "runtimes_s": runtimes,
        "prefix_rows": prefix_rows,
        "drift_rows": drift_rows,
        "prefix_best": asdict(prefix_best),
        "drift_best": asdict(drift_best),
        "order2_prefix": asdict(order2_prefix),
        "order2_drift": asdict(order2_drift),
        "prefix_best_delta_vs_order2": prefix_best.acc - order2_prefix.acc,
        "drift_best_delta_vs_order2": drift_best.acc - order2_drift.acc,
        "ablation": {
            "prefix": {
                "default": asdict(default_prefix),
                "no_bridge": asdict(no_bridge_prefix),
                "fixed_capacity": asdict(fixed_prefix),
                "single_region": asdict(single_prefix),
                "no_reputation": asdict(no_rep_prefix),
            },
            "drift": {
                "default": asdict(default_drift),
                "no_bridge": asdict(no_bridge_drift),
                "fixed_capacity": asdict(fixed_drift),
                "single_region": asdict(single_drift),
                "no_reputation": asdict(no_rep_drift),
            },
            "long_prefix": {
                "default": asdict(long_default),
                "no_bridge": asdict(long_no_bridge),
                "fixed_capacity": asdict(long_fixed),
                "single_region": asdict(long_single),
                "no_reputation": asdict(long_no_rep),
                "order2": asdict(long_order2),
            },
        },
        "headline_findings": {
            "reputation_hurt_prefix_pp": (default_prefix.acc - no_rep_prefix.acc) * 100.0,
            "reputation_hurt_drift_pp": (default_drift.acc - no_rep_drift.acc) * 100.0,
            "elastic_vs_fixed_prefix_pp": (default_prefix.acc - fixed_prefix.acc) * 100.0,
            "elastic_vs_fixed_drift_pp": (default_drift.acc - fixed_drift.acc) * 100.0,
            "bridge_delta_prefix_pp": (default_prefix.acc - no_bridge_prefix.acc) * 100.0,
            "bridge_delta_drift_pp": (default_drift.acc - no_bridge_drift.acc) * 100.0,
            "single_region_delta_prefix_pp": (default_prefix.acc - single_prefix.acc) * 100.0,
            "single_region_delta_drift_pp": (default_drift.acc - single_drift.acc) * 100.0,
            "long_prefix_default_delta_vs_order2_pp": (long_default.acc - long_order2.acc) * 100.0,
        },
        "elastic_probe": {
            "default": asdict(probe_default),
            "no_bridge": asdict(probe_no_bridge),
            "fixed_capacity": asdict(probe_fixed),
            "single_region": asdict(probe_single),
            "no_reputation": asdict(probe_no_rep),
            "order2": asdict(probe_order2),
            "default_vs_fixed_pp": (probe_default.acc - probe_fixed.acc) * 100.0,
            "default_vs_order2_pp": (probe_default.acc - probe_order2.acc) * 100.0,
            "default_peak_short_memories": probe_default_peak_short,
            "default_final_short_memories": probe_default_final_short,
            "default_target_start": ELASTIC_START_TARGET,
            "default_target_peak": ELASTIC_MAX_TARGET,
            "default_target_final": probe_default.final_target_short,
            "default_series": probe_default_series,
            "fixed_series": probe_fixed_series,
        },
    }

    if v3_prefix_ref and v3_drift_ref:
        v3_prefix_best = max([model_stats(m) for m in sban_models(v3_prefix_ref)], key=lambda row: row.acc)
        v3_drift_best = max([model_stats(m) for m in sban_models(v3_drift_ref)], key=lambda row: row.acc)
        v3_prefix_4bit = model_stats(model_by_name(v3_prefix_ref, "sban_v3_4bit"))
        v3_drift_4bit = model_stats(model_by_name(v3_drift_ref, "sban_v3_4bit"))
        payload["v3_reference"] = {
            "prefix_best": asdict(v3_prefix_best),
            "drift_best": asdict(v3_drift_best),
            "prefix_4bit": asdict(v3_prefix_4bit),
            "drift_4bit": asdict(v3_drift_4bit),
            "best_prefix_delta_pp": (prefix_best.acc - v3_prefix_best.acc) * 100.0,
            "best_drift_delta_pp": (drift_best.acc - v3_drift_best.acc) * 100.0,
            "prefix_4bit_delta_pp": (default_prefix.acc - v3_prefix_4bit.acc) * 100.0,
            "drift_4bit_delta_pp": (default_drift.acc - v3_drift_4bit.acc) * 100.0,
        }

    SUMMARY_JSON.write_text(json.dumps(payload, indent=2))
    return payload


def plot_architecture(path: Path) -> None:
    fig, ax = plt.subplots(figsize=(13.8, 8.0))
    ax.set_xlim(0, 18.5)
    ax.set_ylim(0, 12.0)
    ax.axis("off")

    def box(x: float, y: float, w: float, h: float, title: str, body: str, face: str, edge: str) -> None:
        patch = FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0.24", linewidth=1.6, facecolor=face, edgecolor=edge)
        ax.add_patch(patch)
        ax.text(x + w / 2.0, y + h - 0.34, title, ha="center", va="top", fontsize=13.0, fontweight="bold")
        ax.text(x + w / 2.0, y + h - 1.0, body, ha="center", va="top", fontsize=9.5, linespacing=1.25)

    def arrow(x1: float, y1: float, x2: float, y2: float, text: str = "", curve: float = 0.0) -> None:
        patch = FancyArrowPatch((x1, y1), (x2, y2), arrowstyle="-|>", mutation_scale=15, linewidth=1.5, connectionstyle=f"arc3,rad={curve}", color="#485569")
        ax.add_patch(patch)
        if text:
            ax.text((x1 + x2) / 2.0, (y1 + y2) / 2.0 + (0.34 if curve >= 0 else -0.34), text, ha="center", va="center", fontsize=9.1)

    box(0.7, 7.05, 2.9, 2.85, "Delay-bank sensory", "Lagged byte banks\nseed context.\nA stable sensory anchor\navoids region-hash drift.", "#f6f9ff", "#4f6b87")
    box(4.0, 7.05, 2.9, 2.85, "Elastic controller", "Tracks surprise, births,\nand live load.\nRaises or lowers the\nshort-memory target.", "#eef8f0", "#50794a")
    box(7.3, 7.05, 3.2, 2.85, "Regional sparse lanes", "Memories carry a region\nidentity. Output votes are\naccumulated in region-local\nscore buffers.", "#fff9ee", "#8a6942")
    box(10.9, 7.05, 2.9, 2.85, "Bridge memories", "Cross-region conjunctive\nmemories are allowed,\nbut gated conservatively\nby diversity and surprise.", "#f7f2ff", "#6b4ea2")
    box(14.2, 7.05, 2.6, 2.85, "Long-term graph", "Promoted memories\ndecay slowly and\ncarry a mild vote\nbonus.", "#edf3ff", "#355d8c")
    box(16.95, 7.28, 1.05, 2.3, "Out", "256\nbyte\nvotes", "#f5f5f5", "#676d77")

    box(3.9, 2.2, 3.4, 2.9, "Reputation and prune", "Accurate pathways gain\nlocal reputation. Weak\nmemories and synapses\nare demoted or deleted.", "#f7fcf4", "#50794a")
    box(8.0, 2.2, 3.6, 2.9, "Homeostasis", "Survivor floors prevent\ncatastrophic collapse.\nDead slots recycle so\nlater growth stays possible.", "#f6f9ff", "#4f6b87")
    box(12.3, 2.2, 4.2, 2.9, "Parallel-ready merge", "Each active region writes\nits own output lane first,\nthen the lanes are merged.\nThis is the main path toward\nfuture parallel kernels.", "#fff8ef", "#8a6942")

    arrow(3.6, 8.45, 4.0, 8.45, "seed")
    arrow(6.9, 8.45, 7.3, 8.45, "target")
    arrow(10.5, 8.45, 10.9, 8.45, "bridge")
    arrow(13.8, 8.45, 14.2, 8.45, "promote")
    arrow(16.8, 8.45, 16.95, 8.45, "vote")
    arrow(17.3, 7.28, 14.9, 5.1, "prediction error", curve=-0.2)
    arrow(14.4, 5.1, 10.0, 7.05, "reputation", curve=0.11)
    arrow(5.6, 5.1, 5.35, 7.05, "grow / shrink", curve=0.05)
    arrow(9.8, 5.1, 8.9, 7.05, "carry / region split", curve=0.16)
    arrow(7.2, 2.9, 7.4, 7.05, "prune / recycle", curve=-0.1)
    arrow(12.0, 3.7, 15.1, 7.05, "lane merge", curve=0.14)

    ax.text(9.2, 11.1, "SBAN v4 runtime cycle", fontsize=20, fontweight="bold", ha="center")
    ax.text(9.2, 10.45, "Elastic memory sizing plus region-parallel sparse lanes and conservative bridge-memory scaffolding", fontsize=11.0, ha="center")
    ax.text(9.2, 0.82, "The key v4 change is not only more machinery: the system can raise or lower its live target during runtime and keeps region-local score lanes that could be parallelized later.", fontsize=10.0, ha="center")
    fig.tight_layout(pad=0.8)
    fig.savefig(path, dpi=220)
    plt.close(fig)


def plot_scaling_comparison(prefix: dict[str, Any], drift: dict[str, Any], v3_prefix: dict[str, Any] | None, v3_drift: dict[str, Any] | None, path: Path) -> None:
    fig, ax = plt.subplots(figsize=(10.8, 5.6))
    bits = [model["weight_bits"] for model in prefix["models"] if model["kind"] == "sban"]
    v4_prefix = [acc(model) for model in prefix["models"] if model["kind"] == "sban"]
    v4_drift = [acc(model) for model in drift["models"] if model["kind"] == "sban"]
    ax.plot(bits, v4_prefix, marker="o", linewidth=2.2, label="SBAN v4 prefix")
    ax.plot(bits, v4_drift, marker="o", linewidth=2.2, label="SBAN v4 drift")
    if v3_prefix and v3_drift:
        ax.plot(bits, [acc(model) for model in v3_prefix["models"] if model["kind"] == "sban"], linestyle="--", linewidth=1.9, label="SBAN v3 prefix ref")
        ax.plot(bits, [acc(model) for model in v3_drift["models"] if model["kind"] == "sban"], linestyle="--", linewidth=1.9, label="SBAN v3 drift ref")
    ax.axhline(acc(model_by_name(prefix, "markov_order2")), linestyle=":", linewidth=1.4, label="Order-2 prefix")
    ax.axhline(acc(model_by_name(drift, "markov_order2")), linestyle=":", linewidth=1.4, label="Order-2 drift")
    ax.set_title("SBAN v4 precision sweep on enwik8 (30k x 4 protocol)")
    ax.set_xlabel("synaptic precision (bits)")
    ax.set_ylabel("top-1 online accuracy")
    ax.set_xticks(bits)
    ax.set_ylim(0.37, 0.44)
    ax.grid(True, alpha=0.25)
    ax.legend(frameon=False, ncol=2)
    fig.tight_layout(pad=1.1)
    fig.savefig(path, dpi=220)
    plt.close(fig)


def plot_ablation_accuracy(prefix_ablation: dict[str, Any], drift_ablation: dict[str, Any], path: Path) -> None:
    ids = [
        "sban_v4_4bit",
        "sban_v4_4bit_no_bridge",
        "sban_v4_4bit_fixed_capacity",
        "sban_v4_4bit_single_region",
        "sban_v4_4bit_no_reputation",
        "markov_order2",
    ]
    labels = [
        "elastic default",
        "no bridge",
        "fixed capacity",
        "single region",
        "no reputation",
        "order-2",
    ]
    prefix_vals = [acc(model_by_name(prefix_ablation, name)) for name in ids]
    drift_vals = [acc(model_by_name(drift_ablation, name)) for name in ids]
    x = list(range(len(labels)))
    width = 0.37
    fig, ax = plt.subplots(figsize=(10.9, 5.9))
    ax.bar([i - width / 2 for i in x], prefix_vals, width=width, label="prefix")
    ax.bar([i + width / 2 for i in x], drift_vals, width=width, label="drift")
    ax.set_title("4-bit v4 ablations: elasticity helps a little, reputation helps a lot")
    ax.set_ylabel("top-1 online accuracy")
    ax.set_xticks(x)
    ax.set_xticklabels(labels, rotation=12, ha="right")
    ax.set_ylim(0.36, 0.44)
    ax.grid(True, axis="y", alpha=0.25)
    ax.legend(frameon=False)
    fig.tight_layout(pad=1.1)
    fig.savefig(path, dpi=220)
    plt.close(fig)


def plot_long_prefix(path: Path, long_prefix_ablation: dict[str, Any]) -> None:
    ids = [
        "sban_v4_4bit",
        "sban_v4_4bit_no_bridge",
        "sban_v4_4bit_fixed_capacity",
        "sban_v4_4bit_single_region",
        "sban_v4_4bit_no_reputation",
        "markov_order2",
    ]
    labels = [
        "elastic",
        "no bridge",
        "fixed cap",
        "single region",
        "no rep",
        "order-2",
    ]
    accs = [acc(model_by_name(long_prefix_ablation, name)) for name in ids]
    memories = [model_by_name(long_prefix_ablation, name).get("final_memories", 0) for name in ids]
    fig, ax1 = plt.subplots(figsize=(10.9, 5.8))
    ax1.bar(labels, accs)
    ax1.set_ylabel("top-1 online accuracy")
    ax1.set_ylim(0.40, 0.43)
    ax1.set_title("Longer 160k-prediction contiguous prefix stress (40k x 4)")
    ax1.grid(True, axis="y", alpha=0.25)
    ax2 = ax1.twinx()
    ax2.plot(labels, memories, marker="o", linewidth=2.0)
    ax2.set_ylabel("final live memories")
    fig.tight_layout(pad=1.1)
    fig.savefig(path, dpi=220)
    plt.close(fig)


def plot_elastic_probe(summary: dict[str, Any], path: Path) -> None:
    probe = summary["elastic_probe"]
    default_series = probe["default_series"]
    fixed_series = probe["fixed_series"]
    x_default = [cp["step"] for cp in default_series]
    target_default = [cp["target_short"] for cp in default_series]
    short_default = [cp["short_memories"] for cp in default_series]
    x_fixed = [cp["step"] for cp in fixed_series]
    target_fixed = [cp["target_short"] for cp in fixed_series]
    short_fixed = [cp["short_memories"] for cp in fixed_series]

    fig, ax1 = plt.subplots(figsize=(10.9, 5.8))
    ax1.plot(x_default, target_default, linewidth=2.2, label="elastic target")
    ax1.plot(x_fixed, target_fixed, linewidth=2.0, linestyle="--", label="fixed-cap target")
    ax1.axvline(60_000, linestyle=":", linewidth=1.6, label="_nolegend_")
    ax1.text(61_000, 7_900, "easy tail starts", fontsize=9.2)
    ax1.set_xlabel("stream step")
    ax1.set_ylabel("target short memories")
    ax1.set_ylim(0, 9000)
    ax1.set_title("Elasticity probe: hard prefix then easy tail")
    ax1.grid(True, alpha=0.25)

    ax2 = ax1.twinx()
    ax2.plot(x_default, short_default, linewidth=2.2, label="elastic live short")
    ax2.plot(x_fixed, short_fixed, linewidth=2.0, linestyle="--", label="fixed-cap live short")
    ax2.set_ylabel("live short memories")
    ax2.set_ylim(0, max(max(short_default, default=0), max(short_fixed, default=0), 1) * 1.12)

    lines = ax1.get_lines() + ax2.get_lines()
    legend_pairs = [(line, line.get_label()) for line in lines if not line.get_label().startswith("_")]
    ax1.legend([pair[0] for pair in legend_pairs], [pair[1] for pair in legend_pairs], frameon=False, ncol=2, loc="upper right")
    fig.tight_layout(pad=1.1)
    fig.savefig(path, dpi=220)
    plt.close(fig)


def make_table(data: list[list[str]], col_widths: list[float] | None = None, header_fill: colors.Color = colors.HexColor("#dbe8ff")) -> Table:
    table = Table(data, colWidths=col_widths, repeatRows=1)
    table.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, 0), header_fill),
                ("TEXTCOLOR", (0, 0), (-1, 0), colors.HexColor("#14324f")),
                ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
                ("FONTNAME", (0, 1), (-1, -1), "Helvetica"),
                ("FONTSIZE", (0, 0), (-1, -1), 8.8),
                ("LEADING", (0, 0), (-1, -1), 10.8),
                ("GRID", (0, 0), (-1, -1), 0.35, colors.HexColor("#cfd7e6")),
                ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, colors.HexColor("#f8fbff")]),
                ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
                ("ALIGN", (1, 1), (-1, -1), "CENTER"),
                ("LEFTPADDING", (0, 0), (-1, -1), 6),
                ("RIGHTPADDING", (0, 0), (-1, -1), 6),
                ("TOPPADDING", (0, 0), (-1, -1), 5),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
            ]
        )
    )
    return table


def figure_block(image_path: Path, caption: str, width_mm: float = 171.0) -> KeepTogether:
    reader = ImageReader(str(image_path))
    width_px, height_px = reader.getSize()
    width = width_mm * mm
    height = width * (height_px / width_px)
    img = Image(str(image_path), width=width, height=height)
    cap = Paragraph(f"<b>Figure.</b> {caption}", STYLES["caption"])
    return KeepTogether([img, Spacer(1, 2 * mm), cap, Spacer(1, 5 * mm)])


def page_number(canvas, doc) -> None:
    canvas.saveState()
    canvas.setFont("Helvetica", 8)
    canvas.setFillColor(colors.HexColor("#666666"))
    canvas.drawRightString(A4[0] - 18 * mm, 10 * mm, f"Page {doc.page}")
    canvas.drawString(18 * mm, 10 * mm, "SBAN v4 research prototype")
    canvas.restoreState()


def write_paper(summary: dict[str, Any]) -> None:
    doc = SimpleDocTemplate(
        str(PAPER_PATH),
        pagesize=A4,
        leftMargin=18 * mm,
        rightMargin=18 * mm,
        topMargin=18 * mm,
        bottomMargin=16 * mm,
        title="SBAN v4 research paper",
        author="OpenAI",
    )

    prefix_best = summary["prefix_best"]
    drift_best = summary["drift_best"]
    comparison = summary.get("v3_reference")
    headline = summary["headline_findings"]
    probe = summary["elastic_probe"]

    story: list[Any] = []
    story.append(Paragraph("SBAN v4: Elastic Regional Synaptic Birth-Death Assembly Networks in Zig", STYLES["title"]))
    story.append(Paragraph("A non-transformer online byte-learning research artifact with runtime growth and shrink targets, region-parallel sparse lanes, and conservative bridge-memory scaffolding on enwik8", STYLES["subtitle"]))
    story.append(Spacer(1, 4 * mm))

    core_callout = (
        f"<b>Core outcome.</b> On the packaged 30k x 4 enwik8 protocol, the best SBAN v4 prefix model is <b>{prefix_best['name']}</b> at <b>{pct(prefix_best['acc'])}</b>, "
        f"beating the order-2 baseline by <b>{pp(summary['prefix_best_delta_vs_order2'])}</b>. The best drift model is <b>{drift_best['name']}</b> at <b>{pct(drift_best['acc'])}</b>, "
        f"beating order-2 by <b>{pp(summary['drift_best_delta_vs_order2'])}</b>. The largest reliable scientific gain remains local self-rating: removing reputation hurts the 4-bit model by <b>{headline['reputation_hurt_prefix_pp']:.2f} pp</b> on prefix and <b>{headline['reputation_hurt_drift_pp']:.2f} pp</b> on drift. On a separate hard-to-easy elasticity probe, the default 4-bit model grows its short-memory target from <b>{probe['default_target_start']}</b> to <b>{probe['default_target_peak']}</b> and then shrinks to <b>{probe['default_target_final']}</b>, while its live short memories collapse from more than <b>{probe['default_peak_short_memories']}</b> to only <b>{probe['default_final_short_memories']}</b>."
    )
    story.append(
        Table(
            [[Paragraph(core_callout, STYLES["callout"])]],
            colWidths=[171 * mm],
            style=TableStyle(
                [
                    ("BACKGROUND", (0, 0), (-1, -1), colors.HexColor("#eef5ff")),
                    ("BOX", (0, 0), (-1, -1), 0.8, colors.HexColor("#9eb7d6")),
                    ("LEFTPADDING", (0, 0), (-1, -1), 8),
                    ("RIGHTPADDING", (0, 0), (-1, -1), 8),
                    ("TOPPADDING", (0, 0), (-1, -1), 7),
                    ("BOTTOMPADDING", (0, 0), (-1, -1), 7),
                ]
            ),
        )
    )
    story.append(Spacer(1, 5 * mm))
    story.append(figure_block(FIGURES_DIR / "sban_v4_architecture.png", "SBAN v4 adds an elastic short-memory target, region-local score lanes, and conservative bridge-memory scaffolding on top of the earlier online sparse graph."))

    story.append(Paragraph("1. Motivation and v4 design changes", STYLES["h1"]))
    story.append(Paragraph(
        "SBAN v3 already established a dual-memory, reputation-gated sparse graph that could learn enwik8 online, but the next research question was architectural scaling rather than only another bit sweep. The user asked for a system that can expand when the stream demands more internal structure and contract when the stream becomes simpler, while also moving toward a more parallel execution path and a more explicit notion of graph substructure. SBAN v4 therefore keeps the v3 local-learning core but rewrites large parts of the runtime around three new ideas: an elastic short-memory target, region-tagged sparse lanes, and a conservative bridge-memory mechanism for cross-region conjunctions.", STYLES["body"]))
    story.append(Paragraph(
        "A practical design issue appeared during early v4 experiments: sensory tokens should not be reassigned to different regions every time the region count changes. Doing that destabilizes regional identity. The implemented v4 scaffold therefore uses a stable sensory anchor and lets new regions emerge from overloaded memory subgraphs rather than from a moving token hash. This makes the regional split a load-balancing and consolidation mechanism, not a changing partition of the raw byte alphabet.", STYLES["body"]))
    story.append(Paragraph(
        "The v4 bridge mechanism is intentionally conservative. It allows a memory to declare both a primary and a secondary region, but only under diversity plus surprise conditions. That choice was made after testing a more eager bridge rule, which created too many cross-region nodes and hurt accuracy. The present v4 artifact should therefore be read as a stronger engineering scaffold for future bridge research rather than as a final solved bridge design.", STYLES["body"]))

    story.append(Paragraph("2. Experimental protocol", STYLES["h1"]))
    story.append(Paragraph(
        "The main evaluation remains fully prequential: at each byte the model predicts the next byte and then updates immediately with the observed target. The packaged rebuild runs four experiment groups. First, a 30k x 4 prefix sweep evaluates 120k contiguous byte predictions on enwik8. Second, a 30k x 4 drift sweep concatenates windows from offsets 0, 25M, 50M, and 75M with transient state reset at boundaries while preserving learned structure. Third, a 40k x 4 longer prefix stress run evaluates the 4-bit ablations. Fourth, a synthetic elasticity probe concatenates 60k real enwik8 bytes with a 60k low-entropy repeated tail so the controller experiences both a hard regime and an easy regime within one run.", STYLES["body"]))
    story.append(Paragraph(
        "The baselines remain online order-1 and order-2 byte predictors. As in earlier SBAN artifacts, the model emits vote scores rather than calibrated probabilities, so the primary metric is top-1 online accuracy; top-5 is reported to separate candidate coverage from final winner selection. The repo also keeps v3 reference JSON so the new scaffold can be compared against the immediately previous artifact under the same 30k x 4 protocol.", STYLES["body"]))

    sweep_table = [["Model", "Prefix top-1", "Drift top-1", "Prefix top-5", "Drift top-5"]]
    for prefix_row, drift_row in zip(summary["prefix_rows"], summary["drift_rows"]):
        if prefix_row["kind"] == "baseline" and prefix_row["name"] == "markov_order1":
            continue
        sweep_table.append([
            prefix_row["name"],
            pct(prefix_row["acc"]),
            pct(drift_row["acc"]),
            pct(prefix_row["top5"]),
            pct(drift_row["top5"]),
        ])
    story.append(make_table(sweep_table, [52 * mm, 26 * mm, 26 * mm, 26 * mm, 26 * mm]))
    story.append(Paragraph("Table 1. SBAN v4 bit sweep on the packaged 30k x 4 prefix and drift protocols. Order-1 is omitted from the discussion below because it stays far below all SBAN variants.", STYLES["caption"]))
    story.append(Spacer(1, 4 * mm))
    story.append(figure_block(FIGURES_DIR / "bit_scaling_v4_vs_v3.png", "Precision scaling for SBAN v4 compared with the bundled v3 reference on the same 30k x 4 protocol. The broad plateau remains, with drift strongest near 5-6 bits."))

    story.append(Paragraph("3. What v4 adds scientifically, and what it costs", STYLES["h1"]))
    if comparison:
        comp_rows = [
            ["Comparison", "Prefix top-1", "Drift top-1"],
            ["SBAN v3 best reference", pct(comparison["prefix_best"]["acc"]), pct(comparison["drift_best"]["acc"])],
            ["SBAN v4 best", pct(prefix_best["acc"]), pct(drift_best["acc"])],
            ["Delta (v4 - v3)", f"{comparison['best_prefix_delta_pp']:+.2f} pp", f"{comparison['best_drift_delta_pp']:+.2f} pp"],
            ["SBAN v3 4-bit", pct(comparison["prefix_4bit"]["acc"]), pct(comparison["drift_4bit"]["acc"])],
            ["SBAN v4 4-bit", pct(summary["ablation"]["prefix"]["default"]["acc"]), pct(summary["ablation"]["drift"]["default"]["acc"])],
            ["4-bit delta (v4 - v3)", f"{comparison['prefix_4bit_delta_pp']:+.2f} pp", f"{comparison['drift_4bit_delta_pp']:+.2f} pp"],
        ]
        story.append(make_table(comp_rows, [60 * mm, 34 * mm, 34 * mm], header_fill=colors.HexColor("#dfeee6")))
        story.append(Paragraph("Table 2. Direct v3-to-v4 comparison on the same 30k x 4 protocol. v4 adds runtime elasticity and regional scaffolding, but the current default does not yet beat v3 on raw top-1.", STYLES["caption"]))
        story.append(Spacer(1, 4 * mm))

    story.append(Paragraph(
        "The comparison is mixed in a scientifically useful way. v4 keeps the earlier sparse non-transformer behavior and adds a real growth-and-shrink control path, but its best top-1 results are slightly below the bundled v3 reference. That means the new machinery is not a free accuracy gain. The right interpretation is that v4 is an architectural scaffold for dynamic scaling, not yet the new best static operating point. This matters because the user asked for a system that changes size during runtime; that requirement forces a different engineering tradeoff than simply tuning the older v3 graph for maximum top-1.", STYLES["body"]))
    story.append(Paragraph(
        "The good news is that the main v4 mechanisms are at least competitive. The default 4-bit elastic model is slightly ahead of the fixed-capacity 4-bit ablation on both prefix and drift, and almost tied with the single-region ablation. The bridge mechanism is the least mature part: on prefix the no-bridge ablation is slightly better, while on drift the default regains a very small lead. In other words, the present bridge rule is safe enough not to collapse the system, but still too weak to become a major source of gain on enwik8.", STYLES["body"]))

    ablation_rows = [["Model", "Prefix top-1", "Drift top-1", "Regions", "Target short", "Bridge births"]]
    for key, label in [
        ("default", "sban_v4_4bit"),
        ("no_bridge", "sban_v4_4bit_no_bridge"),
        ("fixed_capacity", "sban_v4_4bit_fixed_capacity"),
        ("single_region", "sban_v4_4bit_single_region"),
        ("no_reputation", "sban_v4_4bit_no_reputation"),
    ]:
        prow = summary["ablation"]["prefix"][key]
        drow = summary["ablation"]["drift"][key]
        ablation_rows.append([
            label,
            pct(prow["acc"]),
            pct(drow["acc"]),
            str(drow["final_regions"]),
            str(drow["final_target_short"]),
            str(drow["bridge_births"]),
        ])
    ablation_rows.append(["markov_order2", pct(summary["order2_prefix"]["acc"]), pct(summary["order2_drift"]["acc"]), "0", "0", "0"])
    story.append(make_table(ablation_rows, [55 * mm, 24 * mm, 24 * mm, 18 * mm, 24 * mm, 24 * mm], header_fill=colors.HexColor("#efe9d7")))
    story.append(Paragraph("Table 3. The main v4 4-bit ablations. Reputation remains the largest determinant of decisive top-1 accuracy. Bridge births are intentionally sparse in the current scaffold.", STYLES["caption"]))
    story.append(Spacer(1, 4 * mm))
    story.append(figure_block(FIGURES_DIR / "ablation_accuracy_v4.png", "Removing reputation produces the largest collapse. The elastic regional default is slightly ahead of fixed capacity, while the bridge rule is close to neutral on the main enwik8 protocol."))

    story.append(Paragraph("4. Longer contiguous prefix stress", STYLES["h1"]))
    long_rows = [["Model", "Top-1", "Top-5", "Final memories", "Regions", "Target short", "Synapses"]]
    for key, label in [
        ("default", "sban_v4_4bit"),
        ("no_bridge", "sban_v4_4bit_no_bridge"),
        ("fixed_capacity", "sban_v4_4bit_fixed_capacity"),
        ("single_region", "sban_v4_4bit_single_region"),
        ("no_reputation", "sban_v4_4bit_no_reputation"),
    ]:
        row = summary["ablation"]["long_prefix"][key]
        long_rows.append([
            label,
            pct(row["acc"]),
            pct(row["top5"]),
            str(row["total_memories"]),
            str(row["final_regions"]),
            str(row["final_target_short"]),
            str(row["synapses"]),
        ])
    long_rows.append([
        "markov_order2",
        pct(summary["ablation"]["long_prefix"]["order2"]["acc"]),
        pct(summary["ablation"]["long_prefix"]["order2"]["top5"]),
        "0",
        "0",
        "0",
        "0",
    ])
    story.append(make_table(long_rows, [48 * mm, 22 * mm, 22 * mm, 28 * mm, 20 * mm, 24 * mm, 24 * mm], header_fill=colors.HexColor("#efe4f7")))
    story.append(Paragraph("Table 4. Longer 40k x 4 contiguous prefix stress. The elastic default stays above order-2 by more than one point, but the fixed-capacity variant is slightly ahead on this specific longer stress run.", STYLES["caption"]))
    story.append(Spacer(1, 4 * mm))
    story.append(figure_block(FIGURES_DIR / "long_prefix_v4.png", "Longer 160k-prediction prefix stress. The default elastic model remains above the order-2 baseline while ending with fewer than two thousand live memories, but fixed capacity is still a very competitive ablation."))
    story.append(Paragraph(
        f"The longer prefix stress is useful because it separates two questions that are easy to blur together: does the architecture stay adaptive, and does the elasticity controller automatically become the best choice? The answer here is mixed. The default 4-bit elastic model still beats order-2 by <b>{headline['long_prefix_default_delta_vs_order2_pp']:.2f} pp</b> and ends with only <b>{summary['ablation']['long_prefix']['default']['total_memories']}</b> live memories, yet the fixed-capacity ablation edges it out by about <b>{summary['ablation']['long_prefix']['fixed_capacity']['acc'] * 100.0 - summary['ablation']['long_prefix']['default']['acc'] * 100.0:.2f} pp</b>. So v4 elasticity is clearly viable, but not yet the universally best controller on every long run.", STYLES["body"]))

    story.append(Paragraph("5. Elasticity probe: direct evidence of runtime growth and shrink", STYLES["h1"]))
    probe_rows = [["Model", "Accuracy", "Grows", "Shrinks", "Final target", "Final short", "Regions"]]
    for key, label in [
        ("default", "sban_v4_4bit"),
        ("no_bridge", "sban_v4_4bit_no_bridge"),
        ("fixed_capacity", "sban_v4_4bit_fixed_capacity"),
        ("single_region", "sban_v4_4bit_single_region"),
        ("no_reputation", "sban_v4_4bit_no_reputation"),
        ("order2", "markov_order2"),
    ]:
        row = summary["elastic_probe"][key]
        probe_rows.append([
            label,
            pct(row["acc"]),
            str(row.get("elastic_grows", 0)),
            str(row.get("elastic_shrinks", 0)),
            str(row.get("final_target_short", 0)),
            str(row.get("short_memories", 0)),
            str(row.get("final_regions", 0)),
        ])
    story.append(make_table(probe_rows, [50 * mm, 22 * mm, 18 * mm, 18 * mm, 24 * mm, 22 * mm, 17 * mm], header_fill=colors.HexColor("#e2f2ea")))
    story.append(Paragraph("Table 5. Elasticity probe. The default model expands aggressively during the hard half of the stream and then contracts when the stream becomes simple, while fixed capacity obviously cannot change target size at all.", STYLES["caption"]))
    story.append(Spacer(1, 4 * mm))
    story.append(figure_block(FIGURES_DIR / "elasticity_probe_v4.png", "A hard-to-easy probe shows the main v4 controller behavior directly. The elastic default grows to 8192 target short memories on the difficult half, then shrinks to 4608 on the easy tail while live short memories collapse from more than 4600 to roughly 200."))
    story.append(Paragraph(
        f"This probe is the strongest direct evidence that v4 actually satisfies the user request for runtime size adaptation. The default 4-bit model executes <b>{probe['default']['elastic_grows']}</b> growth events and <b>{probe['default']['elastic_shrinks']}</b> shrink events, reaches a peak target of <b>{probe['default_target_peak']}</b>, and ends at <b>{probe['default_target_final']}</b>. It also slightly beats the fixed-capacity 4-bit ablation by <b>{probe['default_vs_fixed_pp']:.2f} pp</b> and the order-2 baseline by <b>{probe['default_vs_order2_pp']:.2f} pp</b>. The important caveat is that region allocation does not yet compact: live memories shrink hard, but the region scaffold itself remains allocated across seven live regions.", STYLES["body"]))

    story.append(PageBreak())
    story.append(Paragraph("6. Interpretation and remaining limitations", STYLES["h1"]))
    story.append(Paragraph(
        "SBAN v4 is therefore best understood as a scientific machine-learning scaffold rather than a final solved architecture. It demonstrates four things clearly: online local self-improvement still works under the new controller, the graph can expand and contract its target size during runtime, regional score lanes are compatible with the sparse graph, and synaptic reputation remains essential for suppressing bad-habit consolidation. Those are meaningful steps toward the user goal of a dynamic, brain-inspired non-transformer model.", STYLES["body"]))
    story.append(Paragraph(
        "At the same time, the new bridge subsystem is not yet paying for itself on the main enwik8 sweep. Bridge births are extremely sparse under the current conservative gate, and the no-bridge ablation is slightly stronger on prefix. The region scaffold also grows but does not compact, so the controller currently changes target size and live memory count more than it changes the structural footprint of the region layout. Finally, v4 does not yet surpass v3 on the main benchmark, so the present result is an engineering broadening rather than a pure accuracy win.", STYLES["body"]))
    story.append(Paragraph(
        "The highest-value next steps are therefore specific. First, bridge memories need a better selection rule, probably one that depends on region-specific error attribution rather than only diversity and surprise. Second, regions need compaction or merge rules so the scaffold can truly shrink structurally rather than only through memory death. Third, the elasticity controller itself is still hand-tuned; a learned or meta-optimized controller may outperform the current threshold schedule. Fourth, the low-bit synapses are still not bit-packed in RAM, and the scores are still not calibrated probabilities, so hardware efficiency and compression metrics remain future work.", STYLES["body"]))

    story.append(Paragraph("7. Reproducibility", STYLES["h1"]))
    story.append(Paragraph(
        "The packaged script rebuilds the Zig binary, reruns the main prefix and drift sweeps, reruns the 4-bit ablations and long stress run, generates the elasticity probe, redraws the figures, rewrites the executive summary and README, and regenerates this PDF. The commands below assume the current repository root and a compatible Zig compiler.", STYLES["body"]))
    reproducibility = f"""<font face="Courier">zig build test<br/>zig build -Doptimize=ReleaseFast<br/>./zig-out/bin/zig_sban eval-enwik data/enwik8 docs/results/enwik_prefix_v4.json prefix {SWEEP_SEGMENT_LEN} {CHECKPOINT_INTERVAL} {ROLLING_WINDOW}<br/>./zig-out/bin/zig_sban eval-enwik data/enwik8 docs/results/enwik_drift_v4.json drift {SWEEP_SEGMENT_LEN} {CHECKPOINT_INTERVAL} {ROLLING_WINDOW}<br/>./zig-out/bin/zig_sban eval-ablations data/enwik8 docs/results/enwik_prefix_ablation_v4.json prefix {ABLATION_BITS} {SWEEP_SEGMENT_LEN} {CHECKPOINT_INTERVAL} {ROLLING_WINDOW}<br/>./zig-out/bin/zig_sban eval-ablations data/enwik8 docs/results/enwik_drift_ablation_v4.json drift {ABLATION_BITS} {SWEEP_SEGMENT_LEN} {CHECKPOINT_INTERVAL} {ROLLING_WINDOW}<br/>./zig-out/bin/zig_sban eval-ablations data/enwik8 docs/results/enwik_prefix_long_ablation_v4.json prefix {ABLATION_BITS} {LONG_SEGMENT_LEN} {CHECKPOINT_INTERVAL} {ROLLING_WINDOW}<br/>python scripts/make_artifacts.py --zig /path/to/zig --dataset /path/to/enwik8.zip</font>"""
    story.append(Paragraph(reproducibility, STYLES["mono_wrap"]))
    story.append(Spacer(1, 1.5 * mm))
    refs = (
        "<b>References</b><br/>"
        "[1] Mahoney, M. Large text compression benchmark corpus (enwik8).<br/>"
        "[2] Lisman, J. (2017). Multiple plasticity processes in glutamatergic synapses. Philosophical Transactions B.<br/>"
        "[3] Bosch, M., and Hayashi, Y. (2012). Structural plasticity of dendritic spines. Current Opinion in Neurobiology.<br/>"
        "[4] Benna, M. K., and Fusi, S. (2016). Computational principles of synaptic memory consolidation. Nature Neuroscience.<br/>"
        "[5] Courbariaux, M., Bengio, Y., and David, J.-P. (2015). BinaryConnect."
    )
    story.append(Paragraph(refs, STYLES["body"]))

    doc.build(story, onFirstPage=page_number, onLaterPages=page_number)


def write_executive_summary(summary: dict[str, Any]) -> None:
    comparison = summary.get("v3_reference")
    headline = summary["headline_findings"]
    probe = summary["elastic_probe"]
    text = f"""# Executive Summary - SBAN v4 Project Status

## Project name

**SBAN v4 - Elastic Regional Synaptic Birth-Death Assembly Network**

## Project goal

Refine SBAN into a more scientifically ambitious online byte-learning system with:

- runtime **growth and shrink** of its memory target,
- region-tagged sparse pathways that can become a basis for future parallel execution,
- conservative **bridge memories** for cross-region conjunctions,
- continued local reputation, promotion, demotion, pruning, and slot recycling,
- reproducible evaluation on real **enwik8** byte streams in Zig.

## Current status

The repo now delivers a working end-to-end **v4 research artifact** with:

- a Zig implementation of elastic short-memory sizing,
- region-local score lanes and region-tagged memories,
- conservative bridge-memory scaffolding,
- 1-bit through 8-bit sweeps on enwik8,
- 4-bit ablation studies,
- a longer contiguous-prefix stress run,
- an explicit **elasticity probe** that demonstrates runtime growth and shrink,
- a regenerated paper, figures, and summary pipeline.

## Main architectural changes from v3

### 1. Elastic short-memory target

SBAN v4 no longer uses only a fixed live-memory target. It can raise or lower its short-memory budget during runtime based on surprise, birth pressure, and utilization.

### 2. Region-tagged sparse lanes

Memories now carry a **region identity**. Output votes are first accumulated inside region-local score buffers and only then merged, which is the main v4 step toward future parallel kernels.

### 3. Conservative bridge memories

A memory can optionally connect a primary and secondary region. The current gate is deliberately conservative because earlier eager bridge rules created too many harmful cross-region nodes.

### 4. Stable sensory anchoring

The v4 implementation keeps sensory bytes on a stable anchor path and lets regions emerge from overloaded memory subgraphs rather than repeatedly reassigning the raw byte alphabet when the region count changes.

### 5. Direct shrink test

The artifact now includes a dedicated hard-to-easy **elasticity probe** so runtime contraction is not only claimed in theory but measured in practice.

## Packaged protocol

The default reproducible artifact uses:

- **Bit sweeps:** 4 x 30k-byte prefix and drift runs on enwik8.
- **Ablations:** 4-bit prefix and drift runs.
- **Long stress:** 4 x 40k-byte contiguous prefix run.
- **Elasticity probe:** 60k real enwik8 bytes followed by a 60k low-entropy tail.

## Main empirical findings

### Best SBAN v4 results on the packaged enwik8 protocol

- Best **prefix** result: **{summary['prefix_best']['name']} = {pct(summary['prefix_best']['acc'])}**
- Prefix **order-2** baseline: **{pct(summary['order2_prefix']['acc'])}**
- Best **drift** result: **{summary['drift_best']['name']} = {pct(summary['drift_best']['acc'])}**
- Drift **order-2** baseline: **{pct(summary['order2_drift']['acc'])}**

### Precision scaling trend

The strongest gains still happen in the move from **1-bit** into the low multi-bit range. Prefix peaks around **4-bit**, while drift is strongest near **5-bit / 6-bit**.

### Reputation-gating result

At 4 bits, removing reputation drops the default model by about **{headline['reputation_hurt_prefix_pp']:.2f} pp** on prefix and **{headline['reputation_hurt_drift_pp']:.2f} pp** on drift. This remains the clearest evidence that local self-rating suppresses bad-habit consolidation.

### Elasticity result on the main protocol

Relative to the 4-bit **fixed-capacity** ablation, the default elastic model is ahead by about **{headline['elastic_vs_fixed_prefix_pp']:.2f} pp** on prefix and **{headline['elastic_vs_fixed_drift_pp']:.2f} pp** on drift. The gain is modest, but it is positive on the main protocol.

### Elasticity probe result

On the dedicated hard-to-easy probe:

- the default 4-bit model grows its target from **{probe['default_target_start']}** to **{probe['default_target_peak']}**,
- then shrinks to **{probe['default_target_final']}**,
- while live short memories collapse from more than **{probe['default_peak_short_memories']}** to **{probe['default_final_short_memories']}**,
- and accuracy is **{pct(probe['default']['acc'])}** versus **{pct(probe['fixed_capacity']['acc'])}** for fixed capacity.

This is the strongest direct evidence that SBAN v4 can actually change its effective size during runtime.

## Comparison with the bundled v3 reference

"""
    if comparison:
        text += f"""- Best v4 prefix is **{comparison['best_prefix_delta_pp']:+.2f} pp** relative to the bundled v3 reference.
- Best v4 drift is **{comparison['best_drift_delta_pp']:+.2f} pp** relative to v3.
- The v4 **4-bit** operating point is **{comparison['prefix_4bit_delta_pp']:+.2f} pp** on prefix and **{comparison['drift_4bit_delta_pp']:+.2f} pp** on drift versus v3 4-bit.

This means v4 broadens the architecture significantly, but it does **not yet surpass v3 on raw top-1**.

"""
    text += f"""## What the current system demonstrates

1. **Runtime self-improvement** on a real byte stream.
2. **Online pattern learning** without offline retraining.
3. **Dynamic size adaptation** through growth and shrink of the short-memory target.
4. A non-transformer sparse graph with **creation, promotion, demotion, and pruning** of structure.
5. A concrete scaffold for future **parallel region-lane execution**.

## Important limitations

1. v4 does **not yet beat v3** on the main enwik8 benchmark.
2. The current **bridge-memory** rule is not yet a clear win; on prefix the no-bridge ablation is slightly stronger.
3. The system can shrink its **target** and live memory count, but it does not yet compact the allocated region scaffold.
4. On hard enwik8 runs the target grows aggressively to the current maximum of **{ELASTIC_MAX_TARGET}**.
5. Scores are still vote values rather than calibrated probabilities.
6. Synapses are still low-bit in logic but **not bit-packed in RAM**.

## Highest-value next steps

### Near term

- Improve bridge selection using region-specific error signals rather than only diversity and surprise.
- Add true **region compaction / merge** so structural footprint can shrink, not only live memories.
- Learn or meta-optimize the elasticity controller.
- Pack synapses and metadata more compactly.

### Mid term

- Build hierarchical multi-region stacks.
- Add explicit asynchronous or SIMD-friendly region kernels.
- Compare against stronger online baselines beyond order-2 Markov.

## Bottom line

SBAN v4 is now a **real Zig scientific artifact** for studying non-transformer online learning with structural plasticity, dynamic memory sizing, region-tagged sparse computation, and conservative bridge-memory scaffolding. The main enwik8 accuracy is still roughly at v3 level rather than above it, but the new artifact now demonstrates something v3 did not: **direct runtime growth and shrink of the model's effective memory budget**.
"""
    EXEC_SUMMARY_PATH.write_text(text)


def write_readme(summary: dict[str, Any]) -> None:
    comparison = summary.get("v3_reference")
    headline = summary["headline_findings"]
    probe = summary["elastic_probe"]
    text = f"""# SBAN v4 - Elastic Regional Synaptic Birth-Death Assembly Network

SBAN v4 is a non-transformer byte-level online learning prototype written in Zig. It extends the earlier SBAN work with:

- elastic runtime growth and shrink of the short-memory target,
- region-tagged sparse memory lanes,
- conservative bridge-memory scaffolding,
- continued local reputation, promotion, demotion, pruning, and slot recycling,
- a reproducible enwik8 and elasticity-probe evaluation pipeline.

## Headline results

- Best prefix model: **{summary['prefix_best']['name']} = {pct(summary['prefix_best']['acc'])}**
- Best drift model: **{summary['drift_best']['name']} = {pct(summary['drift_best']['acc'])}**
- 4-bit no-reputation penalty: **{headline['reputation_hurt_prefix_pp']:.2f} pp** on prefix and **{headline['reputation_hurt_drift_pp']:.2f} pp** on drift
- Elasticity probe: target grows **{probe['default_target_start']} -> {probe['default_target_peak']}** and shrinks to **{probe['default_target_final']}**

## What changed in v4

### Elastic controller

The model can raise or lower its short-memory target during runtime based on surprise, birth pressure, and utilization.

### Region lanes

Memories carry a region identity. Output scores are accumulated in region-local buffers before merge, which is the main v4 move toward future parallel execution.

### Bridge memories

Cross-region conjunctions are allowed, but conservatively. The current bridge rule is a scaffold, not yet a final tuned subsystem.

### Stable sensory anchor

The implementation avoids region-hash drift by keeping the raw sensory path stable and letting regions emerge from memory overload instead.

## Rebuild

```bash
zig build test
zig build -Doptimize=ReleaseFast
python scripts/make_artifacts.py --zig /path/to/zig --dataset /path/to/enwik8.zip
```

## Main result files

- `docs/results/enwik_prefix_v4.json`
- `docs/results/enwik_drift_v4.json`
- `docs/results/enwik_prefix_ablation_v4.json`
- `docs/results/enwik_drift_ablation_v4.json`
- `docs/results/enwik_prefix_long_ablation_v4.json`
- `docs/results/elastic_probe_ablation_v4.json`
- `docs/results/v4_summary.json`
- `docs/research_paper.pdf`

## Scientific reading of the current artifact

The v4 scaffold clearly demonstrates dynamic runtime resizing and keeps competitive online accuracy on enwik8, but it is not yet a pure accuracy upgrade over v3.

"""
    if comparison:
        text += f"""- Best v4 prefix vs v3 best: **{comparison['best_prefix_delta_pp']:+.2f} pp**
- Best v4 drift vs v3 best: **{comparison['best_drift_delta_pp']:+.2f} pp**
- v4 4-bit vs v3 4-bit: **{comparison['prefix_4bit_delta_pp']:+.2f} pp** on prefix and **{comparison['drift_4bit_delta_pp']:+.2f} pp** on drift

"""
    text += f"""The right interpretation is therefore: **v4 broadens the architecture and validates runtime elasticity**, while the next work should focus on bridge selection, region compaction, and controller optimization.
"""
    README_PATH.write_text(text)


def main() -> None:
    parser = argparse.ArgumentParser(description="Rebuild SBAN v4 experiments, figures, summary, and paper")
    parser.add_argument("--zig", type=Path, default=DEFAULT_ZIG)
    parser.add_argument("--dataset", type=Path, default=DEFAULT_DATASET)
    parser.add_argument("--v3_prefix_ref", type=Path, default=DEFAULT_V3_PREFIX_REF)
    parser.add_argument("--v3_drift_ref", type=Path, default=DEFAULT_V3_DRIFT_REF)
    args = parser.parse_args()

    ensure_dirs()
    dataset_path = ensure_dataset(args.dataset)
    ensure_built(args.zig)

    runtimes: dict[str, float] = {}
    prefix, runtimes["prefix_sweep"] = run_bit_sweep(dataset_path, PREFIX_JSON, "prefix", SWEEP_SEGMENT_LEN)
    drift, runtimes["drift_sweep"] = run_bit_sweep(dataset_path, DRIFT_JSON, "drift", SWEEP_SEGMENT_LEN)
    prefix_ablation, runtimes["prefix_ablation"] = run_ablation(dataset_path, PREFIX_ABLATION_JSON, "prefix", ABLATION_BITS, SWEEP_SEGMENT_LEN)
    drift_ablation, runtimes["drift_ablation"] = run_ablation(dataset_path, DRIFT_ABLATION_JSON, "drift", ABLATION_BITS, SWEEP_SEGMENT_LEN)
    long_prefix_ablation, runtimes["long_prefix_ablation"] = run_ablation(dataset_path, LONG_PREFIX_ABLATION_JSON, "prefix", ABLATION_BITS, LONG_SEGMENT_LEN)

    probe_path = make_elastic_probe(dataset_path)
    probe_ablation, runtimes["elastic_probe"] = run_ablation(probe_path, ELASTIC_PROBE_JSON, "prefix", ABLATION_BITS, PROBE_SEGMENT_LEN)

    v3_prefix_ref = maybe_load_json(args.v3_prefix_ref)
    v3_drift_ref = maybe_load_json(args.v3_drift_ref)
    summary = build_summary(prefix, drift, prefix_ablation, drift_ablation, long_prefix_ablation, probe_ablation, v3_prefix_ref, v3_drift_ref, runtimes)

    plot_architecture(FIGURES_DIR / "sban_v4_architecture.png")
    plot_scaling_comparison(prefix, drift, v3_prefix_ref, v3_drift_ref, FIGURES_DIR / "bit_scaling_v4_vs_v3.png")
    plot_ablation_accuracy(prefix_ablation, drift_ablation, FIGURES_DIR / "ablation_accuracy_v4.png")
    plot_long_prefix(FIGURES_DIR / "long_prefix_v4.png", long_prefix_ablation)
    plot_elastic_probe(summary, FIGURES_DIR / "elasticity_probe_v4.png")

    write_paper(summary)
    write_executive_summary(summary)
    write_readme(summary)
    print(f"[OK] wrote summary to {SUMMARY_JSON}")
    print(f"[OK] wrote paper to {PAPER_PATH}")
    print(f"[OK] wrote executive summary to {EXEC_SUMMARY_PATH}")
    print(f"[OK] wrote README to {README_PATH}")


if __name__ == "__main__":
    main()
