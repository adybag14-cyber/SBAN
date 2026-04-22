#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import zipfile
from pathlib import Path

from md_to_pdf_reportlab import render_markdown_to_pdf

ROOT = Path(__file__).resolve().parents[1]
RESULTS = ROOT / "docs" / "results" / "v23_5"
PAPERS = ROOT / "docs" / "papers"
DELIV = ROOT / "deliverables" / "v23_5"
DEMO_DELIV = DELIV / "demo"
DOWNLOADS = Path.home() / "Downloads"
DESKTOP = Path.home() / "Desktop"
BIN = ROOT / "zig-out" / "bin" / ("zig_sban.exe" if os.name == "nt" else "zig_sban")

PAPERS.mkdir(parents=True, exist_ok=True)
DELIV.mkdir(parents=True, exist_ok=True)
DEMO_DELIV.mkdir(parents=True, exist_ok=True)
DOWNLOADS.mkdir(parents=True, exist_ok=True)
DESKTOP.mkdir(parents=True, exist_ok=True)

BASELINE = {
    "prefix": 99.6350,
    "drift": 99.5400,
    "probe": 99.9000,
    "long_250k": 99.4076,
    "long_1m": 99.4344,
    "long_10m": 77.9175,
}


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def primary_accuracy(path: Path) -> float:
    data = load_json(path)
    model = data["models"][0]
    return 100.0 * model["total_correct"] / model["total_predictions"]


def fmt(value: float) -> str:
    return f"{value:.4f}%"


def parse_chat_summary(path: Path) -> dict[str, int]:
    text = path.read_text(encoding="utf-8")
    match = re.search(r"summary turns=(\d+) anchored=(\d+) retrieved=(\d+) symbolic=(\d+) nonempty=(\d+)", text)
    if not match:
        raise ValueError(f"missing chat summary line in {path}")
    return {
        "turns": int(match.group(1)),
        "anchored": int(match.group(2)),
        "retrieved": int(match.group(3)),
        "symbolic": int(match.group(4)),
        "nonempty": int(match.group(5)),
    }


def parse_session_summary(path: Path) -> dict[str, int]:
    text = path.read_text(encoding="utf-8")
    match = re.search(
        r"summary turns=(\d+) anchored=(\d+) retrieved=(\d+) symbolic=(\d+) nonempty=(\d+) expectations=(\d+) passed=(\d+)",
        text,
    )
    if not match:
        raise ValueError(f"missing session summary line in {path}")
    return {
        "turns": int(match.group(1)),
        "anchored": int(match.group(2)),
        "retrieved": int(match.group(3)),
        "symbolic": int(match.group(4)),
        "nonempty": int(match.group(5)),
        "expectations": int(match.group(6)),
        "passed": int(match.group(7)),
    }


def parse_key_values(path: Path) -> dict[str, str]:
    parsed: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        parsed[key.strip()] = value.strip()
    return parsed


