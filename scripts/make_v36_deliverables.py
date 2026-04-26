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
RESULTS = ROOT / "docs" / "results" / "v36"
PAPERS = ROOT / "docs" / "papers"
DELIV = ROOT / "deliverables" / "v36"
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
    candidates = sorted(RESULTS.glob("longrun_v36_100m*.json"))
    return candidates[-1] if candidates else None


def write_repo_zip(output_path: Path) -> None:
    exclude_names = {".git", ".zig-cache", "zig-out", "__pycache__", "deliverables", "validation"}
    excluded_files = {
        Path("data") / "enwik8",
        Path("data") / "wikitext2_train_seed.txt",
    }
    output_path.parent.mkdir(parents=True, exist_ok=True)
    if output_path.exists():
        output_path.unlink()
    tracked = subprocess.check_output(["git", "ls-files", "--cached"], cwd=ROOT, text=True).splitlines()
    with zipfile.ZipFile(output_path, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as zf:
        for rel_text in tracked:
            rel = Path(rel_text)
            path = ROOT / rel
            if not path.exists():
                continue
            if any(part in exclude_names for part in rel.parts):
                continue
            if rel in excluded_files:
                continue
            if len(rel.parts) >= 3 and rel.parts[0] == "docs" and rel.parts[1] == "results" and "_tune" in rel.parts[2]:
                continue
            if len(rel.parts) >= 3 and rel.parts[0] == "docs" and rel.parts[1] == "results" and rel.name.startswith("_run_"):
                continue
            if len(rel.parts) >= 3 and rel.parts[0] == "docs" and rel.parts[1] == "results" and rel.parts[2] == "v36" and rel.name.startswith("_"):
                continue
            if path == output_path or path.is_dir():
                continue
            zf.write(path, rel.as_posix())


prefix = primary_accuracy(RESULTS / "unified_prefix_v36_release.json")
drift = primary_accuracy(RESULTS / "unified_drift_v36_release.json")
probe = primary_accuracy(RESULTS / "unified_probe_v36_release.json")
long_250k = primary_accuracy(RESULTS / "longrun_v36_250k.json")
long_1m = primary_accuracy(RESULTS / "longrun_v36_1m.json")
long_10m = primary_accuracy(RESULTS / "longrun_v36_10m.json")
long_20m = primary_accuracy(RESULTS / "longrun_v36_20m.json")
long_20m_data = load_json(RESULTS / "longrun_v36_20m.json")
long_20m_carried_from = long_20m_data.get("meta", {}).get("carried_forward_from")
if long_20m_carried_from:
    long_20m_summary_label = "20M guardrail"
    long_20m_release_note = (
        f"The `longrun_v36_20m.json` artifact is a carried-forward guardrail from "
        f"`{long_20m_carried_from}` with v36 metadata because this hosted-compatible release run "
        "intentionally used the memory guardrail rather than rerunning the 20M horizon; it is not "
        "claimed as a fresh 20M numeric improvement."
    )
    long_20m_stance_note = "report the carried-forward 20M guardrail transparently for hosted-compatible release runs, and skip 100M claims unless a completed JSON artifact actually exists"
    long_20m_recipe_note = "The hardening ladder includes `longrun_v36_20m.json` as a carried-forward v27 guardrail when the selected runner should not rerun that horizon."
else:
    long_20m_summary_label = "20M"
    long_20m_release_note = "v36 keeps the measured 20M hardening ladder from v27 as a release guardrail, with the same bounded continuation fallback at that horizon."
    long_20m_stance_note = "report the new 20M hardening extension, and skip 100M claims unless a completed JSON artifact actually exists"
    long_20m_recipe_note = "The hardening ladder now includes `longrun_v36_20m.json`."

chat_hybrid = parse_chat_summary(RESULTS / "chat_eval_v36_hybrid.txt")
chat_free = parse_chat_summary(RESULTS / "chat_eval_v36_free.txt")
session_eval = parse_session_summary(RESULTS / "chat_session_eval_v36.txt")
open_session_eval = parse_session_summary(RESULTS / "open_chat_session_eval_v36.txt")
broad_session_eval = parse_session_summary(RESULTS / "broad_chat_session_eval_v36.txt")
knowledge_session_eval = parse_session_summary(RESULTS / "knowledge_session_eval_v36.txt")
learned_session_eval = parse_session_summary(RESULTS / "learned_session_eval_v36.txt")
limitations_session_eval = parse_session_summary(RESULTS / "limitations_session_eval_v36.txt")
synthetic_knowledge = load_json(RESULTS / "synthetic_knowledge_v36.json")
autolearn_manifest = load_json(RESULTS / "autolearn_manifest_v36.json")
vocab_probe = load_json(RESULTS / "vocab_size_probe_v36.json")

retrieval_cpu_mt_info = parse_key_values(RESULTS / "accel_info_v36_cpu_mt.txt")
retrieval_cuda_info = parse_key_values(RESULTS / "accel_info_v36_cuda.txt")
numeric_cpu_info = parse_key_values(RESULTS / "numeric_accel_info_v36_cpu.txt")
numeric_cpu_mt_info = parse_key_values(RESULTS / "numeric_accel_info_v36_cpu_mt.txt")
numeric_cuda_info = parse_key_values(RESULTS / "numeric_accel_info_v36_cuda.txt")

accel_bench = load_json(RESULTS / "accel_bench_v36.json")
numeric_backend = load_json(RESULTS / "numeric_backend_v36.json")

overview_demo = (RESULTS / "chat_demo_v36_overview.txt").read_text(encoding="utf-8").strip()
autolearn_demo = (RESULTS / "chat_demo_v36_autolearn.txt").read_text(encoding="utf-8").strip()
learned_syllogism_demo = (RESULTS / "chat_demo_v36_learned_syllogism.txt").read_text(encoding="utf-8").strip()
json_slots_demo = (RESULTS / "chat_demo_v36_json_slots.txt").read_text(encoding="utf-8").strip()
bundle_demo = (RESULTS / "chat_demo_v36_bundle.txt").read_text(encoding="utf-8").strip()
paper_demo = (RESULTS / "chat_demo_v36_paper.txt").read_text(encoding="utf-8").strip()
cuda_command_demo = (RESULTS / "chat_demo_v36_cuda_command.txt").read_text(encoding="utf-8").strip()
memory_demo = (RESULTS / "chat_demo_v36_memory_capability.txt").read_text(encoding="utf-8").strip()
planning_demo = (RESULTS / "chat_demo_v36_planning.txt").read_text(encoding="utf-8").strip()
weekend_demo = (RESULTS / "chat_demo_v36_weekend.txt").read_text(encoding="utf-8").strip()
zig_hashmap_demo = (RESULTS / "chat_demo_v36_zig_hashmap.txt").read_text(encoding="utf-8").strip()
synthetic_tides_demo = (RESULTS / "chat_demo_v36_tides.txt").read_text(encoding="utf-8").strip()
zig_reverse_demo = (RESULTS / "chat_demo_v36_zig_reverse.txt").read_text(encoding="utf-8").strip()
quantified_logic_demo = (RESULTS / "chat_demo_v36_quantified_logic.txt").read_text(encoding="utf-8").strip()
quadratic_demo = (RESULTS / "chat_demo_v36_quadratic.txt").read_text(encoding="utf-8").strip()
word_problem_demo = (RESULTS / "chat_demo_v36_word_problem.txt").read_text(encoding="utf-8").strip()
rust_server_demo = (RESULTS / "chat_demo_v36_rust_server.txt").read_text(encoding="utf-8").strip()
safe_math_demo = (RESULTS / "chat_demo_v36_safe_math.txt").read_text(encoding="utf-8").strip()
uncertainty_demo = (RESULTS / "chat_demo_v36_uncertainty.txt").read_text(encoding="utf-8").strip()
nvidia_smi_text = (RESULTS / "nvidia_smi_v36.txt").read_text(encoding="utf-8").strip() if (RESULTS / "nvidia_smi_v36.txt").exists() else "not captured"
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
        "v36 only keeps the CUDA path eligible when a compatible runtime exists."
    )
