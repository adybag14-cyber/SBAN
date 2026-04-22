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
RESULTS = ROOT / "docs" / "results" / "v21"
PAPERS = ROOT / "docs" / "papers"
SUMMARIES = ROOT / "docs" / "summaries"
DELIV = ROOT / "deliverables" / "v21"
DEMO_DELIV = DELIV / "demo"
DOWNLOADS = Path.home() / "Downloads"
BIN = ROOT / "zig-out" / "bin" / ("zig_sban.exe" if os.name == "nt" else "zig_sban")

PAPERS.mkdir(parents=True, exist_ok=True)
SUMMARIES.mkdir(parents=True, exist_ok=True)
DELIV.mkdir(parents=True, exist_ok=True)
DEMO_DELIV.mkdir(parents=True, exist_ok=True)
DOWNLOADS.mkdir(parents=True, exist_ok=True)

V20 = {
    "prefix": 99.6350,
    "drift": 99.5400,
    "probe": 99.9000,
    "long_250k": 99.4076,
    "long_1m": 99.4344,
}

REFERENCES = [
    (
        "Frans M. J. Willems, Yuri M. Shtarkov, and Tjalling J. Tjalkens (1995). "
        "The Context-Tree Weighting Method: Basic Properties. IEEE Transactions on Information Theory, 41(3), 653-664.",
        "https://pure.tue.nl/ws/files/1383848/Metis122608.pdf",
    ),
    (
        "Mark Herbster and Manfred K. Warmuth (1998). Tracking the Best Expert. Machine Learning, 32(2), 151-178.",
        "https://mwarmuth.bitbucket.io/pubs/J39.pdf",
    ),
    (
        "Khronos Group OpenCL Registry and API reference, used for the v21 optional GPU retrieval backend.",
        "https://registry.khronos.org/OpenCL/",
    ),
    (
        "SBAN v21 release artifacts in this repository, including the benchmark JSON files, dialogue assets, chat evaluation outputs, and packaged demo bundles.",
        "https://github.com/adybag14-cyber/SBAN",
    ),
]


def load_pair(path: Path):
    data = json.loads(path.read_text(encoding="utf-8"))
    return data["models"][0], data["models"][1]


def acc(model: dict) -> float:
    return 100.0 * model["total_correct"] / model["total_predictions"]


def fmt(value: float) -> str:
    return f"{value:.4f}%"


def delta_pp(new: float, old: float) -> float:
    return new - old


def parse_chat_summary(path: Path) -> dict[str, int | str]:
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
        "uncertain": int(match.group(1)) - int(match.group(2)) - int(match.group(3)) - int(match.group(4)),
        "text": text,
    }


def parse_session_summary(path: Path) -> dict[str, int | str]:
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
        "text": text,
    }


def parse_key_values(path: Path) -> dict[str, str]:
    data: dict[str, str] = {}
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        if "=" not in raw_line:
            continue
        key, value = raw_line.split("=", 1)
        data[key.strip()] = value.strip()
    return data


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
            if path == output_path:
                continue
            if path.is_dir():
                continue
            zf.write(path, rel.as_posix())


prefix_u, prefix_markov = load_pair(RESULTS / "unified_prefix_v21_release.json")
drift_u, drift_markov = load_pair(RESULTS / "unified_drift_v21_release.json")
probe_u, probe_markov = load_pair(RESULTS / "unified_probe_v21_release.json")
long250_u, long250_markov = load_pair(RESULTS / "longrun_v21_250k.json")
long1m_u, long1m_markov = load_pair(RESULTS / "longrun_v21_1m.json")
chat_hybrid = parse_chat_summary(RESULTS / "chat_eval_v21_hybrid.txt")
chat_free = parse_chat_summary(RESULTS / "chat_eval_v21_free.txt")
session_eval = parse_session_summary(RESULTS / "chat_session_eval_v21.txt")
accel_info = parse_key_values(RESULTS / "accel_info_v21.txt")

