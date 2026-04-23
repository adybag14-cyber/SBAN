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
RESULTS = ROOT / "docs" / "results" / "v27"
PAPERS = ROOT / "docs" / "papers"
DELIV = ROOT / "deliverables" / "v27"
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
    match = re.search(r"summary turns=(\d+) anchored=(\d+) retrieved=(\d+) symbolic=(\d+) nonempty=(\d+) uncertain=(\d+)", text)
    if not match:
        raise ValueError(f"missing chat summary line in {path}")
    return {
        "turns": int(match.group(1)),
        "anchored": int(match.group(2)),
        "retrieved": int(match.group(3)),
        "symbolic": int(match.group(4)),
        "nonempty": int(match.group(5)),
        "uncertain": int(match.group(6)),
    }


def parse_session_summary(path: Path) -> dict[str, int]:
    text = path.read_text(encoding="utf-8")
    match = re.search(
        r"summary turns=(\d+) anchored=(\d+) retrieved=(\d+) symbolic=(\d+) nonempty=(\d+) uncertain=(\d+) expectations=(\d+) passed=(\d+)",
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
        "uncertain": int(match.group(6)),
        "expectations": int(match.group(7)),
        "passed": int(match.group(8)),
    }


def parse_key_values(path: Path) -> dict[str, str]:
    parsed: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        parsed[key.strip()] = value.strip()
    return parsed


def find_completed_100m_json() -> Path | None:
    candidates = sorted((ROOT / "docs" / "results").rglob("longrun*_100m*.json"))
    return candidates[-1] if candidates else None


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


prefix = primary_accuracy(RESULTS / "unified_prefix_v27_release.json")
drift = primary_accuracy(RESULTS / "unified_drift_v27_release.json")
probe = primary_accuracy(RESULTS / "unified_probe_v27_release.json")
long_250k = primary_accuracy(RESULTS / "longrun_v27_250k.json")
long_1m = primary_accuracy(RESULTS / "longrun_v27_1m.json")
long_10m = primary_accuracy(RESULTS / "longrun_v27_10m.json")
long_20m = primary_accuracy(RESULTS / "longrun_v27_20m.json")

chat_hybrid = parse_chat_summary(RESULTS / "chat_eval_v27_hybrid.txt")
chat_free = parse_chat_summary(RESULTS / "chat_eval_v27_free.txt")
session_eval = parse_session_summary(RESULTS / "chat_session_eval_v27.txt")
open_session_eval = parse_session_summary(RESULTS / "open_chat_session_eval_v27.txt")
broad_session_eval = parse_session_summary(RESULTS / "broad_chat_session_eval_v27.txt")

retrieval_cpu_mt_info = parse_key_values(RESULTS / "accel_info_v27_cpu_mt.txt")
retrieval_cuda_info = parse_key_values(RESULTS / "accel_info_v27_cuda.txt")
numeric_cpu_info = parse_key_values(RESULTS / "numeric_accel_info_v27_cpu.txt")
numeric_cpu_mt_info = parse_key_values(RESULTS / "numeric_accel_info_v27_cpu_mt.txt")
numeric_cuda_info = parse_key_values(RESULTS / "numeric_accel_info_v27_cuda.txt")

accel_bench = load_json(RESULTS / "accel_bench_v27.json")
numeric_backend = load_json(RESULTS / "numeric_backend_v27.json")

overview_demo = (RESULTS / "chat_demo_v27_overview.txt").read_text(encoding="utf-8").strip()
bundle_demo = (RESULTS / "chat_demo_v27_bundle.txt").read_text(encoding="utf-8").strip()
paper_demo = (RESULTS / "chat_demo_v27_paper.txt").read_text(encoding="utf-8").strip()
cuda_command_demo = (RESULTS / "chat_demo_v27_cuda_command.txt").read_text(encoding="utf-8").strip()
memory_demo = (RESULTS / "chat_demo_v27_memory_capability.txt").read_text(encoding="utf-8").strip()
planning_demo = (RESULTS / "chat_demo_v27_planning.txt").read_text(encoding="utf-8").strip()
weekend_demo = (RESULTS / "chat_demo_v27_weekend.txt").read_text(encoding="utf-8").strip()
zig_hashmap_demo = (RESULTS / "chat_demo_v27_zig_hashmap.txt").read_text(encoding="utf-8").strip()
uncertainty_demo = (RESULTS / "chat_demo_v27_uncertainty.txt").read_text(encoding="utf-8").strip()
nvidia_smi_text = (RESULTS / "nvidia_smi_v27.txt").read_text(encoding="utf-8").strip() if (RESULTS / "nvidia_smi_v27.txt").exists() else "not captured"
completed_100m_json = find_completed_100m_json()