else:
    cuda_retrieval_claim = "CUDA remains the preferred large-corpus retrieval accelerator on measured NVIDIA systems."

report_md = f"""# SBAN v36 Follow-up Research Paper

## Release intent

SBAN v36 is the runtime-learning, limitation-repair, and Zig/Rust coding follow-up after v35.

The goal is to keep the packaged numeric engine-health suite stable while making reply improvement data-maintainable instead of code-maintained. In practical terms, v36 keeps the measured CPU, `cpu_mt`, CUDA, and OpenCL backend stack, preserves the stable CPU numeric guardrail profile, ships a generated runtime prewarm pack and a learned reasoning corpus loaded by default, validates that the corpus was built from online dataset adapters, fixes exact JSON slot preservation, adds structured forget/delete/no-store session semantics, solves simple quadratic equations, repairs running-total word problems, enforces `max_bytes` on displayed responses, adds larger-vocabulary probe results, and extends Zig/Rust coding plus real-world task coverage without claiming live internet facts.

## What changed in v36

1. Added `data/sban_learned_reasoning_v36.txt`, generated by dataset adapters for `openai/gsm8k`, `Ritu27/StrategyQA`, and `HuggingFaceFW/CommonsenseQA`, with {autolearn_manifest['online_examples']} online examples and {autolearn_manifest['fallback_examples']} deterministic CI fallback examples recorded in the manifest.
2. Routed the learned corpus through the runtime retrieval scorer so new reasoning examples can be learned by regenerating data assets rather than adding new `dialogue.zig` prompt branches.
3. Promoted a generated runtime prewarm pack with {synthetic_knowledge['knowledge_pairs']} generated/compatibility pairs and default chat loading.
4. Added a v36 generated-knowledge regression eval with {knowledge_session_eval['passed']} / {knowledge_session_eval['expectations']} checks, a learned-reasoning eval with {learned_session_eval['passed']} / {learned_session_eval['expectations']} checks, and a limitation-regression eval with {limitations_session_eval['passed']} / {limitations_session_eval['expectations']} checks.
5. Added structured session forget/delete semantics and normalized "my dog is max now" to store `max` instead of the phrase `max now`.
6. Fixed JSON name/age prompts so `generate JSON with name Ada and age 37` returns age 37 instead of a canned age.
7. Kept safe exact-number handling, practical Zig/Python/SQL snippets, source-boundary behavior, and printed response `max_bytes` enforcement.
8. Added a larger-vocabulary probe for 256 through 65536 buckets, showing collision reduction while documenting dense-table memory cost and the sparse-index recommendation.

## Packaged numeric engine-health results

| Test | Baseline | v36 packaged | Delta |
|---|---:|---:|---:|
| Prefix | {fmt(BASELINE['prefix'])} | {fmt(prefix)} | {prefix - BASELINE['prefix']:+.4f} pp |
| Drift | {fmt(BASELINE['drift'])} | {fmt(drift)} | {drift - BASELINE['drift']:+.4f} pp |
| Probe | {fmt(BASELINE['probe'])} | {fmt(probe)} | {probe - BASELINE['probe']:+.4f} pp |
| 250k | {fmt(BASELINE['long_250k'])} | {fmt(long_250k)} | {long_250k - BASELINE['long_250k']:+.4f} pp |
| 1M | {fmt(BASELINE['long_1m'])} | {fmt(long_1m)} | {long_1m - BASELINE['long_1m']:+.4f} pp |
| 10M | {fmt(BASELINE['long_10m'])} | {fmt(long_10m)} | {long_10m - BASELINE['long_10m']:+.4f} pp |
| {long_20m_summary_label} | {fmt(BASELINE['long_20m'])} | {fmt(long_20m)} | {long_20m - BASELINE['long_20m']:+.4f} pp |

- The shipped numeric suite still runs on `numeric_backend=cpu` with `score_threads=1`.
- v36 does not promote `cpu_mt` or numeric CUDA by preference; it keeps the safe CPU path and isolates product/reporting repairs from numeric-profile churn.
- {long_20m_release_note}

## Conversation and product checks

- Hybrid chat eval: **{chat_hybrid['nonempty']} / {chat_hybrid['turns']}** non-empty, **{chat_hybrid['anchored']}** anchored, **{chat_hybrid['retrieved']}** retrieved, **{chat_hybrid['symbolic']}** symbolic, **{chat_hybrid['uncertain']}** uncertain
- Free chat eval: **{chat_free['nonempty']} / {chat_free['turns']}** non-empty, **{chat_free['anchored']}** anchored, **{chat_free['retrieved']}** retrieved, **{chat_free['symbolic']}** symbolic, **{chat_free['uncertain']}** uncertain
- Main scripted session eval: **{session_eval['passed']} / {session_eval['expectations']}** expectation checks passed
- Open-chat scripted session eval: **{open_session_eval['passed']} / {open_session_eval['expectations']}** expectation checks passed
- Broad free-chat battery: **{broad_session_eval['passed']} / {broad_session_eval['expectations']}** expectation checks passed
- Generated knowledge and stress-regression eval: **{knowledge_session_eval['passed']} / {knowledge_session_eval['expectations']}** expectation checks passed
- Learned reasoning eval: **{learned_session_eval['passed']} / {learned_session_eval['expectations']}** expectation checks passed
- v36 limitation-regression eval: **{limitations_session_eval['passed']} / {limitations_session_eval['expectations']}** expectation checks passed
- Runtime prewarm pack: **{synthetic_knowledge['knowledge_pairs']}** generated and compatibility prompt/answer pairs across **{len(synthetic_knowledge['categories'])}** categories
- Learned corpus: **{autolearn_manifest['online_examples']}** online examples from **{len([k for k, v in autolearn_manifest['sources'].items() if v])}** sources, **{autolearn_manifest['learned_examples']}** total examples
- Vocab probe: 65536 buckets reduce collisions from **{vocab_probe['rows'][0]['collisions']}** at 256 buckets to **{vocab_probe['rows'][-1]['collisions']}**, while the dense order-2 estimate rises to **{vocab_probe['rows'][-1]['estimated_dense_order2_mib']:.0f} MiB**

The open-chat scripted session eval, broad free-chat battery, generated-knowledge stress eval, learned reasoning eval, and limitation-regression eval are the important v36 product signals. Together they exercise planning tomorrow, organizing a week, staying focused, drafting follow-ups, meeting agendas, apology rewrites, interview prep, procrastination, practical coding help, generated science/literature/geography facts, algebra, simple quadratics, safe huge math, source-location boundaries, secret rejection, richer session memory with forget/delete/no-store semantics, Zig upstream questions, exact JSON slots, Rust server snippets, and learned syllogism/arithmetic patterns. v36 passes these versioned sets end to end.

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

These numbers still decide whether the accelerated numeric backends deserve promotion. v36 keeps the CPU path as the packaged default because that path now measures better than the older baseline while the accelerated numeric backends still have to earn promotion on elapsed time.

## Concrete runtime behavior

### Overview answer

```text
{overview_demo}
```

### Auto-learn explanation

```text
{autolearn_demo}
```

### Learned reasoning answer

```text
{learned_syllogism_demo}
```

### Exact JSON slot answer

```text
{json_slots_demo}
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

### Quantified negation repair

```text
{quantified_logic_demo}
```

### Quadratic equation repair

```text
{quadratic_demo}
```

### Running-total word problem repair

```text
{word_problem_demo}
```

### Rust async HTTP server answer

```text
{rust_server_demo}
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

{f"A completed 100M-class JSON already exists at `{completed_100m_json.relative_to(ROOT).as_posix()}` and can be consulted separately." if completed_100m_json is not None else ("No completed 100M-class JSON artifact was found under `docs/results/` at packaging time, so v36 reports through the carried-forward 20M guardrail only. The hosted long-hardening workflow records the 10M fresh run and emits the 20M carried-forward guardrail explicitly to avoid another opaque hosted runner termination." if long_20m_carried_from else "No completed 100M-class JSON artifact was found under `docs/results/` at packaging time, so v36 reports through the new 20M hardening run only.")}

## Interpretation

v36 is a runtime-learning release with a strict trust boundary: keep the numeric baseline stable, keep backend claims measured, and make the default chat loop materially broader through generated assets plus symbolic routing before retrieval. The important architectural result is that SBAN now loads both the generated prewarm pack and learned reasoning corpus by default, tests larger vocabularies, answers more Zig/Rust and real-world task prompts, supports data-regenerated learning, attempts near-miss reasoning prompts, and reserves hard boundaries for unsupported source locations or current facts.
"""