def write_repo_zip(output_path: Path) -> None:
    exclude_names = {".git", ".zig-cache", "zig-out", "__pycache__", "deliverables"}
    excluded_files = {
        Path("data") / "enwik8",
        Path("data") / "wikitext2_train_seed.txt",
    }
    output_path.parent.mkdir(parents=True, exist_ok=True)
    if output_path.exists():
        output_path.unlink()
    with zipfile.ZipFile(output_path, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as zf:
        for path in ROOT.rglob("*"):
            rel = path.relative_to(ROOT)
            if any(part in exclude_names for part in rel.parts):
                continue
            if rel in excluded_files:
                continue
            if len(rel.parts) >= 3 and rel.parts[0] == "docs" and rel.parts[1] == "results" and "_tune" in rel.parts[2]:
                continue
            if path == output_path or path.is_dir():
                continue
            zf.write(path, rel.as_posix())


prefix = primary_accuracy(RESULTS / "unified_prefix_v23_5_release.json")
drift = primary_accuracy(RESULTS / "unified_drift_v23_5_release.json")
probe = primary_accuracy(RESULTS / "unified_probe_v23_5_release.json")
long_250k = primary_accuracy(RESULTS / "longrun_v23_5_250k.json")
long_1m = primary_accuracy(RESULTS / "longrun_v23_5_1m.json")
long_10m = primary_accuracy(RESULTS / "longrun_v23_5_10m.json")

chat_hybrid = parse_chat_summary(RESULTS / "chat_eval_v23_5_hybrid.txt")
chat_free = parse_chat_summary(RESULTS / "chat_eval_v23_5_free.txt")
session_eval = parse_session_summary(RESULTS / "chat_session_eval_v23_5.txt")

retrieval_cpu_mt_info = parse_key_values(RESULTS / "accel_info_v23_5_cpu_mt.txt")
retrieval_cuda_info = parse_key_values(RESULTS / "accel_info_v23_5_cuda.txt")
numeric_cpu_info = parse_key_values(RESULTS / "numeric_accel_info_v23_5_cpu.txt")
numeric_cpu_mt_info = parse_key_values(RESULTS / "numeric_accel_info_v23_5_cpu_mt.txt")
numeric_cuda_info = parse_key_values(RESULTS / "numeric_accel_info_v23_5_cuda.txt")

accel_bench = load_json(RESULTS / "accel_bench_v23_5.json")
numeric_backend = load_json(RESULTS / "numeric_backend_v23_5.json")

overview_demo = (RESULTS / "chat_demo_v23_5_overview.txt").read_text(encoding="utf-8").strip()
paper_demo = (RESULTS / "chat_demo_v23_5_paper.txt").read_text(encoding="utf-8").strip()
cuda_command_demo = (RESULTS / "chat_demo_v23_5_cuda_command.txt").read_text(encoding="utf-8").strip()
rtx_demo = (RESULTS / "chat_demo_v23_5_rtx.txt").read_text(encoding="utf-8").strip()
joke_demo = (RESULTS / "chat_demo_v23_5_joke.txt").read_text(encoding="utf-8").strip()
uncertainty_demo = (RESULTS / "chat_demo_v23_5_uncertainty.txt").read_text(encoding="utf-8").strip()
nvidia_smi_text = (RESULTS / "nvidia_smi_v23_5.txt").read_text(encoding="utf-8").strip() if (RESULTS / "nvidia_smi_v23_5.txt").exists() else "not captured"

retrieval_cuda_speedup = float(accel_bench["speedup_cuda_vs_cpu"])
retrieval_cpu_mt_speedup = float(accel_bench["speedup_cpu_mt_vs_cpu"])
numeric_cuda_speedup_250k = float(numeric_backend["speedup_cuda_vs_cpu_250k"])
numeric_cpu_mt_speedup_250k = float(numeric_backend["speedup_cpu_mt_vs_cpu_250k"])
numeric_cuda_speedup_1m = float(numeric_backend["speedup_cuda_vs_cpu_1m"])
numeric_cpu_mt_speedup_1m = float(numeric_backend["speedup_cpu_mt_vs_cpu_1m"])

report_md = f"""# SBAN v23.5 Follow-up Research Paper

## Release intent

SBAN v23.5 is the technical backend upgrade after v23.

The goal is to keep the packaged numeric engine-health suite locked to the proven CPU baseline while extending measured CUDA support deeper into the runtime. In practical terms, v23.5 keeps the v23 conversational surface, preserves the regression-safe `numeric_backend=cpu` release profile, adds a real numeric CUDA backend for `eval-variant` experimentation, exposes a `numeric-accel-info` probe command, and measures CPU versus `cpu_mt` versus CUDA on both the dialogue retrieval path and the numeric scoring path.

## What changed in v23.5

1. Added a numeric scoring backend selector in `src/network.zig` so the runtime can choose `cpu`, `cpu_mt`, or `cuda` for predictive output scoring without changing the learning semantics.
2. Added a dedicated sparse numeric CUDA kernel in `src/numeric_cuda.zig` and kept CPU fallback automatic when CUDA is unavailable or not selected.
3. Preserved the original single-thread CPU path as the packaged release baseline and regression reference.
4. Added `numeric-accel-info` in `src/main.zig` so the numeric path can report whether it actually sees and uses the requested backend.
5. Re-versioned the shipped dialogue assets and demo bundle to `v23.5` so the release no longer reports stale v23 file names.
6. Re-ran the original numeric suite, the v23 conversation checks, the dialogue retrieval accelerator bench, and a new numeric backend comparison matrix after the local NVIDIA driver update.

## Packaged numeric engine-health results

| Test | Baseline | V23.5 packaged | Delta |
|---|---:|---:|---:|
| Prefix | {fmt(BASELINE['prefix'])} | {fmt(prefix)} | {prefix - BASELINE['prefix']:+.4f} pp |
| Drift | {fmt(BASELINE['drift'])} | {fmt(drift)} | {drift - BASELINE['drift']:+.4f} pp |
| Probe | {fmt(BASELINE['probe'])} | {fmt(probe)} | {probe - BASELINE['probe']:+.4f} pp |
| 250k | {fmt(BASELINE['long_250k'])} | {fmt(long_250k)} | {long_250k - BASELINE['long_250k']:+.4f} pp |
| 1M | {fmt(BASELINE['long_1m'])} | {fmt(long_1m)} | {long_1m - BASELINE['long_1m']:+.4f} pp |
| 10M | {fmt(BASELINE['long_10m'])} | {fmt(long_10m)} | {long_10m - BASELINE['long_10m']:+.4f} pp |

- The shipped numeric suite still runs on `numeric_backend=cpu` with `score_threads=1`.
- That preserves the original regression baseline while the newer backends are measured separately.

## Conversation and product checks

- Hybrid chat eval: **{chat_hybrid['nonempty']} / {chat_hybrid['turns']}** non-empty, **{chat_hybrid['anchored']}** anchored, **{chat_hybrid['retrieved']}** retrieved, **{chat_hybrid['symbolic']}** symbolic
- Free chat eval: **{chat_free['nonempty']} / {chat_free['turns']}** non-empty, **{chat_free['anchored']}** anchored, **{chat_free['retrieved']}** retrieved, **{chat_free['symbolic']}** symbolic
- Scripted session eval: **{session_eval['passed']} / {session_eval['expectations']}** expectation checks passed

The v23 conversational surface stayed intact while being re-versioned to `v23.5`. The product runtime still answers operational artifact questions, hardware prompts, session-memory prompts, and safe small-talk prompts without regressing into stale paths.

## Retrieval accelerator results

- `cpu_mt` retrieval probe: backend `{retrieval_cpu_mt_info.get('backend', 'unknown')}`, workers `{retrieval_cpu_mt_info.get('worker_threads', 'unknown')}`
- CUDA retrieval probe: backend `{retrieval_cuda_info.get('backend', 'unknown')}`, platform `{retrieval_cuda_info.get('platform', 'unknown')}`, device `{retrieval_cuda_info.get('device', 'unknown')}`
- Captured `nvidia-smi`: `{nvidia_smi_text}`

### Raw retrieval accelerator bench

- CPU elapsed: **{float(accel_bench['cpu']['elapsed_seconds']):.3f}s**
- `cpu_mt` elapsed: **{float(accel_bench['cpu_mt']['elapsed_seconds']):.3f}s** with speedup **{retrieval_cpu_mt_speedup:.4f}x** vs CPU
- CUDA elapsed: **{float(accel_bench['cuda']['elapsed_seconds']):.3f}s** with speedup **{retrieval_cuda_speedup:.4f}x** vs CPU

CUDA remains the preferred large-corpus retrieval accelerator on this NVIDIA system.

## Numeric backend results

- Numeric CPU probe: configured `{numeric_cpu_info.get('configured_backend', 'unknown')}`, used `{numeric_cpu_info.get('backend_used', 'unknown')}`
- Numeric `cpu_mt` probe: configured `{numeric_cpu_mt_info.get('configured_backend', 'unknown')}`, used `{numeric_cpu_mt_info.get('backend_used', 'unknown')}`
- Numeric CUDA probe: configured `{numeric_cuda_info.get('configured_backend', 'unknown')}`, used `{numeric_cuda_info.get('backend_used', 'unknown')}`, CUDA enabled `{numeric_cuda_info.get('cuda_enabled', 'unknown')}`, device `{numeric_cuda_info.get('device', 'unknown')}`

### Numeric backend timing matrix

| Run | CPU | `cpu_mt` | CUDA |
|---|---:|---:|---:|
| 250k elapsed | {float(numeric_backend['release_cpu_250k']['elapsed_seconds']):.3f}s | {float(numeric_backend['release_cpu_mt4_250k']['elapsed_seconds']):.3f}s | {float(numeric_backend['release_cuda_250k']['elapsed_seconds']):.3f}s |
| 1M elapsed | {float(numeric_backend['release_cpu_1m']['elapsed_seconds']):.3f}s | {float(numeric_backend['release_cpu_mt4_1m']['elapsed_seconds']):.3f}s | {float(numeric_backend['release_cuda_1m']['elapsed_seconds']):.3f}s |

- 250k `cpu_mt` speedup vs CPU: **{numeric_cpu_mt_speedup_250k:.4f}x**
- 250k CUDA speedup vs CPU: **{numeric_cuda_speedup_250k:.4f}x**
- 1M `cpu_mt` speedup vs CPU: **{numeric_cpu_mt_speedup_1m:.4f}x**
- 1M CUDA speedup vs CPU: **{numeric_cuda_speedup_1m:.4f}x**

These numbers decide whether the accelerated numeric backends deserve promotion. The release keeps the old CPU fallback as the default unless the measured end-to-end suite actually wins.

## Concrete runtime behavior

### Overview answer

```text
{overview_demo}
```

### Artifact path answer

```text
{paper_demo}
```

### CUDA command answer

```text
{cuda_command_demo}
```

### RTX support answer

```text
{rtx_demo}
```

### Open-domain joke answer

```text
{joke_demo}
```

### Noise prompt still declines cleanly

```text
{uncertainty_demo}
```

## Interpretation

V23.5 is a backend release with a strict trust boundary: keep the conversation surface stable, keep the numeric baseline honest, and only promote acceleration where the measurements prove it. The important architectural result is that CUDA is no longer confined to dialogue retrieval; it now reaches the numeric output-scoring stack too, while the original CPU path remains intact as the safe default.
"""

summary_md = f"""# SBAN v23.5 Executive Summary

SBAN v23.5 is the technical backend upgrade after v23. The packaged numeric suite stays on the original single-thread CPU baseline, the v23 conversational runtime remains stable, and CUDA now reaches both the dialogue retrieval path and the numeric output-scoring path.

Measured release outcomes:

- Prefix: {fmt(prefix)}
- Drift: {fmt(drift)}
- Probe: {fmt(probe)}
- 250k: {fmt(long_250k)}
- 1M: {fmt(long_1m)}
- 10M: {fmt(long_10m)}
- Hybrid chat eval: {chat_hybrid['nonempty']}/{chat_hybrid['turns']} non-empty
- Free chat eval: {chat_free['nonempty']}/{chat_free['turns']} non-empty
- Session eval: {session_eval['passed']}/{session_eval['expectations']} passed

Backend outcome:

- Retrieval CUDA speedup vs CPU: {retrieval_cuda_speedup:.4f}x
- Retrieval `cpu_mt` speedup vs CPU: {retrieval_cpu_mt_speedup:.4f}x
- Numeric CUDA speedup vs CPU at 250k: {numeric_cuda_speedup_250k:.4f}x
- Numeric CUDA speedup vs CPU at 1M: {numeric_cuda_speedup_1m:.4f}x
- Numeric CUDA probe: configured `{numeric_cuda_info.get('configured_backend', 'unknown')}`, used `{numeric_cuda_info.get('backend_used', 'unknown')}`, device `{numeric_cuda_info.get('device', 'unknown')}`

Release stance:

- keep `numeric_backend=cpu` and `score_threads=1` as the packaged default until accelerated numeric runs prove a dependable end-to-end win
- keep the v23 grounded chat behavior and versioned assets intact for end users
- expose `numeric-accel-info` plus measured CPU versus `cpu_mt` versus CUDA timing so future tuning can be guided by data rather than guesswork
"""

report_path = ROOT / "SBAN_v23_5_REPORT.md"
summary_path = ROOT / "SBAN_v23_5_EXECUTIVE_SUMMARY.md"
paper_path = PAPERS / "SBAN_v23_5_follow_up_research_paper.pdf"
repo_zip = DELIV / "SBAN_v23_5_repo.zip"

report_path.write_text(report_md, encoding="utf-8")
summary_path.write_text(summary_md, encoding="utf-8")
render_markdown_to_pdf(report_path, paper_path)
write_repo_zip(repo_zip)

if BIN.exists():
    platform = "windows_x86_64" if os.name == "nt" else "linux_x86_64"
    subprocess.run(
        ["python", "scripts/package_v23_5_demo.py", "--binary", str(BIN), "--platform", platform],
        cwd=ROOT,
        check=True,
    )

recipe_md = """# SBAN v23.5 Reproduction Recipe

## Build

If `zig` is not on `PATH`, pass `--zig-exe` to the release script or use the extracted local toolchain path.

```bash
zig build test
zig build -Doptimize=ReleaseFast
```

## Run the measured v23.5 release suite

```bash
python scripts/run_v23_5_release.py --skip-build
python scripts/make_v23_5_deliverables.py
```

## Important runtime notes

- The packaged numeric suite stays on `numeric_backend=cpu` and `score_threads=1`.
- The experimental numeric host-threaded path can be explored with `numeric_backend=cpu_mt score_threads=4 parallel_score_min_predictive_nodes=128`.
- The experimental numeric CUDA path can be explored with `numeric_backend=cuda cuda_min_scoring_edges=1`.
- The default product chat loop remains `backend=cpu mode=free allow_generation=true`.

## Inspect the backend paths

```bash
zig-out/bin/zig_sban accel-info seed_path=data/sban_dialogue_seed_v23_5.txt backend=cpu_mt threads=4
zig-out/bin/zig_sban accel-info seed_path=data/sban_dialogue_seed_v23_5.txt backend=cuda
zig-out/bin/zig_sban numeric-accel-info numeric_backend=cpu
zig-out/bin/zig_sban numeric-accel-info numeric_backend=cpu_mt score_threads=4 parallel_score_min_predictive_nodes=1
zig-out/bin/zig_sban numeric-accel-info numeric_backend=cuda cuda_min_scoring_edges=1
```

## Raw retrieval accelerator benchmark

```bash
zig-out/bin/zig_sban accel-bench docs/results/v23_5/accel_prompts_v23_5_bench.txt backend=cpu seed_path=docs/results/v23_5/accel_seed_v23_5_bench.txt iterations=4
zig-out/bin/zig_sban accel-bench docs/results/v23_5/accel_prompts_v23_5_bench.txt backend=cpu_mt threads=4 seed_path=docs/results/v23_5/accel_seed_v23_5_bench.txt iterations=4
zig-out/bin/zig_sban accel-bench docs/results/v23_5/accel_prompts_v23_5_bench.txt backend=cuda seed_path=docs/results/v23_5/accel_seed_v23_5_bench.txt iterations=4
```

## Numeric backend probes

```bash
zig-out/bin/zig_sban eval-variant data/enwik8 docs/results/v23_5/probe_cpu_longrun_v23_5_250k.json prefix 4 default 62500 5000 4096 label=sban_v23_5_release_250k_cpu_probe enable_long_term=false history_lags=32 birth_margin=21 min_parents_for_birth=4 max_carry_memories=48 max_hidden_per_hop=32 propagation_depth=2 birth_pressure_threshold_bonus=0 birth_saturation_threshold_bonus=0 birth_saturation_parent_boost=0 hybrid_share_ppm=0 hybrid_recent_drift_bonus=0 recent_markov2_bonus_ppm=0 burst_bonus_ppm=520 markov1_bonus_ppm=340 markov2_bonus_ppm=760 markov3_bonus_ppm=1900 markov4_bonus_ppm=2400 markov5_bonus_ppm=2800 continuation_bonus_ppm=8000 continuation_min_order=8 continuation_max_order=32 continuation_support_prior=0 continuation_min_support=1 hybrid_support_prior=0 hybrid_evidence_prior=0 score_threads=1 numeric_backend=cpu sequence_seed_path=data/enwik8 sequence_seed_offset=0 sequence_seed_length=1000000
zig-out/bin/zig_sban eval-variant data/enwik8 docs/results/v23_5/probe_cuda_longrun_v23_5_250k.json prefix 4 default 62500 5000 4096 label=sban_v23_5_release_250k_cuda_probe enable_long_term=false history_lags=32 birth_margin=21 min_parents_for_birth=4 max_carry_memories=48 max_hidden_per_hop=32 propagation_depth=2 birth_pressure_threshold_bonus=0 birth_saturation_threshold_bonus=0 birth_saturation_parent_boost=0 hybrid_share_ppm=0 hybrid_recent_drift_bonus=0 recent_markov2_bonus_ppm=0 burst_bonus_ppm=520 markov1_bonus_ppm=340 markov2_bonus_ppm=760 markov3_bonus_ppm=1900 markov4_bonus_ppm=2400 markov5_bonus_ppm=2800 continuation_bonus_ppm=8000 continuation_min_order=8 continuation_max_order=32 continuation_support_prior=0 continuation_min_support=1 hybrid_support_prior=0 hybrid_evidence_prior=0 score_threads=1 numeric_backend=cuda cuda_min_scoring_edges=1 sequence_seed_path=data/enwik8 sequence_seed_offset=0 sequence_seed_length=1000000
```

## One-shot chat checks

```bash
zig-out/bin/zig_sban chat-demo "what is SBAN v23.5" 180 seed_path=data/sban_dialogue_seed_v23_5.txt backend=cpu mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "what command shows numeric cuda support" 180 seed_path=data/sban_dialogue_seed_v23_5.txt backend=cpu mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "where is the v23.5 paper pdf" 180 seed_path=data/sban_dialogue_seed_v23_5.txt backend=cpu mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "tell me a joke" 180 seed_path=data/sban_dialogue_seed_v23_5.txt backend=cpu mode=free allow_generation=true
```
"""

recipe_path = DESKTOP / "SBAN_v23_5_reproduction_recipe.md"
recipe_path.write_text(recipe_md, encoding="utf-8")

for path in [report_path, summary_path, paper_path, repo_zip, recipe_path]:
    shutil.copy2(path, DOWNLOADS / path.name)

for demo_zip in DEMO_DELIV.glob("SBAN_v23_5_*_demo.zip"):
    shutil.copy2(demo_zip, DOWNLOADS / demo_zip.name)