unified = {
    "prefix": acc(prefix_u),
    "drift": acc(drift_u),
    "probe": acc(probe_u),
}
markov_short = {
    "prefix": acc(prefix_markov),
    "drift": acc(drift_markov),
    "probe": acc(probe_markov),
}
long_vals = {
    "250k": acc(long250_u),
    "250k_markov": acc(long250_markov),
    "1m": acc(long1m_u),
    "1m_markov": acc(long1m_markov),
}

chat_demo_overview = (RESULTS / "chat_demo_v21_overview.txt").read_text(encoding="utf-8").strip()
chat_demo_architecture = (RESULTS / "chat_demo_v21_architecture.txt").read_text(encoding="utf-8").strip()
chat_demo_compare = (RESULTS / "chat_demo_v21_compare.txt").read_text(encoding="utf-8").strip()
chat_demo_uncertainty = (RESULTS / "chat_demo_v21_uncertainty.txt").read_text(encoding="utf-8").strip()
chat_demo_version_guard = (RESULTS / "chat_demo_v21_version_guard.txt").read_text(encoding="utf-8").strip()
chat_demo_math = (RESULTS / "chat_demo_v21_math.txt").read_text(encoding="utf-8").strip()
chat_demo_recall = (RESULTS / "chat_demo_v21_recall.txt").read_text(encoding="utf-8").strip()
chat_demo_setup = (RESULTS / "chat_demo_v21_setup.txt").read_text(encoding="utf-8").strip()
chat_demo_injection = (RESULTS / "chat_demo_v21_injection_safe.txt").read_text(encoding="utf-8").strip()
chat_demo_missing_seed = (RESULTS / "chat_demo_v21_missing_seed.txt").read_text(encoding="utf-8").strip()
sample_hybrid = "\n".join(chat_hybrid["text"].splitlines()[:28])
sample_free = "\n".join(chat_free["text"].splitlines()[:28])
sample_session = "\n".join(session_eval["text"].splitlines()[:36])

if accel_info.get("backend") == "gpu":
    accel_summary = (
        f"On the local validation machine, `accel-info` resolved the optional GPU backend successfully: "
        f"platform `{accel_info.get('platform', 'unknown')}`, device `{accel_info.get('device', 'unknown')}`."
    )
else:
    accel_summary = (
        "On the local validation machine, `accel-info` fell back to CPU mode. "
        "The v21 runtime still supports the OpenCL path, but compatible GPU acceleration was not active in this capture."
    )

