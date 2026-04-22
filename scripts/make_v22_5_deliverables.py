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
RESULTS = ROOT / "docs" / "results" / "v22_5"
PAPERS = ROOT / "docs" / "papers"
DELIV = ROOT / "deliverables" / "v22_5"
DEMO_DELIV = DELIV / "demo"
DOWNLOADS = Path.home() / "Downloads"
DESKTOP = Path.home() / "Desktop"
BIN = ROOT / "zig-out" / "bin" / ("zig_sban.exe" if os.name == "nt" else "zig_sban")

PAPERS.mkdir(parents=True, exist_ok=True)
DELIV.mkdir(parents=True, exist_ok=True)
DEMO_DELIV.mkdir(parents=True, exist_ok=True)
DOWNLOADS.mkdir(parents=True, exist_ok=True)
DESKTOP.mkdir(parents=True, exist_ok=True)

V22 = {
    "prefix": 99.6350,
    "drift": 99.5400,
    "probe": 99.9000,
    "long_250k": 99.4076,
    "long_1m": 99.4344,
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
    out: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        out[key.strip()] = value.strip()
    return out


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


prefix = primary_accuracy(RESULTS / "unified_prefix_v22_5_release.json")
drift = primary_accuracy(RESULTS / "unified_drift_v22_5_release.json")
probe = primary_accuracy(RESULTS / "unified_probe_v22_5_release.json")
long_250k = primary_accuracy(RESULTS / "longrun_v22_5_250k.json")
long_1m = primary_accuracy(RESULTS / "longrun_v22_5_1m.json")
long_10m = primary_accuracy(RESULTS / "longrun_v22_5_10m.json")

chat_hybrid = parse_chat_summary(RESULTS / "chat_eval_v22_5_hybrid.txt")
chat_free = parse_chat_summary(RESULTS / "chat_eval_v22_5_free.txt")
session_eval = parse_session_summary(RESULTS / "chat_session_eval_v22_5.txt")
cpu_mt_info = parse_key_values(RESULTS / "accel_info_v22_5_cpu_mt.txt")
cuda_info = parse_key_values(RESULTS / "accel_info_v22_5_cuda.txt")
accel_bench = load_json(RESULTS / "accel_bench_v22_5.json")
numeric_backend = load_json(RESULTS / "numeric_backend_v22_5.json")

overview_demo = (RESULTS / "chat_demo_v22_5_overview.txt").read_text(encoding="utf-8").strip()
rtx_demo = (RESULTS / "chat_demo_v22_5_rtx.txt").read_text(encoding="utf-8").strip()
numeric_demo = (RESULTS / "chat_demo_v22_5_numeric_fallback.txt").read_text(encoding="utf-8").strip()
uncertainty_demo = (RESULTS / "chat_demo_v22_5_uncertainty.txt").read_text(encoding="utf-8").strip()

cuda_speedup = float(accel_bench["speedup_cuda_vs_cpu"])
cpu_mt_speedup = float(accel_bench["speedup_cpu_mt_vs_cpu"])

report_md = f"""# SBAN v22.5 Follow-up Research Paper

## Release intent

SBAN v22.5 is the technical point release after v22.

The user-facing grounded dialogue contract from v22 stays intact. The point release focuses on backend realism: real NVIDIA CUDA support, a measured accelerator benchmark, conservative multithreaded retrieval support, and an experimental multithreaded numeric scorer that is kept off the shipped numeric profile when it does not show a dependable gain.

## What changed in v22.5

1. Added a real CUDA retrieval backend for NVIDIA RTX-class GPUs through the NVIDIA driver API.
2. Added the `accel-bench` command so raw retrieval throughput can be measured directly instead of inferring backend quality from full chat timings.
3. Added a conservative `cpu_mt` retrieval path with explicit worker control and an automatic cap tuned toward four workers instead of blindly using every core.
4. Added an experimental multithreaded numeric output scorer in `src/network.zig` while preserving the exact single-thread path and keeping the release suite on that proven fallback.
5. Updated the dialogue assets and product copy so the runtime can explain the v22.5 technical release itself.

## Numeric engine-health results

| Test | V22 baseline | V22.5 packaged | Delta |
|---|---:|---:|---:|
| Prefix | {fmt(V22['prefix'])} | {fmt(prefix)} | {prefix - V22['prefix']:+.4f} pp |
| Drift | {fmt(V22['drift'])} | {fmt(drift)} | {drift - V22['drift']:+.4f} pp |
| Probe | {fmt(V22['probe'])} | {fmt(probe)} | {probe - V22['probe']:+.4f} pp |
| 250k | {fmt(V22['long_250k'])} | {fmt(long_250k)} | {long_250k - V22['long_250k']:+.4f} pp |
| 1M | {fmt(V22['long_1m'])} | {fmt(long_1m)} | {long_1m - V22['long_1m']:+.4f} pp |

- 10M hardening accuracy: **{fmt(long_10m)}**
- The shipped numeric suite stays on `score_threads=1`.

## Runtime and accelerator results

- Hybrid chat eval: **{chat_hybrid['nonempty']} / {chat_hybrid['turns']}** non-empty, **{chat_hybrid['anchored']}** anchored, **{chat_hybrid['symbolic']}** symbolic
- Free chat eval: **{chat_free['nonempty']} / {chat_free['turns']}** non-empty, **{chat_free['anchored']}** anchored, **{chat_free['symbolic']}** symbolic
- Scripted session eval: **{session_eval['passed']} / {session_eval['expectations']}** expectation checks passed
- `cpu_mt` accel-info: backend `{cpu_mt_info.get('backend', 'unknown')}`, workers `{cpu_mt_info.get('worker_threads', 'unknown')}`
- CUDA accel-info: backend `{cuda_info.get('backend', 'unknown')}`, platform `{cuda_info.get('platform', 'unknown')}`, device `{cuda_info.get('device', 'unknown')}`

### Raw retrieval accelerator bench

- CPU elapsed: **{float(accel_bench['cpu']['elapsed_seconds']):.3f}s**
- `cpu_mt` elapsed: **{float(accel_bench['cpu_mt']['elapsed_seconds']):.3f}s** with speedup **{cpu_mt_speedup:.4f}x** vs CPU
- CUDA elapsed: **{float(accel_bench['cuda']['elapsed_seconds']):.3f}s** with speedup **{cuda_speedup:.4f}x** vs CPU

The key practical result is that CUDA is materially faster on the larger grounded retrieval corpus used for the raw bench, while the multithreaded numeric scorer does not yet beat the single-thread numeric release profile reliably enough to replace it.

### Numeric backend probe

- 250k single-thread elapsed: **{float(numeric_backend['release_st_250k']['elapsed_seconds']):.3f}s**
- 250k mt4 elapsed: **{float(numeric_backend['parallel_mt4_250k']['elapsed_seconds']):.3f}s**
- 1M single-thread elapsed: **{float(numeric_backend['release_st_1m']['elapsed_seconds']):.3f}s**
- 1M mt4 elapsed: **{float(numeric_backend['parallel_mt4_1m']['elapsed_seconds']):.3f}s**

## Concrete behavior

### Release overview

```text
{overview_demo}
```

### NVIDIA CUDA support

```text
{rtx_demo}
```

### Numeric fallback stance

```text
{numeric_demo}
```

### Honest uncertainty remains intact

```text
{uncertainty_demo}
```

## Interpretation

V22.5 is not a new dialogue generation strategy. It is the release where SBAN's acceleration story becomes honest and measurable.

The system now has a real NVIDIA CUDA backend, an explicit raw retrieval benchmark, and an experimental multithreaded numeric scorer. The release still prefers the old single-thread numeric profile when the new path does not win, which is exactly the behavior a technical point release should have.
"""

summary_md = f"""# SBAN v22.5 Executive Summary

SBAN v22.5 is the technical point release after v22. It keeps the v22 grounded dialogue behavior and numeric engine-health baseline stable while adding a real CUDA retrieval backend for NVIDIA RTX GPUs, a raw accelerator benchmark command, conservative multithreaded retrieval support, and an experimental multithreaded numeric scorer.

Measured release outcomes:

- Prefix: {fmt(prefix)}
- Drift: {fmt(drift)}
- Probe: {fmt(probe)}
- 250k: {fmt(long_250k)}
- 1M: {fmt(long_1m)}
- 10M: {fmt(long_10m)}
- Hybrid chat eval: {chat_hybrid['nonempty']}/{chat_hybrid['turns']} non-empty
- Session eval: {session_eval['passed']}/{session_eval['expectations']} passed

Acceleration outcome:

- CUDA raw retrieval bench speedup vs CPU: {cuda_speedup:.4f}x
- CPU_MT raw retrieval bench speedup vs CPU: {cpu_mt_speedup:.4f}x
- Shipped numeric suite remains on single-thread fallback because the multithreaded numeric path did not show a dependable win on the release profile.
"""

report_path = ROOT / "SBAN_v22_5_REPORT.md"
summary_path = ROOT / "SBAN_v22_5_EXECUTIVE_SUMMARY.md"
paper_path = PAPERS / "SBAN_v22_5_follow_up_research_paper.pdf"
repo_zip = DELIV / "SBAN_v22_5_repo.zip"

report_path.write_text(report_md, encoding="utf-8")
summary_path.write_text(summary_md, encoding="utf-8")
render_markdown_to_pdf(report_path, paper_path)
write_repo_zip(repo_zip)

if BIN.exists():
    platform = "windows_x86_64" if os.name == "nt" else "linux_x86_64"
    subprocess.run(
        ["python", "scripts/package_v22_5_demo.py", "--binary", str(BIN), "--platform", platform],
        cwd=ROOT,
        check=True,
    )

recipe_md = """# SBAN v22.5 Reproduction Recipe

## Build

```bash
zig build test
zig build -Doptimize=ReleaseFast
```

## Run the technical release suite

```bash
python scripts/run_v22_5_release.py --skip-build
python scripts/make_v22_5_deliverables.py
```

## Important runtime notes

- The shipped numeric suite uses `score_threads=1`.
- The experimental multithreaded numeric scorer can be explored with `score_threads=4 parallel_score_min_predictive_nodes=128`.
- The grounded retrieval runtime can be inspected with:

```bash
zig-out/bin/zig_sban accel-info seed_path=data/sban_dialogue_seed_v22.txt backend=cpu_mt threads=4
zig-out/bin/zig_sban accel-info seed_path=data/sban_dialogue_seed_v22.txt backend=cuda
```

## Raw accelerator benchmark

```bash
zig-out/bin/zig_sban accel-bench docs/results/v22_5/accel_prompts_v22_5_bench.txt backend=cpu seed_path=docs/results/v22_5/accel_seed_v22_5_bench.txt iterations=4
zig-out/bin/zig_sban accel-bench docs/results/v22_5/accel_prompts_v22_5_bench.txt backend=cpu_mt threads=4 seed_path=docs/results/v22_5/accel_seed_v22_5_bench.txt iterations=4
zig-out/bin/zig_sban accel-bench docs/results/v22_5/accel_prompts_v22_5_bench.txt backend=cuda seed_path=docs/results/v22_5/accel_seed_v22_5_bench.txt iterations=4
```

## Verify the discrete NVIDIA GPU

```bash
zig-out/bin/zig_sban accel-info seed_path=data/sban_dialogue_seed_v22.txt backend=cuda
nvidia-smi --query-gpu=name,utilization.gpu,utilization.memory,temperature.gpu,power.draw --format=csv
nvidia-smi --query-compute-apps=pid,process_name,used_gpu_memory --format=csv
```

## One-shot chat checks

```bash
zig-out/bin/zig_sban chat-demo "what is SBAN v22.5" 160 seed_path=data/sban_dialogue_seed_v22.txt backend=cpu
zig-out/bin/zig_sban chat-demo "do you support nvidia rtx gpus" 160 seed_path=data/sban_dialogue_seed_v22.txt backend=cpu
zig-out/bin/zig_sban chat-demo "is multithreaded numeric scoring the default" 160 seed_path=data/sban_dialogue_seed_v22.txt backend=cpu
```
"""
recipe_path = DESKTOP / "SBAN_v22_5_reproduction_recipe.md"
recipe_path.write_text(recipe_md, encoding="utf-8")

for path in [report_path, summary_path, paper_path, repo_zip, recipe_path]:
    shutil.copy2(path, DOWNLOADS / path.name)

for demo_zip in DEMO_DELIV.glob("SBAN_v22_5_*_demo.zip"):
    shutil.copy2(demo_zip, DOWNLOADS / demo_zip.name)