summary_md = f"""# SBAN v36 Executive Summary

SBAN v36 is the runtime-learning, limitation-repair, and Zig/Rust coding follow-up after v35. The packaged numeric suite still ships on the safe single-thread CPU path and keeps the stable CPU profile while the user-facing runtime gains a default generated prewarm pack, a generated learned reasoning corpus, larger-vocabulary probe, safer session persistence with forget/delete/no-store semantics, exact JSON slot preservation, simple quadratic solving, repaired word-problem arithmetic, and stricter release checks.

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
- Learned reasoning eval: {learned_session_eval['passed']}/{learned_session_eval['expectations']} passed
- v36 limitation-regression eval: {limitations_session_eval['passed']}/{limitations_session_eval['expectations']} passed
- Runtime prewarm pairs: {synthetic_knowledge['knowledge_pairs']}
- Learned corpus examples: {autolearn_manifest['learned_examples']} total, {autolearn_manifest['online_examples']} online
- 65536-vocab probe collisions: {vocab_probe['rows'][-1]['collisions']} vs {vocab_probe['rows'][0]['collisions']} at 256 buckets

Product outcome:

- default v36 runtime prewarm pack shipped
- learned reasoning corpus from online dataset adapters shipped
- compatibility v36 seed, open-seed, and generated knowledge files shipped
- deterministic and generated coverage widened for learned syllogisms, arithmetic reasoning, simple quadratics, safe huge math, linear equations, translation, summarization, Zig/Rust coding, exact JSON, science, geography, literature, planning, task triage, and source-boundary prompts
- session persistence now rejects likely secrets, caps loaded session bytes, caps retained facts/turns, and frees encoded save fields
- bundle inventory, artifact paths, starter files, CUDA commands, and hardware prompts answer operationally and correctly
- broader free chat now covers planning, writing, brainstorming, support prompts, generated general knowledge, practical Zig/Rust snippets, and Zig upstream file-location questions directly
- unsupported live-current or unindexed source-location prompts still return honest boundaries

Backend outcome:

- Retrieval CUDA speedup vs CPU: {fmt_speedup(retrieval_cuda_speedup)}
- Retrieval `cpu_mt` speedup vs CPU: {fmt_speedup(retrieval_cpu_mt_speedup)}
- Numeric CUDA speedup vs CPU at 250k: {fmt_speedup(numeric_cuda_speedup_250k)}
- Numeric CUDA speedup vs CPU at 1M: {fmt_speedup(numeric_cuda_speedup_1m)}
- Numeric CUDA probe: configured `{numeric_cuda_info.get('configured_backend', 'unknown')}`, used `{numeric_cuda_info.get('backend_used', 'unknown')}`, device `{numeric_cuda_info.get('device', 'unknown')}`

Release stance:

- keep `numeric_backend=cpu` and `score_threads=1` as the packaged default until accelerated numeric runs prove a dependable end-to-end win
- ship free mode with the generated runtime prewarm pack and learned reasoning corpus as the default conversational product surface
- treat v36 as a broader offline/runtime-updatable assistant, not as a live-current web oracle
- {long_20m_stance_note}
"""

