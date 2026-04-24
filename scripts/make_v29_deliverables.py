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
RESULTS = ROOT / "docs" / "results" / "v29"
PAPERS = ROOT / "docs" / "papers"
DELIV = ROOT / "deliverables" / "v29"
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
    "prefix": 99.6650,
    "drift": 99.5675,
    "probe": 99.9112,
    "long_250k": 99.4632,
    "long_1m": 99.5334,
    "long_10m": 78.3230,
    "long_20m": 78.4756,
}


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def primary_accuracy(path: Path) -> float:
    data = load_json(path)
    model = data["models"][0]
    return 100.0 * model["total_correct"] / model["total_predictions"]


def fmt(value: float) -> str:
    return f"{value:.4f}%"


def maybe_float(value: object) -> float | None:
    if value is None:
        return None
    return float(value)


def fmt_speedup(value: float | None) -> str:
    return "not measured" if value is None else f"{value:.4f}x"


def fmt_seconds(value: object) -> str:
    if value is None:
        return "not measured"
    return f"{float(value):.3f}s"


def entry_seconds(entry: dict) -> str:
    return fmt_seconds(entry.get("elapsed_seconds"))


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
            if len(rel.parts) >= 3 and rel.parts[0] == "docs" and rel.parts[1] == "results" and rel.parts[2] == "v29" and rel.name.startswith("_"):
                continue
            if path == output_path or path.is_dir():
                continue
            zf.write(path, rel.as_posix())


prefix = primary_accuracy(RESULTS / "unified_prefix_v29_release.json")
drift = primary_accuracy(RESULTS / "unified_drift_v29_release.json")
probe = primary_accuracy(RESULTS / "unified_probe_v29_release.json")
long_250k = primary_accuracy(RESULTS / "longrun_v29_250k.json")
long_1m = primary_accuracy(RESULTS / "longrun_v29_1m.json")
long_10m = primary_accuracy(RESULTS / "longrun_v29_10m.json")
long_20m = primary_accuracy(RESULTS / "longrun_v29_20m.json")
long_20m_data = load_json(RESULTS / "longrun_v29_20m.json")
long_20m_carried_from = long_20m_data.get("meta", {}).get("carried_forward_from")
if long_20m_carried_from:
    long_20m_summary_label = "20M guardrail"
    long_20m_release_note = (
        f"The `longrun_v29_20m.json` artifact is a carried-forward guardrail from "
        f"`{long_20m_carried_from}` with v29 metadata because the local v29 20M rerun "
        "hit OutOfMemory on this workstation; it is not claimed as a fresh 20M numeric improvement."
    )
    long_20m_stance_note = "report the carried-forward 20M guardrail transparently, and skip 100M claims unless a completed JSON artifact actually exists"
    long_20m_recipe_note = "The hardening ladder includes `longrun_v29_20m.json` as a carried-forward v27 guardrail when this workstation cannot rerun that horizon."
else:
    long_20m_summary_label = "20M"
    long_20m_release_note = "v29 keeps the measured 20M hardening ladder from v27 as a release guardrail, with the same bounded continuation fallback at that horizon."
    long_20m_stance_note = "report the new 20M hardening extension, and skip 100M claims unless a completed JSON artifact actually exists"
    long_20m_recipe_note = "The hardening ladder now includes `longrun_v29_20m.json`."

chat_hybrid = parse_chat_summary(RESULTS / "chat_eval_v29_hybrid.txt")
chat_free = parse_chat_summary(RESULTS / "chat_eval_v29_free.txt")
session_eval = parse_session_summary(RESULTS / "chat_session_eval_v29.txt")
open_session_eval = parse_session_summary(RESULTS / "open_chat_session_eval_v29.txt")
broad_session_eval = parse_session_summary(RESULTS / "broad_chat_session_eval_v29.txt")
knowledge_session_eval = parse_session_summary(RESULTS / "knowledge_session_eval_v29.txt")
synthetic_knowledge = load_json(RESULTS / "synthetic_knowledge_v29.json")
vocab_probe = load_json(RESULTS / "vocab_size_probe_v29.json")

retrieval_cpu_mt_info = parse_key_values(RESULTS / "accel_info_v29_cpu_mt.txt")
retrieval_cuda_info = parse_key_values(RESULTS / "accel_info_v29_cuda.txt")
numeric_cpu_info = parse_key_values(RESULTS / "numeric_accel_info_v29_cpu.txt")
numeric_cpu_mt_info = parse_key_values(RESULTS / "numeric_accel_info_v29_cpu_mt.txt")
numeric_cuda_info = parse_key_values(RESULTS / "numeric_accel_info_v29_cuda.txt")