retrieval_cuda_speedup = float(accel_bench["speedup_cuda_vs_cpu"])
retrieval_cpu_mt_speedup = float(accel_bench["speedup_cpu_mt_vs_cpu"])
numeric_cuda_speedup_250k = float(numeric_backend["speedup_cuda_vs_cpu_250k"])
numeric_cpu_mt_speedup_250k = float(numeric_backend["speedup_cpu_mt_vs_cpu_250k"])
numeric_cuda_speedup_1m = float(numeric_backend["speedup_cuda_vs_cpu_1m"])
numeric_cpu_mt_speedup_1m = float(numeric_backend["speedup_cpu_mt_vs_cpu_1m"])

report_md = f"""# SBAN v27 Follow-up Research Paper

## Release intent

SBAN v27 is the product and free-chat follow-up after v26.

The goal is twofold: push the packaged numeric engine-health suite forward without leaving the safe CPU release path, and make the shipped free-chat surface meaningfully broader on ordinary prompts that previously fell to uncertainty or bad overmatches. In practical terms, v27 keeps the measured CPU, `cpu_mt`, CUDA, and OpenCL backend stack, upgrades the release CPU profile with a stronger continuation setting, ships a real v27 grounded seed plus a larger v27 open-chat seed, broadens operational answers, strengthens natural session memory around project, pet, and tomorrow-style facts, and extends the free-chat surface so common coding, explanation, writing, and planning prompts resolve deterministically instead of drifting.

## What changed in v27

1. Upgraded the packaged CPU numeric release profile with a stronger continuation configuration that improved prefix, drift, probe, 250k, 1M, and 10M while keeping `numeric_backend=cpu` and `score_threads=1` as the shipped fallback path.
2. Shipped a real v27 grounded seed that reflects the current release, starter files, artifact paths, and backend commands.
3. Rebuilt the separate v27 open-chat seed from the v26 base plus broader curated practical prompts and a larger filtered factoid slice.
4. Extended deterministic free-chat support for common coding prompts, practical explanations, professional rewrites, short creative writing, lunch and weekend planning, and safe light-humor prompts.
5. Strengthened natural session memory around project, dog-name, and tomorrow-style facts without regressing earlier location, team, lab, and role behavior.
6. Re-ran the full numeric guardrail suite, the broader conversational batteries, and the measured backend probes and retrieval accelerator bench on the current NVIDIA stack.

## Packaged numeric engine-health results

| Test | Baseline | v27 packaged | Delta |
|---|---:|---:|---:|
| Prefix | {fmt(BASELINE['prefix'])} | {fmt(prefix)} | {prefix - BASELINE['prefix']:+.4f} pp |
| Drift | {fmt(BASELINE['drift'])} | {fmt(drift)} | {drift - BASELINE['drift']:+.4f} pp |
| Probe | {fmt(BASELINE['probe'])} | {fmt(probe)} | {probe - BASELINE['probe']:+.4f} pp |
| 250k | {fmt(BASELINE['long_250k'])} | {fmt(long_250k)} | {long_250k - BASELINE['long_250k']:+.4f} pp |
| 1M | {fmt(BASELINE['long_1m'])} | {fmt(long_1m)} | {long_1m - BASELINE['long_1m']:+.4f} pp |
| 10M | {fmt(BASELINE['long_10m'])} | {fmt(long_10m)} | {long_10m - BASELINE['long_10m']:+.4f} pp |
| 20M | n/a | {fmt(long_20m)} | new |

- The shipped numeric suite still runs on `numeric_backend=cpu` with `score_threads=1`.
- v27 does not promote `cpu_mt` or numeric CUDA by preference; it keeps the safe CPU path while improving that path's actual release profile.
- v27 also extends the hardening ladder to a measured 20M run on the same guarded CPU release path, but that 20M point intentionally falls back to the older bounded continuation setting after the stronger short-suite profile hit `OutOfMemory` at that horizon on this workstation.

## Conversation and product checks

- Hybrid chat eval: **{chat_hybrid['nonempty']} / {chat_hybrid['turns']}** non-empty, **{chat_hybrid['anchored']}** anchored, **{chat_hybrid['retrieved']}** retrieved, **{chat_hybrid['symbolic']}** symbolic, **{chat_hybrid['uncertain']}** uncertain
- Free chat eval: **{chat_free['nonempty']} / {chat_free['turns']}** non-empty, **{chat_free['anchored']}** anchored, **{chat_free['retrieved']}** retrieved, **{chat_free['symbolic']}** symbolic, **{chat_free['uncertain']}** uncertain
- Main scripted session eval: **{session_eval['passed']} / {session_eval['expectations']}** expectation checks passed
- Open-chat scripted session eval: **{open_session_eval['passed']} / {open_session_eval['expectations']}** expectation checks passed
- Broad free-chat battery: **{broad_session_eval['passed']} / {broad_session_eval['expectations']}** expectation checks passed

The open-chat scripted session eval and the broad free-chat battery are the important v27 product signals. Together they exercise planning tomorrow, organizing a week, staying focused, drafting follow-ups, meeting agendas, apology rewrites, interview prep, procrastination, doomscrolling, practical coding help, everyday explanations, light factual prompts, short math, richer session memory, Zig upstream questions, and one unsupported nonsense prompt that should still decline cleanly. v27 passes both versioned sets end to end.

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

These numbers still decide whether the accelerated numeric backends deserve promotion. v27 keeps the CPU path as the packaged default because that path now measures better than the older baseline while the accelerated numeric backends still have to earn promotion on elapsed time.

## Concrete runtime behavior

### Overview answer

```text
{overview_demo}
```

### Bundle inventory answer

```text
{bundle_demo}
```

### Artifact path answer

```text
{paper_demo}
```

### CUDA command answer

```text
{cuda_command_demo}
```

### Session-memory capability answer

```text
{memory_demo}
```

### Planning answer

```text
{planning_demo}
```

### Weekend planning answer

```text
{weekend_demo}
```

### Zig upstream path answer

```text
{zig_hashmap_demo}
```

### Unsupported factual prompt still declines cleanly

```text
{uncertainty_demo}
```

## Long-run note

{f"A completed 100M-class JSON already exists at `{completed_100m_json.relative_to(ROOT).as_posix()}` and can be consulted separately." if completed_100m_json is not None else "No completed 100M-class JSON artifact was found under `docs/results/` at packaging time, so v27 reports through the new 20M hardening run only."}

## Interpretation

v27 is a product release with a strict trust boundary: improve the numeric baseline honestly, keep the backend claims measured, and make the default chat loop materially more useful without pretending it is a broad general knowledge model. The important architectural result is that SBAN now ships a broader conversational surface, versioned conversational evaluations, richer natural session memory, and a measurably stronger CPU numeric profile, while still declining unsupported prompts instead of hallucinating.
"""

