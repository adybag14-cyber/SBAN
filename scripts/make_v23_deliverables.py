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
RESULTS = ROOT / "docs" / "results" / "v23"
PAPERS = ROOT / "docs" / "papers"
DELIV = ROOT / "deliverables" / "v23"
DEMO_DELIV = DELIV / "demo"
DOWNLOADS = Path.home() / "Downloads"
DESKTOP = Path.home() / "Desktop"
BIN = ROOT / "zig-out" / "bin" / ("zig_sban.exe" if os.name == "nt" else "zig_sban")

PAPERS.mkdir(parents=True, exist_ok=True)
DELIV.mkdir(parents=True, exist_ok=True)
DEMO_DELIV.mkdir(parents=True, exist_ok=True)
DOWNLOADS.mkdir(parents=True, exist_ok=True)
DESKTOP.mkdir(parents=True, exist_ok=True)

V22_5 = {
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


prefix = primary_accuracy(RESULTS / "unified_prefix_v23_release.json")
drift = primary_accuracy(RESULTS / "unified_drift_v23_release.json")
probe = primary_accuracy(RESULTS / "unified_probe_v23_release.json")
long_250k = primary_accuracy(RESULTS / "longrun_v23_250k.json")
long_1m = primary_accuracy(RESULTS / "longrun_v23_1m.json")
long_10m = primary_accuracy(RESULTS / "longrun_v23_10m.json")

chat_hybrid = parse_chat_summary(RESULTS / "chat_eval_v23_hybrid.txt")
chat_free = parse_chat_summary(RESULTS / "chat_eval_v23_free.txt")
session_eval = parse_session_summary(RESULTS / "chat_session_eval_v23.txt")
cpu_mt_info = parse_key_values(RESULTS / "accel_info_v23_cpu_mt.txt")
cuda_info = parse_key_values(RESULTS / "accel_info_v23_cuda.txt")
accel_bench = load_json(RESULTS / "accel_bench_v23.json")
numeric_backend = load_json(RESULTS / "numeric_backend_v23.json")

overview_demo = (RESULTS / "chat_demo_v23_overview.txt").read_text(encoding="utf-8").strip()
paper_demo = (RESULTS / "chat_demo_v23_paper.txt").read_text(encoding="utf-8").strip()
cuda_command_demo = (RESULTS / "chat_demo_v23_cuda_command.txt").read_text(encoding="utf-8").strip()
rtx_demo = (RESULTS / "chat_demo_v23_rtx.txt").read_text(encoding="utf-8").strip()
joke_demo = (RESULTS / "chat_demo_v23_joke.txt").read_text(encoding="utf-8").strip()
uncertainty_demo = (RESULTS / "chat_demo_v23_uncertainty.txt").read_text(encoding="utf-8").strip()
nvidia_smi_text = (RESULTS / "nvidia_smi_v23.txt").read_text(encoding="utf-8").strip() if (RESULTS / "nvidia_smi_v23.txt").exists() else "not captured"

cuda_speedup = float(accel_bench["speedup_cuda_vs_cpu"])
cpu_mt_speedup = float(accel_bench["speedup_cpu_mt_vs_cpu"])

report_md = f"""# SBAN v23 Follow-up Research Paper

## Release intent

SBAN v23 is the conversational repair release after v22.5.

The point of v23 is not another numeric leap. The release keeps the established numeric engine-health suite stable while repairing the actual product runtime: a real v23 chat seed, broader operational and hardware coverage, safer retrieval on paraphrases, stronger natural session memory, and a default free-chat loop that is no longer just hybrid retrieval with generation disabled.

## What changed in v23

1. Replaced the stale v22.5 dialogue asset with a real `data/sban_dialogue_seed_v23.txt` seed that knows the v23 starter files, artifact paths, release inventory, CUDA commands, backend comparisons, and roadmap stance.
2. Tightened retrieval with semantic guards so hardware prompts and artifact questions do not overmatch unrelated benchmark blurbs.
3. Broadened paraphrase coverage through new seed entries plus stronger lexical canonicalization for change, compare, launch, command, overview, bundle, path, and hardware wording.
4. Upgraded session memory extraction so natural phrases like `i am from london` and `i work in the sbx lab` are stored correctly instead of being misread as names or ignored.
5. Replaced the old unsafe-feeling free-chat fallback with constrained conversational synthesis for greetings, identity, thanks, light small talk, and other safe prompts.
6. Kept the real CUDA path, cpu-mt retrieval path, accelerator bench, and experimental numeric multithread probe from v22.5, and revalidated them after the local NVIDIA driver update.

## Numeric engine-health results

| Test | V22.5 baseline | V23 packaged | Delta |
|---|---:|---:|---:|
| Prefix | {fmt(V22_5['prefix'])} | {fmt(prefix)} | {prefix - V22_5['prefix']:+.4f} pp |
| Drift | {fmt(V22_5['drift'])} | {fmt(drift)} | {drift - V22_5['drift']:+.4f} pp |
| Probe | {fmt(V22_5['probe'])} | {fmt(probe)} | {probe - V22_5['probe']:+.4f} pp |
| 250k | {fmt(V22_5['long_250k'])} | {fmt(long_250k)} | {long_250k - V22_5['long_250k']:+.4f} pp |
| 1M | {fmt(V22_5['long_1m'])} | {fmt(long_1m)} | {long_1m - V22_5['long_1m']:+.4f} pp |
| 10M | {fmt(V22_5['long_10m'])} | {fmt(long_10m)} | {long_10m - V22_5['long_10m']:+.4f} pp |

- The shipped numeric suite still stays on `score_threads=1`.

## Chat and product results

- Hybrid chat eval: **{chat_hybrid['nonempty']} / {chat_hybrid['turns']}** non-empty, **{chat_hybrid['anchored']}** anchored, **{chat_hybrid['retrieved']}** retrieved, **{chat_hybrid['symbolic']}** symbolic
- Free chat eval: **{chat_free['nonempty']} / {chat_free['turns']}** non-empty, **{chat_free['anchored']}** anchored, **{chat_free['retrieved']}** retrieved, **{chat_free['symbolic']}** symbolic
- Scripted session eval: **{session_eval['passed']} / {session_eval['expectations']}** expectation checks passed

The free-chat path is the main user-facing improvement. It can now answer operational questions about files and commands, handle a few safe open-domain prompts, and keep more natural session facts without regressing into stale v22 paths.

## Accelerator results

- `cpu_mt` accel-info: backend `{cpu_mt_info.get('backend', 'unknown')}`, workers `{cpu_mt_info.get('worker_threads', 'unknown')}`
- CUDA accel-info: backend `{cuda_info.get('backend', 'unknown')}`, platform `{cuda_info.get('platform', 'unknown')}`, device `{cuda_info.get('device', 'unknown')}`
- Captured `nvidia-smi`: `{nvidia_smi_text}`

### Raw retrieval accelerator bench

- CPU elapsed: **{float(accel_bench['cpu']['elapsed_seconds']):.3f}s**
- `cpu_mt` elapsed: **{float(accel_bench['cpu_mt']['elapsed_seconds']):.3f}s** with speedup **{cpu_mt_speedup:.4f}x** vs CPU
- CUDA elapsed: **{float(accel_bench['cuda']['elapsed_seconds']):.3f}s** with speedup **{cuda_speedup:.4f}x** vs CPU

CUDA remains the preferred large-corpus retrieval accelerator on this NVIDIA system. The driver update did not break the CUDA probe or the raw accelerator path.

### Numeric backend probe

- 250k single-thread elapsed: **{float(numeric_backend['release_st_250k']['elapsed_seconds']):.3f}s**
- 250k mt4 elapsed: **{float(numeric_backend['parallel_mt4_250k']['elapsed_seconds']):.3f}s**
- 1M single-thread elapsed: **{float(numeric_backend['release_st_1m']['elapsed_seconds']):.3f}s**
- 1M mt4 elapsed: **{float(numeric_backend['parallel_mt4_1m']['elapsed_seconds']):.3f}s**

The multithreaded numeric path is still available for experiments, but it does not yet earn default release status.

## Concrete behavior

### Overview

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

V23 is the release where SBAN's chat runtime finally stops feeling like a narrowly seeded retrieval demo. It still does not pretend to have broad transformer-style world knowledge, but it now answers more of its own operational questions correctly, carries more natural session facts across turns, avoids obvious retrieval overmatches, and handles a useful slice of free conversation without losing its grounding discipline.
"""

summary_md = f"""# SBAN v23 Executive Summary

SBAN v23 is the conversational repair release after v22.5. The numeric engine-health suite stays stable, CUDA support remains healthy on the local NVIDIA system, and the user-facing runtime now ships with a real v23 chat seed plus stronger operational, retrieval, memory, and free-chat behavior.

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

Product outcome:

- starter files, artifact paths, CUDA commands, backend comparisons, RTX support questions, and roadmap prompts now have grounded v23 answers
- natural fact memory now handles phrases such as `i am from london` and `i work in the sbx lab`
- free chat can answer greetings, identity, thanks, favorite-color style small talk, and jokes without collapsing into stale release blurbs
- noise prompts still decline honestly

Acceleration outcome:

- CUDA raw retrieval bench speedup vs CPU: {cuda_speedup:.4f}x
- CPU_MT raw retrieval bench speedup vs CPU: {cpu_mt_speedup:.4f}x
- shipped numeric suite remains on single-thread fallback because the multithreaded numeric path still has not shown a dependable release-profile win
"""

report_path = ROOT / "SBAN_v23_REPORT.md"
summary_path = ROOT / "SBAN_v23_EXECUTIVE_SUMMARY.md"
paper_path = PAPERS / "SBAN_v23_follow_up_research_paper.pdf"
repo_zip = DELIV / "SBAN_v23_repo.zip"

report_path.write_text(report_md, encoding="utf-8")
summary_path.write_text(summary_md, encoding="utf-8")
render_markdown_to_pdf(report_path, paper_path)
write_repo_zip(repo_zip)

if BIN.exists():
    platform = "windows_x86_64" if os.name == "nt" else "linux_x86_64"
    subprocess.run(
        ["python", "scripts/package_v23_demo.py", "--binary", str(BIN), "--platform", platform],
        cwd=ROOT,
        check=True,
    )

recipe_md = """# SBAN v23 Reproduction Recipe

## Build

If `zig` is not on `PATH`, pass `--zig-exe` to the release script or use the extracted local toolchain path.

```bash
zig build test
zig build -Doptimize=ReleaseFast
```

## Run the v23 release suite

```bash
python scripts/run_v23_release.py --skip-build
python scripts/make_v23_deliverables.py
```

## Important runtime notes

- The shipped numeric suite still uses `score_threads=1`.
- The experimental multithreaded numeric scorer can be explored with `score_threads=4 parallel_score_min_predictive_nodes=128`.
- The default product chat loop is now free mode with safe conversational composition enabled.

## Inspect the backend paths

```bash
zig-out/bin/zig_sban accel-info seed_path=data/sban_dialogue_seed_v23.txt backend=cpu_mt threads=4
zig-out/bin/zig_sban accel-info seed_path=data/sban_dialogue_seed_v23.txt backend=cuda
```

## Raw accelerator benchmark

```bash
zig-out/bin/zig_sban accel-bench docs/results/v23/accel_prompts_v23_bench.txt backend=cpu seed_path=docs/results/v23/accel_seed_v23_bench.txt iterations=4
zig-out/bin/zig_sban accel-bench docs/results/v23/accel_prompts_v23_bench.txt backend=cpu_mt threads=4 seed_path=docs/results/v23/accel_seed_v23_bench.txt iterations=4
zig-out/bin/zig_sban accel-bench docs/results/v23/accel_prompts_v23_bench.txt backend=cuda seed_path=docs/results/v23/accel_seed_v23_bench.txt iterations=4
```

## Verify the discrete NVIDIA GPU and driver

```bash
zig-out/bin/zig_sban accel-info seed_path=data/sban_dialogue_seed_v23.txt backend=cuda
nvidia-smi --query-gpu=name,driver_version --format=csv,noheader
```

## One-shot chat checks

```bash
zig-out/bin/zig_sban chat-demo "what is SBAN v23" 180 seed_path=data/sban_dialogue_seed_v23.txt backend=cpu mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "what command shows cuda support" 180 seed_path=data/sban_dialogue_seed_v23.txt backend=cpu mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "where is the v23 paper pdf" 180 seed_path=data/sban_dialogue_seed_v23.txt backend=cpu mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "tell me a joke" 180 seed_path=data/sban_dialogue_seed_v23.txt backend=cpu mode=free allow_generation=true
```
"""
recipe_path = DESKTOP / "SBAN_v23_reproduction_recipe.md"
recipe_path.write_text(recipe_md, encoding="utf-8")

for path in [report_path, summary_path, paper_path, repo_zip, recipe_path]:
    shutil.copy2(path, DOWNLOADS / path.name)

for demo_zip in DEMO_DELIV.glob("SBAN_v23_*_demo.zip"):
    shutil.copy2(demo_zip, DOWNLOADS / demo_zip.name)