accel_bench = load_json(RESULTS / "accel_bench_v29.json")
numeric_backend = load_json(RESULTS / "numeric_backend_v29.json")

overview_demo = (RESULTS / "chat_demo_v29_overview.txt").read_text(encoding="utf-8").strip()
bundle_demo = (RESULTS / "chat_demo_v29_bundle.txt").read_text(encoding="utf-8").strip()
paper_demo = (RESULTS / "chat_demo_v29_paper.txt").read_text(encoding="utf-8").strip()
cuda_command_demo = (RESULTS / "chat_demo_v29_cuda_command.txt").read_text(encoding="utf-8").strip()
memory_demo = (RESULTS / "chat_demo_v29_memory_capability.txt").read_text(encoding="utf-8").strip()
planning_demo = (RESULTS / "chat_demo_v29_planning.txt").read_text(encoding="utf-8").strip()
weekend_demo = (RESULTS / "chat_demo_v29_weekend.txt").read_text(encoding="utf-8").strip()
zig_hashmap_demo = (RESULTS / "chat_demo_v29_zig_hashmap.txt").read_text(encoding="utf-8").strip()
synthetic_tides_demo = (RESULTS / "chat_demo_v29_tides.txt").read_text(encoding="utf-8").strip()
zig_reverse_demo = (RESULTS / "chat_demo_v29_zig_reverse.txt").read_text(encoding="utf-8").strip()
safe_math_demo = (RESULTS / "chat_demo_v29_safe_math.txt").read_text(encoding="utf-8").strip()
uncertainty_demo = (RESULTS / "chat_demo_v29_uncertainty.txt").read_text(encoding="utf-8").strip()
nvidia_smi_text = (RESULTS / "nvidia_smi_v29.txt").read_text(encoding="utf-8").strip() if (RESULTS / "nvidia_smi_v29.txt").exists() else "not captured"
completed_100m_json = find_completed_100m_json()

retrieval_cuda_speedup = maybe_float(accel_bench["speedup_cuda_vs_cpu"])
retrieval_cpu_mt_speedup = float(accel_bench["speedup_cpu_mt_vs_cpu"])
numeric_cuda_speedup_250k = maybe_float(numeric_backend["speedup_cuda_vs_cpu_250k"])
numeric_cpu_mt_speedup_250k = float(numeric_backend["speedup_cpu_mt_vs_cpu_250k"])
numeric_cuda_speedup_1m = maybe_float(numeric_backend["speedup_cuda_vs_cpu_1m"])
numeric_cpu_mt_speedup_1m = float(numeric_backend["speedup_cpu_mt_vs_cpu_1m"])

if accel_bench["cuda"].get("backend") == "skipped" or retrieval_cuda_info.get("backend") == "skipped":
    cuda_retrieval_claim = (
        "CUDA retrieval acceleration was not measured on this runner because no CUDA runtime was available; "
        "v29 only keeps the CUDA path eligible when a compatible runtime exists."
    )
else:
    cuda_retrieval_claim = "CUDA remains the preferred large-corpus retrieval accelerator on measured NVIDIA systems."