summary_md = f"""# SBAN v27 Executive Summary

SBAN v27 is the product and free-chat follow-up after v26. The packaged numeric suite still ships on the safe single-thread CPU path, but the v27 release profile materially improves that CPU baseline while the user-facing chat surface gets broader and less brittle.

Measured release outcomes:

- Prefix: {fmt(prefix)}
- Drift: {fmt(drift)}
- Probe: {fmt(probe)}
- 250k: {fmt(long_250k)}
- 1M: {fmt(long_1m)}
- 10M: {fmt(long_10m)}
- 20M: {fmt(long_20m)}
- Hybrid chat eval: {chat_hybrid['nonempty']}/{chat_hybrid['turns']} non-empty with {chat_hybrid['uncertain']} uncertain
- Free chat eval: {chat_free['nonempty']}/{chat_free['turns']} non-empty with {chat_free['uncertain']} uncertain
- Main session eval: {session_eval['passed']}/{session_eval['expectations']} passed
- Open-chat session eval: {open_session_eval['passed']}/{open_session_eval['expectations']} passed
- Broad free-chat battery: {broad_session_eval['passed']}/{broad_session_eval['expectations']} passed

Product outcome:

- real v27 grounded seed shipped
- separate curated and dataset-enriched v27 open-chat seed shipped
- deterministic coverage widened for common coding, explanation, rewrite, planning, and light-knowledge prompts
- bundle inventory, artifact paths, starter files, CUDA commands, and hardware prompts answer operationally and correctly
- broader free chat now covers planning, writing, brainstorming, stress support, casual preference boundaries, richer session-memory follow-ups, and Zig upstream file-location questions directly
- unsupported factual prompts still return honest uncertainty

Backend outcome:

- Retrieval CUDA speedup vs CPU: {retrieval_cuda_speedup:.4f}x
- Retrieval `cpu_mt` speedup vs CPU: {retrieval_cpu_mt_speedup:.4f}x
- Numeric CUDA speedup vs CPU at 250k: {numeric_cuda_speedup_250k:.4f}x
- Numeric CUDA speedup vs CPU at 1M: {numeric_cuda_speedup_1m:.4f}x
- Numeric CUDA probe: configured `{numeric_cuda_info.get('configured_backend', 'unknown')}`, used `{numeric_cuda_info.get('backend_used', 'unknown')}`, device `{numeric_cuda_info.get('device', 'unknown')}`

Release stance:

- keep `numeric_backend=cpu` and `score_threads=1` as the packaged default until accelerated numeric runs prove a dependable end-to-end win
- ship free mode with both the grounded and open-chat v27 seeds as the default conversational product surface
- treat v27 as a calmer and broader assistant, not as a claim of broad general knowledge
- report the new 20M hardening extension, and skip 100M claims unless a completed JSON artifact actually exists
"""