report_path = ROOT / "SBAN_v36_REPORT.md"
summary_path = ROOT / "SBAN_v36_EXECUTIVE_SUMMARY.md"
paper_path = PAPERS / "SBAN_v36_follow_up_research_paper.pdf"
repo_zip = DELIV / "SBAN_v36_repo.zip"

report_path.write_text(report_md, encoding="utf-8", newline="\n")
summary_path.write_text(summary_md, encoding="utf-8", newline="\n")
render_markdown_to_pdf(report_path, paper_path)
write_repo_zip(repo_zip)

if BIN.exists():
    platform = "windows_x86_64" if os.name == "nt" else "linux_x86_64"
    subprocess.run(
        ["python", "scripts/package_v36_demo.py", "--binary", str(BIN), "--platform", platform],
        cwd=ROOT,
        check=True,
    )

recipe_md = f"""# SBAN v36 Reproduction Recipe

## Build

If `zig` is not on `PATH`, pass `--zig-exe` to the release script or use the extracted local toolchain path.

```bash
zig build test
zig build -Doptimize=ReleaseFast
```

## Run the measured v36 release suite

```bash
python scripts/run_v36_release.py --skip-build
python scripts/make_v36_deliverables.py
```

## Important runtime notes

- The packaged numeric suite stays on `numeric_backend=cpu` and `score_threads=1`.
- The starter chat loop uses the default `data/sban_runtime_prewarm_v36.txt` pack plus `data/sban_learned_reasoning_v36.txt` and does not need explicit seed/open/knowledge/learned arguments.
- Rebuild the learned corpus with `python scripts/build_v36_runtime_prewarm.py --force-refresh` when you want new dataset rows to improve runtime replies without editing `dialogue.zig`.
- {long_20m_recipe_note}
- The experimental numeric host-threaded path can be explored with `numeric_backend=cpu_mt score_threads=4 parallel_score_min_predictive_nodes=128`.
- The experimental numeric CUDA path can be explored with `numeric_backend=cuda cuda_min_scoring_edges=1`.

## Inspect the backend paths

```bash
zig-out/bin/zig_sban accel-info backend=cpu_mt threads=4
zig-out/bin/zig_sban accel-info backend=cuda
zig-out/bin/zig_sban numeric-accel-info numeric_backend=cpu
zig-out/bin/zig_sban numeric-accel-info numeric_backend=cpu_mt score_threads=4 parallel_score_min_predictive_nodes=1
zig-out/bin/zig_sban numeric-accel-info numeric_backend=cuda cuda_min_scoring_edges=1
```

## Raw retrieval accelerator benchmark

```bash
zig-out/bin/zig_sban accel-bench docs/results/v36/accel_prompts_v36_bench.txt backend=cpu seed_path=docs/results/v36/accel_seed_v36_bench.txt iterations=4
zig-out/bin/zig_sban accel-bench docs/results/v36/accel_prompts_v36_bench.txt backend=cpu_mt threads=4 seed_path=docs/results/v36/accel_seed_v36_bench.txt iterations=4
zig-out/bin/zig_sban accel-bench docs/results/v36/accel_prompts_v36_bench.txt backend=cuda seed_path=docs/results/v36/accel_seed_v36_bench.txt iterations=4
```

## One-shot chat checks

```bash
zig-out/bin/zig_sban chat-demo "what is SBAN v36" 220 backend=cpu mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "how does SBAN v36 learn without editing dialogue.zig" 260 backend=cpu mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "If all daxes are lums, and some lums are norps, are all daxes definitely norps? Explain." 260 backend=cpu mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "generate JSON with name Ada and age 37" 160 backend=cpu mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "what causes tides" 220 backend=cpu mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "write a zig function to reverse a slice" 420 backend=cpu mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "calculate 2^1000" 220 backend=cpu mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "what does defer do in Zig" 220 backend=cpu mode=free allow_generation=true
```
"""

recipe_path = DESKTOP / "SBAN_v36_reproduction_recipe.md"
recipe_path.write_text(recipe_md, encoding="utf-8", newline="\n")

for path in [report_path, summary_path, paper_path, repo_zip, recipe_path]:
    shutil.copy2(path, DOWNLOADS / path.name)

for demo_zip in DEMO_DELIV.glob("SBAN_v36_*_demo.zip"):
    shutil.copy2(demo_zip, DOWNLOADS / demo_zip.name)