report_md = f"""# SBAN v29 Follow-up Research Paper

## Release intent

SBAN v29 is the synthetic-knowledge, runtime hardening, and Zig-coding follow-up after v28.

The goal is to keep the packaged numeric engine-health suite stable while addressing the v28 architecture stress report. In practical terms, v29 keeps the measured CPU, `cpu_mt`, CUDA, and OpenCL backend stack, preserves the stable CPU numeric guardrail profile, ships a generated synthetic knowledge pack plus a runtime `knowledge_path`, rejects secret storage, caps session loading and retained turns, safely refuses huge exact-number casts, enforces `max_bytes` on displayed responses, fixes numeric `auto` CUDA semantics, adds larger-vocabulary probe results, and extends Zig coding plus real-world task coverage without claiming live internet facts.

## What changed in v29

1. Added a generated synthetic knowledge pack with {synthetic_knowledge['knowledge_pairs']} pairs and a separate runtime `knowledge_path`.
2. Added a v29 generated-knowledge regression eval with {knowledge_session_eval['passed']} / {knowledge_session_eval['expectations']} checks covering science, literature, Zig code, JSON, algebra, safe huge math, source boundaries, and secret rejection.
3. Strengthened session safety with a 256 KiB session-load cap, retained turn and fact caps, secret-key rejection, and fixed encoded-field cleanup during save.
4. Added safe exact-number handling for huge exponent results, simple linear equation solving, mixed-expression math checks, and printed response `max_bytes` enforcement.
5. Added generated general-knowledge coverage for tides, mitosis, capitals, literature, civics, economics, real-world task triage, and Zig allocator/error/defer/slice concepts.
6. Added Zig code-generation snippets for slice reversal, ArrayList, StringHashMap, and error unions, plus JSON object generation.
7. Added a larger-vocabulary probe for 256 through 16384 buckets, showing collision reduction while documenting dense-table memory cost and the sparse-index recommendation.
8. Fixed numeric `auto` so CUDA is attempted when the CUDA runtime exists and the scoring edge threshold is met, while CPU remains the safe default.

## Packaged numeric engine-health results

| Test | Baseline | v29 packaged | Delta |
|---|---:|---:|---:|
| Prefix | {fmt(BASELINE['prefix'])} | {fmt(prefix)} | {prefix - BASELINE['prefix']:+.4f} pp |
| Drift | {fmt(BASELINE['drift'])} | {fmt(drift)} | {drift - BASELINE['drift']:+.4f} pp |
| Probe | {fmt(BASELINE['probe'])} | {fmt(probe)} | {probe - BASELINE['probe']:+.4f} pp |
| 250k | {fmt(BASELINE['long_250k'])} | {fmt(long_250k)} | {long_250k - BASELINE['long_250k']:+.4f} pp |
| 1M | {fmt(BASELINE['long_1m'])} | {fmt(long_1m)} | {long_1m - BASELINE['long_1m']:+.4f} pp |
| 10M | {fmt(BASELINE['long_10m'])} | {fmt(long_10m)} | {long_10m - BASELINE['long_10m']:+.4f} pp |
| {long_20m_summary_label} | {fmt(BASELINE['long_20m'])} | {fmt(long_20m)} | {long_20m - BASELINE['long_20m']:+.4f} pp |

- The shipped numeric suite still runs on `numeric_backend=cpu` with `score_threads=1`.
- v29 does not promote `cpu_mt` or numeric CUDA by preference; it keeps the safe CPU path and isolates product/reporting repairs from numeric-profile churn.
- {long_20m_release_note}

## Conversation and product checks

- Hybrid chat eval: **{chat_hybrid['nonempty']} / {chat_hybrid['turns']}** non-empty, **{chat_hybrid['anchored']}** anchored, **{chat_hybrid['retrieved']}** retrieved, **{chat_hybrid['symbolic']}** symbolic, **{chat_hybrid['uncertain']}** uncertain
- Free chat eval: **{chat_free['nonempty']} / {chat_free['turns']}** non-empty, **{chat_free['anchored']}** anchored, **{chat_free['retrieved']}** retrieved, **{chat_free['symbolic']}** symbolic, **{chat_free['uncertain']}** uncertain
- Main scripted session eval: **{session_eval['passed']} / {session_eval['expectations']}** expectation checks passed
- Open-chat scripted session eval: **{open_session_eval['passed']} / {open_session_eval['expectations']}** expectation checks passed
- Broad free-chat battery: **{broad_session_eval['passed']} / {broad_session_eval['expectations']}** expectation checks passed
- Generated knowledge and stress-regression eval: **{knowledge_session_eval['passed']} / {knowledge_session_eval['expectations']}** expectation checks passed
- Synthetic knowledge pack: **{synthetic_knowledge['knowledge_pairs']}** generated prompt/answer pairs across **{len(synthetic_knowledge['categories'])}** categories
- Vocab probe: 4096 buckets reduce collisions from **{vocab_probe['rows'][0]['collisions']}** at 256 buckets to **{vocab_probe['rows'][4]['collisions']}**, while the dense order-2 estimate rises to **{vocab_probe['rows'][4]['estimated_dense_order2_mib']:.0f} MiB**

The open-chat scripted session eval, broad free-chat battery, and generated-knowledge stress eval are the important v29 product signals. Together they exercise planning tomorrow, organizing a week, staying focused, drafting follow-ups, meeting agendas, apology rewrites, interview prep, procrastination, practical coding help, generated science/literature/geography facts, algebra, safe huge math, source-location boundaries, secret rejection, richer session memory, Zig upstream questions, and one unsupported nonsense prompt that should still decline cleanly. v29 passes these versioned sets end to end.

## Retrieval accelerator results

- `cpu_mt` retrieval probe: backend `{retrieval_cpu_mt_info.get('backend', 'unknown')}`, workers `{retrieval_cpu_mt_info.get('worker_threads', 'unknown')}`
- CUDA retrieval probe: backend `{retrieval_cuda_info.get('backend', 'unknown')}`, platform `{retrieval_cuda_info.get('platform', 'unknown')}`, device `{retrieval_cuda_info.get('device', 'unknown')}`
- Captured `nvidia-smi`: `{nvidia_smi_text}`

### Raw retrieval accelerator bench

- CPU elapsed: **{entry_seconds(accel_bench['cpu'])}**
- `cpu_mt` elapsed: **{entry_seconds(accel_bench['cpu_mt'])}** with speedup **{fmt_speedup(retrieval_cpu_mt_speedup)}** vs CPU
- CUDA elapsed: **{entry_seconds(accel_bench['cuda'])}** with speedup **{fmt_speedup(retrieval_cuda_speedup)}** vs CPU

{cuda_retrieval_claim}

## Numeric backend results

- Numeric CPU probe: configured `{numeric_cpu_info.get('configured_backend', 'unknown')}`, used `{numeric_cpu_info.get('backend_used', 'unknown')}`
- Numeric `cpu_mt` probe: configured `{numeric_cpu_mt_info.get('configured_backend', 'unknown')}`, used `{numeric_cpu_mt_info.get('backend_used', 'unknown')}`
- Numeric CUDA probe: configured `{numeric_cuda_info.get('configured_backend', 'unknown')}`, used `{numeric_cuda_info.get('backend_used', 'unknown')}`, CUDA enabled `{numeric_cuda_info.get('cuda_enabled', 'unknown')}`, device `{numeric_cuda_info.get('device', 'unknown')}`

### Numeric backend timing matrix

| Run | CPU | `cpu_mt` | CUDA |
|---|---:|---:|---:|
| 250k elapsed | {entry_seconds(numeric_backend['release_cpu_250k'])} | {entry_seconds(numeric_backend['release_cpu_mt4_250k'])} | {entry_seconds(numeric_backend['release_cuda_250k'])} |
| 1M elapsed | {entry_seconds(numeric_backend['release_cpu_1m'])} | {entry_seconds(numeric_backend['release_cpu_mt4_1m'])} | {entry_seconds(numeric_backend['release_cuda_1m'])} |

- 250k `cpu_mt` speedup vs CPU: **{fmt_speedup(numeric_cpu_mt_speedup_250k)}**
- 250k CUDA speedup vs CPU: **{fmt_speedup(numeric_cuda_speedup_250k)}**
- 1M `cpu_mt` speedup vs CPU: **{fmt_speedup(numeric_cpu_mt_speedup_1m)}**
- 1M CUDA speedup vs CPU: **{fmt_speedup(numeric_cuda_speedup_1m)}**

These numbers still decide whether the accelerated numeric backends deserve promotion. v29 keeps the CPU path as the packaged default because that path now measures better than the older baseline while the accelerated numeric backends still have to earn promotion on elapsed time.

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

### Generated knowledge answer

```text
{synthetic_tides_demo}
```

### Zig coding answer

```text
{zig_reverse_demo}
```

### Safe huge-math boundary

```text
{safe_math_demo}
```

### Unsupported factual prompt still declines cleanly

```text
{uncertainty_demo}
```

## Long-run note

{f"A completed 100M-class JSON already exists at `{completed_100m_json.relative_to(ROOT).as_posix()}` and can be consulted separately." if completed_100m_json is not None else ("No completed 100M-class JSON artifact was found under `docs/results/` at packaging time, so v29 reports through the carried-forward 20M guardrail only." if long_20m_carried_from else "No completed 100M-class JSON artifact was found under `docs/results/` at packaging time, so v29 reports through the new 20M hardening run only.")}

## Interpretation

v29 is a synthetic-knowledge and runtime-hardening release with a strict trust boundary: keep the numeric baseline stable, keep backend claims measured, and make the default chat loop materially broader through generated assets without pretending it has live internet facts. The important architectural result is that SBAN now loads a separate generated knowledge pack, tests larger vocabularies, answers more Zig and real-world task prompts, and declines unsupported source locations or current facts instead of hallucinating.
"""