report_md = f"""# SBAN v21 Follow-up Research Paper

## Release intent

SBAN v21 is the reliability and grounding release.

The v20 generation made SBAN much more usable than the earlier benchmark-first releases, but the chat surface was still too close to a seeded retrieval demo with a few symbolic patches. In particular, unsupported prompts could drift into plausible but wrong canned answers, retrieval could over-match nearby release prompts, general session memory was too narrow, math outside a tiny integer grammar was unsafe, raw transcript persistence was vulnerable to prompt injection, and missing assets could surface raw file errors instead of product-grade diagnostics.

V21 keeps the same packaged numeric engine-health suite as the core guardrail and upgrades the conversation runtime so it behaves more like a dependable collaborator:

1. grounded when it knows,
2. explicit when it does not,
3. able to remember user facts naturally across a session,
4. resistant to transcript corruption,
5. and capable of running retrieval scoring on CPU or GPU.

## What changed in v21

### 1. Stricter grounded routing

The v20 loose token-overlap matcher is replaced by stronger lexical gating and explicit version-token conflict rejection. This directly fixes failure modes such as a future-version question retrieving the answer for the current version.

### 2. General session fact memory

V21 stores and recalls general facts such as names, favorite colors, and preferences, not only a narrow name-only path. User introductions with follow-on clauses such as `hi i am tom and i need help` now store the name correctly while still returning contextual help.

### 3. Safer symbolic reasoning

The runtime now supports short arithmetic with negatives, decimals, operator precedence, and parentheses. Unsupported expressions fail closed instead of silently rewriting the question into a wrong integer-only answer.

### 4. Structured session persistence

V21 no longer persists raw transcript lines directly. It sanitizes turn text and stores encoded structured fields under a versioned session format, eliminating the transcript corruption issue caused by embedded newlines and forged `User:` or `Assistant:` markers.

### 5. Product-grade error handling

Missing assets now return user-facing diagnostics such as `error=missing_file label=seed_path ...` rather than exposing raw filesystem exceptions.

### 6. First CPU or GPU retrieval acceleration

The retrieval scorer now supports CPU execution and an optional OpenCL path. GPU acceleration is opportunistic rather than required, so the runtime remains deployable on plain CPU machines while able to use compatible GPUs on systems where OpenCL is available.

## Main empirical results

### Numeric engine-health suite

| Test | V20 packaged | V21 packaged | Delta |
|---|---:|---:|---:|
| Prefix short suite | {fmt(V20['prefix'])} | {fmt(unified['prefix'])} | {delta_pp(unified['prefix'], V20['prefix']):+.4f} pp |
| Drift short suite | {fmt(V20['drift'])} | {fmt(unified['drift'])} | {delta_pp(unified['drift'], V20['drift']):+.4f} pp |
| Probe short suite | {fmt(V20['probe'])} | {fmt(unified['probe'])} | {delta_pp(unified['probe'], V20['probe']):+.4f} pp |
| 250k long run | {fmt(V20['long_250k'])} | {fmt(long_vals['250k'])} | {delta_pp(long_vals['250k'], V20['long_250k']):+.4f} pp |
| 1M long run | {fmt(V20['long_1m'])} | {fmt(long_vals['1m'])} | {delta_pp(long_vals['1m'], V20['long_1m']):+.4f} pp |

The numeric core stays locked to the prior packaged baseline, which is exactly the intended engine-health outcome for this generation.

### Baseline comparison on the same v21 protocols

- Prefix order-2 baseline: **{fmt(markov_short['prefix'])}**
- Drift order-2 baseline: **{fmt(markov_short['drift'])}**
- Probe order-2 baseline: **{fmt(markov_short['probe'])}**
- 250k order-2 baseline: **{fmt(long_vals['250k_markov'])}**
- 1M order-2 baseline: **{fmt(long_vals['1m_markov'])}**

### One-shot chat evaluation

Hybrid-mode evaluation on the v21 prompt set:

- turns: **{chat_hybrid['turns']}**
- anchored replies: **{chat_hybrid['anchored']} / {chat_hybrid['turns']}**
- retrieved replies: **{chat_hybrid['retrieved']} / {chat_hybrid['turns']}**
- symbolic replies: **{chat_hybrid['symbolic']} / {chat_hybrid['turns']}**
- uncertainty replies: **{chat_hybrid['uncertain']} / {chat_hybrid['turns']}**
- non-empty replies: **{chat_hybrid['nonempty']} / {chat_hybrid['turns']}**

Free-mode evaluation on the same prompt set:

- turns: **{chat_free['turns']}**
- anchored replies: **{chat_free['anchored']} / {chat_free['turns']}**
- retrieved replies: **{chat_free['retrieved']} / {chat_free['turns']}**
- symbolic replies: **{chat_free['symbolic']} / {chat_free['turns']}**
- uncertainty replies: **{chat_free['uncertain']} / {chat_free['turns']}**
- non-empty replies: **{chat_free['nonempty']} / {chat_free['turns']}**

### Multi-turn session evaluation

The scripted v21 session evaluation records:

- turns: **{session_eval['turns']}**
- symbolic replies: **{session_eval['symbolic']} / {session_eval['turns']}**
- non-empty replies: **{session_eval['nonempty']} / {session_eval['turns']}**
- expectation checks passed: **{session_eval['passed']} / {session_eval['expectations']}**

### Local CPU or GPU validation

{accel_summary}

Example hybrid excerpt:

```text
{sample_hybrid}
```

Example free excerpt:

```text
{sample_free}
```

Example session excerpt:

```text
{sample_session}
```

## Concrete failure-mode fixes

### Unsupported prompts now decline cleanly

```text
{chat_demo_uncertainty}
```

### Nearby-but-wrong version prompts no longer cross versions

```text
{chat_demo_version_guard}
```

### Architecture and comparison prompts answer with grounded domain content

```text
{chat_demo_architecture}
```

```text
{chat_demo_compare}
```

### General session facts now persist and recall correctly

```text
{chat_demo_recall}
```

### Arithmetic handles negatives and decimals

```text
{chat_demo_math}
```

### Session persistence is injection-safe

```text
{chat_demo_injection}
```

### Missing assets now produce friendly diagnostics

```text
{chat_demo_missing_seed}
```

### Product demo setup remains simple

```text
{chat_demo_overview}
```

```text
{chat_demo_setup}
```

## Interpretation

V21 is the generation where SBAN stops rewarding the illusion of competence and starts optimizing for trust.

The important scientific move is not another synthetic numeric jump. The important move is that the runtime now has a firmer contract:

- answer precisely when grounded support exists,
- store and recall session facts naturally,
- solve the narrow symbolic cases it explicitly supports,
- reject unsupported lookalikes instead of bluffing,
- and keep the same measured engine-health profile as the stabilized numeric core.

## Known limitations

1. The packaged numeric benchmark story still needs to be described carefully according to the release methodology and should not be oversold as a broad generalization benchmark.
2. The dialogue runtime remains intentionally conservative; many open-domain prompts will return uncertainty instead of speculative generation.
3. The GPU backend currently accelerates retrieval scoring only. It is not a fully GPU-native end-to-end SBAN execution path.
4. Session memory is still scoped to the current transcript-backed session rather than a separate long-lived memory service.

## Recommended next work

- expand grounded knowledge without reintroducing loose retrieval,
- add richer typed session memory beyond simple scalar facts,
- deepen held-out adversarial chat evaluation,
- and explore broader GPU coverage beyond the retrieval scorer.

## References

"""

