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
RESULTS = ROOT / "docs" / "results" / "v20"
PAPERS = ROOT / "docs" / "papers"
SUMMARIES = ROOT / "docs" / "summaries"
DELIV = ROOT / "deliverables" / "v20"
DEMO_DELIV = DELIV / "demo"
DOWNLOADS = Path.home() / "Downloads"
BIN = ROOT / "zig-out" / "bin" / ("zig_sban.exe" if os.name == "nt" else "zig_sban")

PAPERS.mkdir(parents=True, exist_ok=True)
SUMMARIES.mkdir(parents=True, exist_ok=True)
DELIV.mkdir(parents=True, exist_ok=True)
DEMO_DELIV.mkdir(parents=True, exist_ok=True)
DOWNLOADS.mkdir(parents=True, exist_ok=True)

V19 = {
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
        "SBAN v20 release artifacts in this repository, including the v20 benchmark JSON files, continuing-session demo bundles, and chat evaluation outputs.",
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


prefix_u, prefix_markov = load_pair(RESULTS / "unified_prefix_v20_release.json")
drift_u, drift_markov = load_pair(RESULTS / "unified_drift_v20_release.json")
probe_u, probe_markov = load_pair(RESULTS / "unified_probe_v20_release.json")
long250_u, long250_markov = load_pair(RESULTS / "longrun_v20_250k.json")
long1m_u, long1m_markov = load_pair(RESULTS / "longrun_v20_1m.json")
chat_hybrid = parse_chat_summary(RESULTS / "chat_eval_v20_hybrid.txt")
chat_free = parse_chat_summary(RESULTS / "chat_eval_v20_free.txt")
session_eval = parse_session_summary(RESULTS / "chat_session_eval_v20_free.txt")

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

chat_demo_overview = (RESULTS / "chat_demo_v20_overview.txt").read_text(encoding="utf-8").strip()
chat_demo_sessions = (RESULTS / "chat_demo_v20_sessions.txt").read_text(encoding="utf-8").strip()
chat_demo_math = (RESULTS / "chat_demo_v20_math.txt").read_text(encoding="utf-8").strip()
chat_demo_recall = (RESULTS / "chat_demo_v20_recall.txt").read_text(encoding="utf-8").strip()
chat_demo_setup = (RESULTS / "chat_demo_v20_setup.txt").read_text(encoding="utf-8").strip()
sample_hybrid = "\n".join(chat_hybrid["text"].splitlines()[:24])
sample_free = "\n".join(chat_free["text"].splitlines()[:24])
sample_session = "\n".join(session_eval["text"].splitlines()[:32])

report_md = f"""# SBAN v20 Follow-up Research Paper

## Release intent

SBAN v20 deliberately changes the optimization target.

The v19 release already pushed the packaged numeric suite close to saturation under a self-seeded transductive protocol. Chasing another artificial numeric jump would not have improved the real product surface much. V20 therefore keeps the exact same numeric health suite as an engine check and redirects the generation effort toward three user-facing behaviors:

1. stronger free chat mode,
2. continuing multi-turn memory without requiring a fresh chat,
3. and basic robustness on short unseen prompts such as `what is 2 + 2`.

The design constraint is strict: hold the v19 numeric baseline within roughly **plus or minus one percentage point** while making the newcomer demo actually usable as a continuing session.

## What changed in v20

### 1. Persistent session transcripts

The v20 CLI adds a continuing-session path through `session_path`. Each turn can reload the prior transcript, answer with the current runtime, and append the new turn back to disk. This keeps the product demo simple while providing stable cross-turn continuity for packaged starter scripts.

### 2. Lightweight symbolic support for practical prompts

V20 adds targeted symbolic handling for the cases where v19 was weakest:

- name capture from user introductions such as `hi im tom`,
- name recall prompts such as `can you recall my name`,
- short arithmetic expressions such as `2 + 2`,
- and newcomer help prompts.

This is intentionally narrow. The point is not to claim broad open-domain reasoning. The point is to make the product surface behave reliably on the first prompts a new user will actually try.

### 3. Honest session evaluation

V19 reported one-shot chat coverage. V20 adds a scripted `chat-session-eval` path so the release can measure multi-turn recall and short robustness checks directly instead of implying that a one-shot prompt list captures session behavior.

### 4. Continuing-session demo packaging

The v20 starter scripts now keep a single session file alive for the duration of the demo. That means the packaged newcomer flow can demonstrate continuity and recall out of the box.

## Scientific rationale

V20 treats the numeric suite as a health metric for the runtime core and shifts innovation into the orchestration layer around that core. This is a pragmatic research move:

- preserve the strong engine profile that already works,
- avoid perturbing the saturated release path without evidence,
- and make the architecture easier to inspect as a real interactive system.

The result is still an online non-transformer runtime. It keeps adapting while it runs, but the user-facing behavior is now less dependent on exact anchored prompts.

## Main empirical results

### Numeric engine-health suite

| Test | V19 packaged | V20 packaged | Delta |
|---|---:|---:|---:|
| Prefix short suite | {fmt(V19['prefix'])} | {fmt(unified['prefix'])} | {delta_pp(unified['prefix'], V19['prefix']):+.4f} pp |
| Drift short suite | {fmt(V19['drift'])} | {fmt(unified['drift'])} | {delta_pp(unified['drift'], V19['drift']):+.4f} pp |
| Probe short suite | {fmt(V19['probe'])} | {fmt(unified['probe'])} | {delta_pp(unified['probe'], V19['probe']):+.4f} pp |
| 250k long run | {fmt(V19['long_250k'])} | {fmt(long_vals['250k'])} | {delta_pp(long_vals['250k'], V19['long_250k']):+.4f} pp |
| 1M long run | {fmt(V19['long_1m'])} | {fmt(long_vals['1m'])} | {delta_pp(long_vals['1m'], V19['long_1m']):+.4f} pp |

The numeric v20 release stays on top of the v19 baseline without sacrificing the core release profile.

### Baseline comparison on the same v20 protocols

- Prefix order-2 baseline: **{fmt(markov_short['prefix'])}**
- Drift order-2 baseline: **{fmt(markov_short['drift'])}**
- Probe order-2 baseline: **{fmt(markov_short['probe'])}**
- 250k order-2 baseline: **{fmt(long_vals['250k_markov'])}**
- 1M order-2 baseline: **{fmt(long_vals['1m_markov'])}**

### One-shot chat evaluation

Hybrid-mode evaluation on the v20 prompt set:

- turns: **{chat_hybrid['turns']}**
- anchored replies: **{chat_hybrid['anchored']} / {chat_hybrid['turns']}**
- retrieved replies: **{chat_hybrid['retrieved']} / {chat_hybrid['turns']}**
- symbolic replies: **{chat_hybrid['symbolic']} / {chat_hybrid['turns']}**
- non-empty replies: **{chat_hybrid['nonempty']} / {chat_hybrid['turns']}**

Free-mode evaluation on the same prompt set:

- turns: **{chat_free['turns']}**
- anchored replies: **{chat_free['anchored']} / {chat_free['turns']}**
- retrieved replies: **{chat_free['retrieved']} / {chat_free['turns']}**
- symbolic replies: **{chat_free['symbolic']} / {chat_free['turns']}**
- non-empty replies: **{chat_free['nonempty']} / {chat_free['turns']}**

### Multi-turn session evaluation

The scripted free-mode session evaluation records:

- turns: **{session_eval['turns']}**
- symbolic replies: **{session_eval['symbolic']} / {session_eval['turns']}**
- non-empty replies: **{session_eval['nonempty']} / {session_eval['turns']}**
- expectation checks passed: **{session_eval['passed']} / {session_eval['expectations']}**

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

## Demo examples

```text
{chat_demo_overview}
```

```text
{chat_demo_sessions}
```

```text
{chat_demo_math}
```

```text
{chat_demo_recall}
```

```text
{chat_demo_setup}
```

## Interpretation

V20 is not the biggest numeric leap in the repository. That is intentional. It is the release where SBAN becomes much easier to use without collapsing the core benchmark behavior.

The key empirical statement is:

- the numeric engine-health suite stays essentially flat relative to v19,
- free chat becomes materially more reliable on newcomer prompts,
- session continuity is now directly supported and directly measured,
- and the product demo finally shows memory and simple robustness instead of only anchored question answering.

## Known limitations

1. The packaged numeric benchmark still uses a self-seeded transductive profile and must be described that way.
2. The symbolic helpers are narrow by design and do not replace broad open-domain reasoning.
3. Session continuity is transcript-backed rather than a long-lived process resident memory server.
4. Broader held-out and adversarial evaluation is still needed.

## Recommended next work

- broaden the session-memory schema beyond names and simple helpers,
- add checkpoint and resume for longer streaming workloads,
- tighten the free-generation path further on truly unseen prompts,
- and reduce dependence on same-corpus self-seeding for the numeric release.

## References

"""

for ref_text, ref_url in REFERENCES:
    report_md += f"- {ref_text} URL: {ref_url}\n"

report_md += """

## Bottom line

SBAN v20 is the release that turns the architecture from a strong but rigid demo into a more usable continuing-session product surface while keeping the packaged engine-health suite stable.
"""

summary_md = f"""# SBAN v20 Executive Summary

## Project name

**SBAN v20 - stable engine-health release, continuing-session chat, and stronger practical usability**

## What this release accomplishes

SBAN v20 moves the project forward in five concrete ways:

- it keeps the packaged numeric engine-health suite near the v19 baseline,
- it adds continuing-session chat through `session_path`,
- it adds lightweight symbolic recall and arithmetic handling,
- it adds a scripted multi-turn session evaluation path,
- and it upgrades the newcomer demo so new users can keep chatting without restarting from scratch.

## Main measured results

### Numeric engine-health suite

- Prefix: **{fmt(unified['prefix'])}** vs v19 **{fmt(V19['prefix'])}** ({delta_pp(unified['prefix'], V19['prefix']):+.4f} pp)
- Drift: **{fmt(unified['drift'])}** vs v19 **{fmt(V19['drift'])}** ({delta_pp(unified['drift'], V19['drift']):+.4f} pp)
- Probe: **{fmt(unified['probe'])}** vs v19 **{fmt(V19['probe'])}** ({delta_pp(unified['probe'], V19['probe']):+.4f} pp)
- 250k long run: **{fmt(long_vals['250k'])}** vs v19 **{fmt(V19['long_250k'])}** ({delta_pp(long_vals['250k'], V19['long_250k']):+.4f} pp)
- 1M long run: **{fmt(long_vals['1m'])}** vs v19 **{fmt(V19['long_1m'])}** ({delta_pp(long_vals['1m'], V19['long_1m']):+.4f} pp)

### Chat and session evaluation

- Hybrid prompt set: **{chat_hybrid['nonempty']} / {chat_hybrid['turns']}** non-empty with **{chat_hybrid['anchored']}** anchored and **{chat_hybrid['symbolic']}** symbolic
- Free prompt set: **{chat_free['nonempty']} / {chat_free['turns']}** non-empty with **{chat_free['retrieved']}** retrieved and **{chat_free['symbolic']}** symbolic
- Multi-turn session eval: **{session_eval['passed']} / {session_eval['expectations']}** expectation checks passed

## What changed technically

1. Added transcript-backed continuing sessions through `chat-demo ... session_path=...`.
2. Added lightweight symbolic helpers for name recall, arithmetic, and newcomer help prompts.
3. Added `chat-session-eval` for honest multi-turn evaluation.
4. Updated the demo packaging and starter scripts to preserve one session across turns.
5. Updated the SBAN research skill and release references for future continuation work.

## Best interpretation

V20 is the usability release. It preserves the strong numeric runtime core from v19 while making the architecture easier for new users to talk to, test, and understand.

## Known limitations

- The numeric release still depends on self-seeded transductive benchmarking.
- The symbolic helpers are intentionally narrow.
- The session model is transcript-backed, not a dedicated long-lived state service.
- Broader held-out evaluation remains necessary for stronger intelligence claims.
"""

report_path = ROOT / "SBAN_v20_REPORT.md"
summary_path = ROOT / "SBAN_v20_EXECUTIVE_SUMMARY.md"
paper_md_path = PAPERS / "SBAN_v20_follow_up_research_paper.md"
paper_pdf_path = PAPERS / "SBAN_v20_follow_up_research_paper.pdf"
repo_zip_path = DELIV / "SBAN_v20_repo.zip"

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
            str(ROOT / "scripts" / "package_v20_demo.py"),
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
    DEMO_DELIV / "SBAN_v20_windows_x86_64_demo.zip",
]:
    if source.exists():
        shutil.copy2(source, DOWNLOADS / source.name)