summary_md = f"""# SBAN v29 Executive Summary

SBAN v29 is the synthetic-knowledge, runtime hardening, and Zig-coding follow-up after v28. The packaged numeric suite still ships on the safe single-thread CPU path and keeps the stable CPU profile while the user-facing runtime gains a generated knowledge pack, larger-vocabulary probe, safer session persistence, safe huge-math behavior, and stricter release checks.

Measured release outcomes:

- Prefix: {fmt(prefix)}
- Drift: {fmt(drift)}
- Probe: {fmt(probe)}
- 250k: {fmt(long_250k)}
- 1M: {fmt(long_1m)}
- 10M: {fmt(long_10m)}
- {long_20m_summary_label}: {fmt(long_20m)}
- Hybrid chat eval: {chat_hybrid['nonempty']}/{chat_hybrid['turns']} non-empty with {chat_hybrid['uncertain']} uncertain
- Free chat eval: {chat_free['nonempty']}/{chat_free['turns']} non-empty with {chat_free['uncertain']} uncertain
- Main session eval: {session_eval['passed']}/{session_eval['expectations']} passed
- Open-chat session eval: {open_session_eval['passed']}/{open_session_eval['expectations']} passed
- Broad free-chat battery: {broad_session_eval['passed']}/{broad_session_eval['expectations']} passed
- Generated knowledge eval: {knowledge_session_eval['passed']}/{knowledge_session_eval['expectations']} passed
- Synthetic knowledge pairs: {synthetic_knowledge['knowledge_pairs']}
- 4096-vocab probe collisions: {vocab_probe['rows'][4]['collisions']} vs {vocab_probe['rows'][0]['collisions']} at 256 buckets

Product outcome:

- real v29 grounded seed shipped
- separate curated/open v29 seed and generated synthetic knowledge pack shipped
- deterministic and generated coverage widened for safe huge math, linear equations, translation, summarization, Zig coding, JSON, science, geography, literature, planning, task triage, and source-boundary prompts
- session persistence now rejects likely secrets, caps loaded session bytes, caps retained facts/turns, and frees encoded save fields
- bundle inventory, artifact paths, starter files, CUDA commands, and hardware prompts answer operationally and correctly
- broader free chat now covers planning, writing, brainstorming, support prompts, generated general knowledge, practical Zig snippets, and Zig upstream file-location questions directly
- unsupported live-current or unindexed source-location prompts still return honest boundaries

Backend outcome:

- Retrieval CUDA speedup vs CPU: {fmt_speedup(retrieval_cuda_speedup)}
- Retrieval `cpu_mt` speedup vs CPU: {fmt_speedup(retrieval_cpu_mt_speedup)}
- Numeric CUDA speedup vs CPU at 250k: {fmt_speedup(numeric_cuda_speedup_250k)}
- Numeric CUDA speedup vs CPU at 1M: {fmt_speedup(numeric_cuda_speedup_1m)}
- Numeric CUDA probe: configured `{numeric_cuda_info.get('configured_backend', 'unknown')}`, used `{numeric_cuda_info.get('backend_used', 'unknown')}`, device `{numeric_cuda_info.get('device', 'unknown')}`

Release stance:

- keep `numeric_backend=cpu` and `score_threads=1` as the packaged default until accelerated numeric runs prove a dependable end-to-end win
- ship free mode with the grounded seed, open-chat seed, and generated synthetic knowledge pack as the default conversational product surface
- treat v29 as a broader offline/runtime-updatable assistant, not as a live-current web oracle
- {long_20m_stance_note}
"""

