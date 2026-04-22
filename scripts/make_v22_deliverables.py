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
RESULTS = ROOT / "docs" / "results" / "v22"
PAPERS = ROOT / "docs" / "papers"
DELIV = ROOT / "deliverables" / "v22"
DEMO_DELIV = DELIV / "demo"
DOWNLOADS = Path.home() / "Downloads"
BIN = ROOT / "zig-out" / "bin" / ("zig_sban.exe" if os.name == "nt" else "zig_sban")

PAPERS.mkdir(parents=True, exist_ok=True)
DELIV.mkdir(parents=True, exist_ok=True)
DEMO_DELIV.mkdir(parents=True, exist_ok=True)
DOWNLOADS.mkdir(parents=True, exist_ok=True)

V21 = {
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


def primary_predictions(path: Path) -> int:
    data = load_json(path)
    model = data["models"][0]
    return int(model["total_predictions"])


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
    exclude_names = {".git", ".zig-cache", "zig-out", "__pycache__", "zig-toolchain", "deliverables"}
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


prefix = primary_accuracy(RESULTS / "unified_prefix_v22_release.json")
drift = primary_accuracy(RESULTS / "unified_drift_v22_release.json")
probe = primary_accuracy(RESULTS / "unified_probe_v22_release.json")
long_250k = primary_accuracy(RESULTS / "longrun_v22_250k.json")
long_1m = primary_accuracy(RESULTS / "longrun_v22_1m.json")
long_10m = primary_accuracy(RESULTS / "longrun_v22_10m.json")
long_100m = primary_accuracy(RESULTS / "longrun_v22_100m.json")
pred_100m = primary_predictions(RESULTS / "longrun_v22_100m.json")

chat_hybrid = parse_chat_summary(RESULTS / "chat_eval_v22_hybrid.txt")
chat_free = parse_chat_summary(RESULTS / "chat_eval_v22_free.txt")
session_eval = parse_session_summary(RESULTS / "chat_session_eval_v22.txt")
accel_info = parse_key_values(RESULTS / "accel_info_v22.txt")
runtime_timings = load_json(RESULTS / "runtime_timings_v22.json")

chat_demo_paraphrase = (RESULTS / "chat_demo_v22_paraphrase.txt").read_text(encoding="utf-8").strip()
chat_demo_recall = (RESULTS / "chat_demo_v22_recall.txt").read_text(encoding="utf-8").strip()
chat_demo_uncertainty = (RESULTS / "chat_demo_v22_uncertainty.txt").read_text(encoding="utf-8").strip()
chat_demo_math_error = (RESULTS / "chat_demo_v22_math_error.txt").read_text(encoding="utf-8").strip()
chat_demo_setup = (RESULTS / "chat_demo_v22_setup.txt").read_text(encoding="utf-8").strip()
chat_demo_version_guard = (RESULTS / "chat_demo_v22_version_guard.txt").read_text(encoding="utf-8").strip()
chat_demo_missing_seed = (RESULTS / "chat_demo_v22_missing_seed.txt").read_text(encoding="utf-8").strip()

gpu_summary = (
    f"`accel-info` resolved GPU support on the validation machine: platform `{accel_info.get('platform', 'unknown')}`, "
    f"device `{accel_info.get('device', 'unknown')}`."
    if accel_info.get("backend") == "gpu"
    else "The validation machine fell back to CPU mode for `accel-info`."
)

timing_summary = (
    f"On the broadened v22 prompt set, CPU chat-eval took {runtime_timings['chat_eval_cpu_seconds']:.3f}s and "
    f"GPU chat-eval took {runtime_timings['chat_eval_gpu_seconds']:.3f}s on this machine. "
    "That means the packaged newcomer flow should default to CPU for small-corpus responsiveness, while keeping GPU mode available for explicit experiments and future larger retrieval corpora."
)

report_md = f"""# SBAN v22 Follow-up Research Paper

## Release intent

SBAN v22 is the usability and hardening release.

The v21 generation made SBAN much safer and more honest, but it still felt brittle in everyday use. Retrieval missed reasonable paraphrases, session memory was still too template-shaped, divide-by-zero collapsed into generic uncertainty, and the session store still kept a hard turn cap. V22 keeps the trustworthiness contract from v21 and makes the runtime more natural to use.

## What changed in v22

1. Broader paraphrase tolerance in grounded retrieval through stronger token canonicalization plus direct grounded coverage for previously missed paraphrases such as historical version comparisons, Linux launch wording, GPU support wording, and bridge-memory questions.
2. Natural session memory for facts such as city, lab, and role, plus explicit capability handling for prompts like `can you remember my role if i tell you`.
3. Explicit symbolic divide-by-zero handling rather than falling back to generic uncertainty.
4. Uncapped continuing-session retention and unlimited session-file loading for the structured session format.
5. Longer hardening runs at 10M predictions on the common release profile and a near-full-corpus 100M-class run on a memory-bounded long-horizon profile that disables the order-4, order-5, and continuation expert bonuses.
6. Product-side CPU/GPU tuning: the runtime still supports OpenCL retrieval, but the newcomer flow now defaults to CPU because the grounded v22 corpus is small enough that CPU startup is faster for real users on this machine.

## Main measured results

### Original engine-health suite

| Test | V21 packaged | V22 packaged | Delta |
|---|---:|---:|---:|
| Prefix | {fmt(V21['prefix'])} | {fmt(prefix)} | {prefix - V21['prefix']:+.4f} pp |
| Drift | {fmt(V21['drift'])} | {fmt(drift)} | {drift - V21['drift']:+.4f} pp |
| Probe | {fmt(V21['probe'])} | {fmt(probe)} | {probe - V21['probe']:+.4f} pp |
| 250k | {fmt(V21['long_250k'])} | {fmt(long_250k)} | {long_250k - V21['long_250k']:+.4f} pp |
| 1M | {fmt(V21['long_1m'])} | {fmt(long_1m)} | {long_1m - V21['long_1m']:+.4f} pp |

### Expanded hardening runs

- 10M hardening accuracy: **{fmt(long_10m)}**
- Near-100M hardening accuracy: **{fmt(long_100m)}** over **{pred_100m:,}** predictions
- The near-100M hardening profile disables the order-4, order-5, and continuation expert bonuses so the long-horizon run stays bounded and reproducible on commodity hardware.

### Dialogue/runtime evaluation

- Hybrid chat eval: **{chat_hybrid['nonempty']} / {chat_hybrid['turns']}** non-empty, **{chat_hybrid['anchored']}** anchored, **{chat_hybrid['symbolic']}** symbolic
- Free chat eval: **{chat_free['nonempty']} / {chat_free['turns']}** non-empty, **{chat_free['anchored']}** anchored, **{chat_free['symbolic']}** symbolic
- Scripted session eval: **{session_eval['passed']} / {session_eval['expectations']}** expectation checks passed

### CPU/GPU validation

{gpu_summary}

{timing_summary}

## Concrete runtime behavior

### Paraphrase retrieval

```text
{chat_demo_paraphrase}
```

### Natural session memory

```text
{chat_demo_recall}
```

### Honest uncertainty

```text
{chat_demo_uncertainty}
```

### Explicit symbolic error handling

```text
{chat_demo_math_error}
```

### Continuing-session setup

```text
{chat_demo_setup}
```

### Future-version guard still declines unsupported questions

```text
{chat_demo_version_guard}
```

### Friendly missing-file diagnostics

```text
{chat_demo_missing_seed}
```

## Interpretation

V22 is not the generation that makes SBAN magically open-domain. It is the generation that makes the grounded runtime feel materially more usable without weakening the honesty constraint added in v21.

The numeric story remains intentionally conservative: the old core suite stays flat as an engine-health guardrail, the 10M run extends that common profile, and the near-100M artifact switches to a memory-bounded long-horizon profile so the hardest run remains measurable instead of failing on allocator pressure.

## Known limitations

1. The near-100M hardening run is limited by the exact size of the 100,000,000-byte enwik8 corpus, so the packaged run is just under a literal 100,000,000 predictions. That artifact also uses a memory-bounded long-horizon profile rather than a strict copy of the short-suite common profile.
2. GPU retrieval is supported and validated, but on the current small grounded corpus the OpenCL startup cost makes CPU the better default for newcomer chat loops on this machine.
3. Session memory remains intentionally scoped to simple structured facts and the current session file rather than a separate persistent memory service.
4. The numeric benchmark methodology still needs precise wording and should not be oversold as a broad intelligence benchmark.

## Bottom line

SBAN v22 keeps the measured engine-health baseline intact, broadens paraphrase tolerance, makes session memory more natural, removes the turn cap, adds long hardening runs, and ships a calmer product demo that defaults to the faster small-corpus CPU path while preserving explicit GPU experimentation.
"""

summary_md = f"""# SBAN v22 Executive Summary

## Release headline

**SBAN v22 keeps the trusted v21 grounding contract and makes the runtime materially easier to use.**

## What improved

- Broader paraphrase tolerance for grounded questions such as historical version comparisons, Linux launch wording, GPU support wording, and bridge-memory questions.
- More natural session memory for facts like city, lab, and role.
- Explicit divide-by-zero handling.
- No retained-turn cap in continuing sessions.
- Expanded hardening runs at 10M and near-100M predictions, with the near-100M artifact using a memory-bounded long-horizon profile.
- CPU remains the best default for the small grounded newcomer flow, while GPU support stays available through the OpenCL retrieval backend.

## Core measurements

- Prefix: {fmt(prefix)}
- Drift: {fmt(drift)}
- Probe: {fmt(probe)}
- 250k: {fmt(long_250k)}
- 1M: {fmt(long_1m)}
- 10M hardening: {fmt(long_10m)}
- Near-100M hardening: {fmt(long_100m)} over {pred_100m:,} predictions
- Hybrid chat eval: {chat_hybrid['nonempty']}/{chat_hybrid['turns']} non-empty
- Free chat eval: {chat_free['nonempty']}/{chat_free['turns']} non-empty
- Session eval: {session_eval['passed']}/{session_eval['expectations']} checks passed

## Operational note

{timing_summary}

## Bottom line

V22 is the generation where SBAN starts feeling less brittle in ordinary language while staying conservative enough to answer only when it really has support.
"""

report_path = ROOT / "SBAN_v22_REPORT.md"
summary_path = ROOT / "SBAN_v22_EXECUTIVE_SUMMARY.md"
paper_md_path = PAPERS / "SBAN_v22_follow_up_research_paper.md"
paper_pdf_path = PAPERS / "SBAN_v22_follow_up_research_paper.pdf"
repo_zip_path = DELIV / "SBAN_v22_repo.zip"

report_path.write_text(report_md, encoding="utf-8")
summary_path.write_text(summary_md, encoding="utf-8")
paper_md_path.write_text(report_md, encoding="utf-8")
render_markdown_to_pdf(report_md, paper_pdf_path)
write_repo_zip(repo_zip_path)

if BIN.exists() and os.name == "nt":
    subprocess.run(
        [
            os.environ.get("PYTHON", "python"),
            str(ROOT / "scripts" / "package_v22_demo.py"),
            "--binary",
            str(BIN),
            "--platform",
            "windows_x86_64",
        ],
        cwd=ROOT,
        check=True,
    )

for path in [report_path, summary_path, paper_pdf_path, repo_zip_path]:
    shutil.copy2(path, DELIV / path.name)
    shutil.copy2(path, DOWNLOADS / path.name)

print(report_path)
print(summary_path)
print(paper_pdf_path)
print(repo_zip_path)