report_path = ROOT / "SBAN_v27_REPORT.md"
summary_path = ROOT / "SBAN_v27_EXECUTIVE_SUMMARY.md"
paper_path = PAPERS / "SBAN_v27_follow_up_research_paper.pdf"
repo_zip = DELIV / "SBAN_v27_repo.zip"

report_path.write_text(report_md, encoding="utf-8")
summary_path.write_text(summary_md, encoding="utf-8")
render_markdown_to_pdf(report_path, paper_path)
write_repo_zip(repo_zip)

if BIN.exists():
    platform = "windows_x86_64" if os.name == "nt" else "linux_x86_64"
    subprocess.run(
        ["python", "scripts/package_v27_demo.py", "--binary", str(BIN), "--platform", platform],
        cwd=ROOT,
        check=True,
    )

recipe_md = """# SBAN v27 Reproduction Recipe

## Build

If `zig` is not on `PATH`, pass `--zig-exe` to the release script or use the extracted local toolchain path.

```bash
zig build test
zig build -Doptimize=ReleaseFast
```

## Run the measured v27 release suite

```bash
python scripts/run_v27_release.py --skip-build
python scripts/make_v27_deliverables.py
```

## Important runtime notes

- The packaged numeric suite stays on `numeric_backend=cpu` and `score_threads=1`.
- The starter chat loop uses both `seed_path=data/sban_dialogue_seed_v27.txt` and `open_seed_path=data/sban_dialogue_open_seed_v27.txt`.
- The hardening ladder now includes `longrun_v27_20m.json`.
- The experimental numeric host-threaded path can be explored with `numeric_backend=cpu_mt score_threads=4 parallel_score_min_predictive_nodes=128`.
- The experimental numeric CUDA path can be explored with `numeric_backend=cuda cuda_min_scoring_edges=1`.

## Inspect the backend paths

```bash
zig-out/bin/zig_sban accel-info seed_path=data/sban_dialogue_seed_v27.txt backend=cpu_mt threads=4
zig-out/bin/zig_sban accel-info seed_path=data/sban_dialogue_seed_v27.txt backend=cuda
zig-out/bin/zig_sban numeric-accel-info numeric_backend=cpu
zig-out/bin/zig_sban numeric-accel-info numeric_backend=cpu_mt score_threads=4 parallel_score_min_predictive_nodes=1
zig-out/bin/zig_sban numeric-accel-info numeric_backend=cuda cuda_min_scoring_edges=1
```

## Raw retrieval accelerator benchmark

```bash
zig-out/bin/zig_sban accel-bench docs/results/v27/accel_prompts_v27_bench.txt backend=cpu seed_path=docs/results/v27/accel_seed_v27_bench.txt iterations=4
zig-out/bin/zig_sban accel-bench docs/results/v27/accel_prompts_v27_bench.txt backend=cpu_mt threads=4 seed_path=docs/results/v27/accel_seed_v27_bench.txt iterations=4
zig-out/bin/zig_sban accel-bench docs/results/v27/accel_prompts_v27_bench.txt backend=cuda seed_path=docs/results/v27/accel_seed_v27_bench.txt iterations=4
```

## One-shot chat checks

```bash
zig-out/bin/zig_sban chat-demo "what is SBAN v27" 180 seed_path=data/sban_dialogue_seed_v27.txt open_seed_path=data/sban_dialogue_open_seed_v27.txt backend=cpu mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "what files ship in the bundle" 180 seed_path=data/sban_dialogue_seed_v27.txt open_seed_path=data/sban_dialogue_open_seed_v27.txt backend=cpu mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "can you remember where i am from" 180 seed_path=data/sban_dialogue_seed_v27.txt open_seed_path=data/sban_dialogue_open_seed_v27.txt backend=cpu mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "can you help me plan tomorrow" 180 seed_path=data/sban_dialogue_seed_v27.txt open_seed_path=data/sban_dialogue_open_seed_v27.txt backend=cpu mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "what should i do this weekend" 180 seed_path=data/sban_dialogue_seed_v27.txt open_seed_path=data/sban_dialogue_open_seed_v27.txt backend=cpu mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "where is std.hashmap implemented in zig upstream" 180 seed_path=data/sban_dialogue_seed_v27.txt open_seed_path=data/sban_dialogue_open_seed_v27.txt backend=cpu mode=free allow_generation=true
```
"""

recipe_path = DESKTOP / "SBAN_v27_reproduction_recipe.md"
recipe_path.write_text(recipe_md, encoding="utf-8")

for path in [report_path, summary_path, paper_path, repo_zip, recipe_path]:
    shutil.copy2(path, DOWNLOADS / path.name)

for demo_zip in DEMO_DELIV.glob("SBAN_v27_*_demo.zip"):
    shutil.copy2(demo_zip, DOWNLOADS / demo_zip.name)