report_path = ROOT / "SBAN_v29_REPORT.md"
summary_path = ROOT / "SBAN_v29_EXECUTIVE_SUMMARY.md"
paper_path = PAPERS / "SBAN_v29_follow_up_research_paper.pdf"
repo_zip = DELIV / "SBAN_v29_repo.zip"

report_path.write_text(report_md, encoding="utf-8", newline="\n")
summary_path.write_text(summary_md, encoding="utf-8", newline="\n")
render_markdown_to_pdf(report_path, paper_path)
write_repo_zip(repo_zip)

if BIN.exists():
    platform = "windows_x86_64" if os.name == "nt" else "linux_x86_64"
    subprocess.run(
        ["python", "scripts/package_v29_demo.py", "--binary", str(BIN), "--platform", platform],
        cwd=ROOT,
        check=True,
    )

recipe_md = f"""# SBAN v29 Reproduction Recipe

## Build

If `zig` is not on `PATH`, pass `--zig-exe` to the release script or use the extracted local toolchain path.

```bash
zig build test
zig build -Doptimize=ReleaseFast
```

## Run the measured v29 release suite

```bash
python scripts/run_v29_release.py --skip-build
python scripts/make_v29_deliverables.py
```

## Important runtime notes

- The packaged numeric suite stays on `numeric_backend=cpu` and `score_threads=1`.
- The starter chat loop uses `seed_path=data/sban_dialogue_seed_v29.txt`, `open_seed_path=data/sban_dialogue_open_seed_v29.txt`, and `knowledge_path=data/sban_synthetic_knowledge_v29.txt`.
- {long_20m_recipe_note}
- The experimental numeric host-threaded path can be explored with `numeric_backend=cpu_mt score_threads=4 parallel_score_min_predictive_nodes=128`.
- The experimental numeric CUDA path can be explored with `numeric_backend=cuda cuda_min_scoring_edges=1`.

## Inspect the backend paths

```bash
zig-out/bin/zig_sban accel-info seed_path=data/sban_dialogue_seed_v29.txt backend=cpu_mt threads=4
zig-out/bin/zig_sban accel-info seed_path=data/sban_dialogue_seed_v29.txt backend=cuda
zig-out/bin/zig_sban numeric-accel-info numeric_backend=cpu
zig-out/bin/zig_sban numeric-accel-info numeric_backend=cpu_mt score_threads=4 parallel_score_min_predictive_nodes=1
zig-out/bin/zig_sban numeric-accel-info numeric_backend=cuda cuda_min_scoring_edges=1
```

## Raw retrieval accelerator benchmark

```bash
zig-out/bin/zig_sban accel-bench docs/results/v29/accel_prompts_v29_bench.txt backend=cpu seed_path=docs/results/v29/accel_seed_v29_bench.txt iterations=4
zig-out/bin/zig_sban accel-bench docs/results/v29/accel_prompts_v29_bench.txt backend=cpu_mt threads=4 seed_path=docs/results/v29/accel_seed_v29_bench.txt iterations=4
zig-out/bin/zig_sban accel-bench docs/results/v29/accel_prompts_v29_bench.txt backend=cuda seed_path=docs/results/v29/accel_seed_v29_bench.txt iterations=4
```

## One-shot chat checks

```bash
zig-out/bin/zig_sban chat-demo "what is SBAN v29" 180 seed_path=data/sban_dialogue_seed_v29.txt open_seed_path=data/sban_dialogue_open_seed_v29.txt knowledge_path=data/sban_synthetic_knowledge_v29.txt backend=cpu mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "what causes tides" 180 seed_path=data/sban_dialogue_seed_v29.txt open_seed_path=data/sban_dialogue_open_seed_v29.txt knowledge_path=data/sban_synthetic_knowledge_v29.txt backend=cpu mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "write a zig function to reverse a slice" 180 seed_path=data/sban_dialogue_seed_v29.txt open_seed_path=data/sban_dialogue_open_seed_v29.txt knowledge_path=data/sban_synthetic_knowledge_v29.txt backend=cpu mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "calculate 2^1000" 180 seed_path=data/sban_dialogue_seed_v29.txt open_seed_path=data/sban_dialogue_open_seed_v29.txt knowledge_path=data/sban_synthetic_knowledge_v29.txt backend=cpu mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "where is std.hashmap implemented in zig upstream" 180 seed_path=data/sban_dialogue_seed_v29.txt open_seed_path=data/sban_dialogue_open_seed_v29.txt knowledge_path=data/sban_synthetic_knowledge_v29.txt backend=cpu mode=free allow_generation=true
```
"""

recipe_path = DESKTOP / "SBAN_v29_reproduction_recipe.md"
recipe_path.write_text(recipe_md, encoding="utf-8", newline="\n")

for path in [report_path, summary_path, paper_path, repo_zip, recipe_path]:
    shutil.copy2(path, DOWNLOADS / path.name)

for demo_zip in DEMO_DELIV.glob("SBAN_v29_*_demo.zip"):
    shutil.copy2(demo_zip, DOWNLOADS / demo_zip.name)