for ref_text, ref_url in REFERENCES:
    report_md += f"- {ref_text} URL: {ref_url}\n"

report_md += """

## Bottom line

SBAN v21 keeps the numeric engine-health core stable and makes the chat runtime significantly more dependable. It is a stronger product release because it is more willing to say less when support is weak.
"""

summary_md = f"""# SBAN v21 Executive Summary

## Project name

**SBAN v21 - grounded dialogue, general session memory, safer persistence, and first CPU or GPU retrieval acceleration**

## What this release accomplishes

SBAN v21 turns the current chat surface into a calmer and more trustworthy runtime:

- unsupported prompts now return honest uncertainty instead of irrelevant canned blurbs,
- retrieval matching is stricter and avoids version-crossing mistakes,
- session memory stores general user facts such as names and favorite colors,
- arithmetic now handles negatives and decimals safely,
- session persistence uses a structured encoded format instead of raw transcript text,
- missing assets return friendly diagnostics,
- and retrieval can run on CPU or use an OpenCL-capable GPU when available.

## Main measured results

### Numeric engine-health suite

- Prefix: **{fmt(unified['prefix'])}** vs v20 **{fmt(V20['prefix'])}** ({delta_pp(unified['prefix'], V20['prefix']):+.4f} pp)
- Drift: **{fmt(unified['drift'])}** vs v20 **{fmt(V20['drift'])}** ({delta_pp(unified['drift'], V20['drift']):+.4f} pp)
- Probe: **{fmt(unified['probe'])}** vs v20 **{fmt(V20['probe'])}** ({delta_pp(unified['probe'], V20['probe']):+.4f} pp)
- 250k long run: **{fmt(long_vals['250k'])}** vs v20 **{fmt(V20['long_250k'])}** ({delta_pp(long_vals['250k'], V20['long_250k']):+.4f} pp)
- 1M long run: **{fmt(long_vals['1m'])}** vs v20 **{fmt(V20['long_1m'])}** ({delta_pp(long_vals['1m'], V20['long_1m']):+.4f} pp)

### Chat and reliability evaluation

- Hybrid prompt set: **{chat_hybrid['nonempty']} / {chat_hybrid['turns']}** non-empty with **{chat_hybrid['anchored']}** anchored, **{chat_hybrid['symbolic']}** symbolic, and **{chat_hybrid['uncertain']}** explicit uncertainty replies
- Free prompt set: **{chat_free['nonempty']} / {chat_free['turns']}** non-empty with **{chat_free['symbolic']}** symbolic and **{chat_free['uncertain']}** explicit uncertainty replies
- Multi-turn session eval: **{session_eval['passed']} / {session_eval['expectations']}** expectation checks passed

### Local acceleration check

- backend: **{accel_info.get('backend', 'unknown')}**
"""

if accel_info.get("backend") == "gpu":
    summary_md += f"- platform: **{accel_info.get('platform', 'unknown')}**\n- device: **{accel_info.get('device', 'unknown')}**\n"
else:
    summary_md += f"- reason: **{accel_info.get('reason', 'n/a')}**\n"

summary_md += """

## What changed technically

1. Added `src/dialogue.zig` as the grounded dialogue runtime for matching, memory, math, persistence, and acceleration.
2. Added structured v21 session files with encoded fact and turn storage.
3. Added version-aware retrieval rejection and stronger uncertainty behavior.
4. Added an optional OpenCL retrieval backend with automatic CPU fallback.
5. Added versioned v21 prompt assets, scripted session evaluation, release scripts, and packaged demo bundles.

## Best interpretation

V21 is the trustworthiness release. It preserves the stabilized numeric core from v20 while making the runtime substantially safer and more useful for real conversational work.

## Known limitations

- The numeric benchmark story still needs careful release-method wording.
- The runtime is intentionally conservative on unsupported open-domain prompts.
- GPU acceleration currently targets retrieval scoring rather than the whole runtime.
- Session memory remains transcript-scoped rather than global.
"""

report_path = ROOT / "SBAN_v21_REPORT.md"
summary_path = ROOT / "SBAN_v21_EXECUTIVE_SUMMARY.md"
paper_md_path = PAPERS / "SBAN_v21_follow_up_research_paper.md"
paper_pdf_path = PAPERS / "SBAN_v21_follow_up_research_paper.pdf"
repo_zip_path = DELIV / "SBAN_v21_repo.zip"

report_path.write_text(report_md, encoding="utf-8")
summary_path.write_text(summary_md, encoding="utf-8")
ROOT.joinpath("EXECUTIVE_SUMMARY.md").write_text(summary_md, encoding="utf-8")
paper_md_path.write_text(report_md, encoding="utf-8")
SUMMARIES.joinpath(summary_path.name).write_text(summary_md, encoding="utf-8")

render_markdown_to_pdf(paper_md_path, paper_pdf_path)
shutil.copy2(paper_pdf_path, ROOT / "docs" / "research_paper.pdf")
DELIV.joinpath(summary_path.name).write_text(summary_md, encoding="utf-8")
DELIV.joinpath(paper_md_path.name).write_text(report_md, encoding="utf-8")
shutil.copy2(paper_pdf_path, DELIV / paper_pdf_path.name)

write_repo_zip(repo_zip_path)

if BIN.exists():
    subprocess.run(
        [
            "python",
            str(ROOT / "scripts" / "package_v21_demo.py"),
            "--binary",
            str(BIN),
            "--platform",
            "windows_x86_64",
            "--output-dir",
            str(DEMO_DELIV),
        ],
        cwd=ROOT,
        check=True,
    )

for source in [
    report_path,
    summary_path,
    paper_pdf_path,
    repo_zip_path,
    DEMO_DELIV / "SBAN_v21_windows_x86_64_demo.zip",
]:
    if source.exists():
        shutil.copy2(source, DOWNLOADS / source.name)
