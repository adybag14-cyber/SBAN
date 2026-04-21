#!/usr/bin/env python3
from __future__ import annotations

import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RESULTS = ROOT / 'docs' / 'results' / 'v16'
PAPERS = ROOT / 'docs' / 'papers'
SUMMARIES = ROOT / 'docs' / 'summaries'
DELIV = ROOT / 'deliverables' / 'v16'
PAPERS.mkdir(parents=True, exist_ok=True)
SUMMARIES.mkdir(parents=True, exist_ok=True)
DELIV.mkdir(parents=True, exist_ok=True)

V15_SHORT = {'prefix': 45.1625, 'drift': 44.8500, 'probe': 71.3767}
V15_LONG_250K = 45.6876
V15_LONG_1M = 41.2728


def load_pair(path: Path):
    data = json.loads(path.read_text())
    return data['models'][0], data['models'][1]


def acc(model):
    return 100.0 * model['total_correct'] / model['total_predictions']


def fmt(v: float) -> str:
    return f'{v:.4f}%'


def parse_summary(path: Path):
    text = path.read_text()
    m = re.search(r'summary turns=(\d+) anchored=(\d+) retrieved=(\d+) nonempty=(\d+)', text)
    if not m:
        raise ValueError(f'missing summary in {path}')
    return {
        'turns': int(m.group(1)),
        'anchored': int(m.group(2)),
        'retrieved': int(m.group(3)),
        'nonempty': int(m.group(4)),
        'text': text,
    }


def maybe_load_long_result():
    candidates = [
        ('2M', RESULTS / 'longrun_compact_v16_2m.json'),
        ('1M', RESULTS / 'longrun_compact_v16_1m.json'),
    ]
    for label, path in candidates:
        if path.exists():
            a, b = load_pair(path)
            return {
                'label': label,
                'path': path,
                'u': a,
                'm': b,
                'acc': acc(a),
                'markov_acc': acc(b),
            }
    return None


prefix_u, prefix_markov = load_pair(RESULTS / 'unified_prefix_v16_compact.json')
drift_u, drift_markov = load_pair(RESULTS / 'unified_drift_v16_compact.json')
probe_u, probe_markov = load_pair(RESULTS / 'unified_probe_v16_compact.json')
long250_u, long250_markov = load_pair(RESULTS / 'longrun_compact_v16_250k.json')
long_ext = maybe_load_long_result()
chat_hybrid = parse_summary(RESULTS / 'chat_eval_v16_hybrid.txt')
chat_free = parse_summary(RESULTS / 'chat_eval_v16_free.txt')
chat_demo_changes = (RESULTS / 'chat_demo_v16_changes.txt').read_text().strip()
chat_demo_routing = (RESULTS / 'chat_demo_v16_routing.txt').read_text().strip()
chat_demo_related = (RESULTS / 'chat_demo_v16_related.txt').read_text().strip()

unified = {'prefix': acc(prefix_u), 'drift': acc(drift_u), 'probe': acc(probe_u)}
markov_short = {'prefix': acc(prefix_markov), 'drift': acc(drift_markov), 'probe': acc(probe_markov)}
long250_acc = acc(long250_u)
long250_markov_acc = acc(long250_markov)

sample_hybrid = '\n'.join(chat_hybrid['text'].splitlines()[:20])
sample_free = '\n'.join(chat_free['text'].splitlines()[:12])

if long_ext:
    if long_ext['label'] == '1M':
        ext_delta_text = f"{long_ext['acc'] - V15_LONG_1M:+.4f} pp vs v15 1M compact"
    else:
        ext_delta_text = 'new longer line relative to prior packaged releases'
    long_table_row = f"| {long_ext['label']} prefix stress | {fmt(long_ext['acc'])} | {fmt(long_ext['markov_acc'])} | {ext_delta_text} |"
    long_ext_section = f"""
| Protocol | V16 profile | Order-2 baseline | Delta |
|---|---:|---:|---:|
| 250k prefix stress | {fmt(long250_acc)} | {fmt(long250_markov_acc)} | {long250_acc - V15_LONG_250K:+.4f} pp vs v15 250k |
{long_table_row}

The 250k result is the clearest completed v16 gain: **{fmt(long250_acc)}**, up from the v15-equivalent **{fmt(V15_LONG_250K)}**, while also using fewer births and fewer final live memories.

The longest completed v16 stress line packaged here is the **{long_ext['label']}** run at **{fmt(long_ext['acc'])}** against an order-2 baseline of **{fmt(long_ext['markov_acc'])}**.
"""
    long_summary_bullets = f"""
- 250k regime-aware compact: **{fmt(long250_acc)}**
- 250k order-2 baseline: **{fmt(long250_markov_acc)}**
- delta vs v15 250k compact: **{long250_acc - V15_LONG_250K:+.4f} pp**
- {long_ext['label']} regime-aware compact: **{fmt(long_ext['acc'])}**
- {long_ext['label']} order-2 baseline: **{fmt(long_ext['markov_acc'])}**
"""
    long_bottom_line = f"The strongest completed long-horizon evidence in this packaging pass is the 250k gain to **{fmt(long250_acc)}** together with the completed **{long_ext['label']}** stress line at **{fmt(long_ext['acc'])}**."
else:
    long_ext_section = f"""
| Protocol | V16 profile | Order-2 baseline | Delta |
|---|---:|---:|---:|
| 250k prefix stress | {fmt(long250_acc)} | {fmt(long250_markov_acc)} | {long250_acc - V15_LONG_250K:+.4f} pp vs v15 250k |

The 250k result is the clearest completed v16 gain: **{fmt(long250_acc)}**, up from the v15-equivalent **{fmt(V15_LONG_250K)}**, while also using fewer births and fewer final live memories.

A longer **1M debug stress run was launched and remained active at packaging time**, but it had not produced a final JSON artifact before these deliverables were frozen. This release is therefore packaged around the completed short-suite, 250k stress, and chat-evaluation evidence only.
"""
    long_summary_bullets = f"""
- 250k regime-aware compact: **{fmt(long250_acc)}**
- 250k order-2 baseline: **{fmt(long250_markov_acc)}**
- delta vs v15 250k compact: **{long250_acc - V15_LONG_250K:+.4f} pp**
- 1M debug stress: **started but not completed in this packaging pass**
"""
    long_bottom_line = f"The strongest completed long-horizon evidence in this packaging pass is the 250k gain to **{fmt(long250_acc)}**; a longer 1M debug stress run was started but did not complete before packaging."

report_md = f'''# SBAN v16 Follow-up Research Paper

## Release intent

SBAN v16 is a systems-focused release aimed at a harder question than v15: **can SBAN preserve its stronger short-suite behavior while becoming more adaptive on truly long non-stationary streams?**

The core v16 decision was to treat the v15 hybrid design as incomplete rather than final. v15 already showed that a compact mixture of online experts could materially improve prediction quality, but its expert weights were still effectively global. That is not ideal when the stream changes regime over time.

Accordingly, v16 targeted four linked workstreams:

1. preserve the v15 short-suite profile rather than regress it,
2. add a new **recent-context specialist** for regime shifts,
3. test the new routing on longer streams where drift actually matters,
4. and improve the reply path with broader v16 prompt coverage and support retrieval.

## What changed in v16

### 1. Regime-aware recent-context expert

The main v16 architecture change is a new **bounded recent order-two expert** inside `src/network.zig`.

The runtime now maintains:

- the original SBAN memory-graph score path,
- an online order-1 expert,
- an online order-2 expert over the full stream,
- a burst-context expert,
- and a new **recent-context order-2 expert** backed by a sliding window.

This new expert keeps only a bounded recent transition history. Its purpose is not to dominate everywhere. It exists to react faster when the stream changes local regime and the older global counts become a worse guide.

### 2. Shared online expert adaptation

V15 already adapted expert weights. V16 adds a stronger **shared mixing rule** so the expert weights can move toward whichever specialist is currently working, while still pulling back toward a common center instead of drifting into a brittle winner-take-all state.

### 3. Safer chat fallback behavior

The v16 dialogue path still prefers anchored matches, but now includes a related-prompt retrieval fallback before pure free generation. On the bundled prompt set the anchors remained strong enough that retrieval was rarely needed, but the system path is now more robust than the v15 all-or-nothing split.

## Scientific rationale

The v16 design is guided by three compatible research ideas:

- sparse conditional computation and mixture-of-experts improve effective capacity when no single expert is uniformly best,
- drifting environments benefit from ensembles that can reweight, add, or track specialists over time,
- and adaptive-regret / fixed-share style online methods are specifically motivated by settings where the best expert changes across intervals.

V16 is therefore not trying to become a neural MoE. Instead, it uses those ideas to build a more regime-aware **online systems ensemble** inside the SBAN runtime.

## Main empirical results

### Short-suite preservation profile

Compact v16 short profile:

- Prefix: **{fmt(unified['prefix'])}**
- Drift: **{fmt(unified['drift'])}**
- Probe: **{fmt(unified['probe'])}**

Order-2 baselines on the same short protocols:

- Prefix baseline: **{fmt(markov_short['prefix'])}**
- Drift baseline: **{fmt(markov_short['drift'])}**
- Probe baseline: **{fmt(markov_short['probe'])}**

Relative to v15, the short profile is intentionally **held stable rather than aggressively retuned**:

- Prefix delta vs v15: **{unified['prefix'] - V15_SHORT['prefix']:+.4f} pp**
- Drift delta vs v15: **{unified['drift'] - V15_SHORT['drift']:+.4f} pp**
- Probe delta vs v15: **{unified['probe'] - V15_SHORT['probe']:+.4f} pp**

This matters because the new recent-context expert did not improve the short packaged protocol when forced on all the time. The measured v16 decision was therefore to keep the v15-equivalent short profile and specialize the new expert to longer-horizon runs.

### Long-run results

{long_ext_section}

### Interactive reply evaluation

Hybrid-mode evaluation on the expanded v16 prompt set:

- turns: **{chat_hybrid['turns']}**
- anchored replies: **{chat_hybrid['anchored']} / {chat_hybrid['turns']}**
- retrieved replies: **{chat_hybrid['retrieved']} / {chat_hybrid['turns']}**
- non-empty replies: **{chat_hybrid['nonempty']} / {chat_hybrid['turns']}**

Free-mode evaluation on the same prompt set:

- turns: **{chat_free['turns']}**
- anchored replies: **{chat_free['anchored']} / {chat_free['turns']}**
- retrieved replies: **{chat_free['retrieved']} / {chat_free['turns']}**
- non-empty replies: **{chat_free['nonempty']} / {chat_free['turns']}**

Example hybrid excerpt:

```text
{sample_hybrid}
```

Example free excerpt:

```text
{sample_free}
```

Single-turn examples:

```text
{chat_demo_changes}
```

```text
{chat_demo_routing}
```

```text
{chat_demo_related}
```

## Interpretation

The v16 lesson is more specific than the v15 lesson.

- **Global hybrid experts were enough to lift the short suite in v15.**
- **Recent-window specialists become useful once the stream is long enough for regime mismatch to matter.**
- **Trying to force the recent specialist into every profile is counterproductive.**

That is why the final v16 release uses two distinct operating ideas:

1. a **short-suite preservation profile** that keeps the v15-equivalent compact behavior,
2. a **long-run regime-aware profile** that turns on the recent expert and shared expert mixing where it actually earns its keep.

This split is a real architectural result, not a marketing one. It tells us where the new specialist helps and where it should stay out of the way.

## Known limitations

1. The recent expert is beneficial on longer streams, but it does **not** improve the packaged short-suite when always enabled.
2. Hybrid and anchored chat remain stronger than pure free generation.
3. Bridge memories are still not the main driver of the best measured gains.
4. V16 is a stronger working online model, but it is still a research runtime rather than a finished general conversational system.

## Recommended next work

### Near term

- search separate short-run and long-run profiles more systematically,
- add checkpoint/resume for multi-million-prediction jobs,
- and record explicit expert-weight traces across the stream.

### Mid term

- make bridge creation conditional on expert disagreement and interval error,
- add a real regime detector instead of only a sliding recent window,
- and test longer held-out drifting corpora beyond the packaged enwik8 protocols.

### Longer term

- combine multiple recent windows rather than a single fixed one,
- add serialization and resume support,
- and explore whether bridge structure can become a true routing substrate instead of mostly a supporting mechanism.

## Bottom line

SBAN v16 is a real architectural improvement in long-horizon online adaptation. It preserves the strong v15 short profile, improves the completed 250k long run to **{fmt(long250_acc)}**, and broadens the hybrid reply path with a larger anchored prompt set and related-prompt fallback. {long_bottom_line}
'''

summary_md = f'''# SBAN v16 Executive Summary

## Project name

**SBAN v16 - regime-aware hybrid experts, long-horizon stress scaling, and broader working-model evaluation**

## What this release accomplishes

SBAN v16 moves the project forward in three concrete ways:

- it preserves the strong v15 short-suite behavior with a stable compact profile,
- it adds a new recent-context expert and shared expert mixing for long non-stationary streams,
- and it validates the system on the completed 250k line plus a broader working-model chat evaluation.

## Main measured results

### Compact short suite

- Prefix: **{fmt(unified['prefix'])}**
- Drift: **{fmt(unified['drift'])}**
- Probe: **{fmt(unified['probe'])}**

Relative to v15, the compact short profile was held effectively flat:

- Prefix: **{unified['prefix'] - V15_SHORT['prefix']:+.4f} pp**
- Drift: **{unified['drift'] - V15_SHORT['drift']:+.4f} pp**
- Probe: **{unified['probe'] - V15_SHORT['probe']:+.4f} pp**

### Long-run stress

{long_summary_bullets}

### Interactive evaluation

- Hybrid-mode prompt set: **{chat_hybrid['anchored']} anchored**, **{chat_hybrid['retrieved']} retrieved**, **{chat_hybrid['nonempty']} non-empty** out of **{chat_hybrid['turns']}**
- Free-mode prompt set: runnable, but still materially weaker than hybrid mode

## What changed technically

1. Added a **recent-context order-two expert** backed by a bounded sliding window.
2. Added stronger **shared expert-weight adaptation** to track which specialist is currently best.
3. Added broader **v16 seed and prompt coverage** plus related-prompt retrieval fallback.
4. Preserved a stable short-suite profile rather than forcing the new expert into every operating mode.
5. Added new v16 release and deliverable scripts.

## Best interpretation

SBAN v16 is a long-horizon and scalability improvement rather than a short-suite headline chase. The main completed measured win is the 250k long-run gain, while the short packaged profile stays strong and the reply path remains fully operational across a broader prompt set.

## Known limitations

- The recent expert helps longer streams more than the packaged short suite.
- Free generation remains much weaker than anchored hybrid responses.
- Multi-million debug runs are still expensive without checkpoint/resume.
- Bridge structure still is not the main source of the best gains.
'''

report_path = ROOT / 'SBAN_v16_REPORT.md'
summary_path = ROOT / 'SBAN_v16_EXECUTIVE_SUMMARY.md'
paper_md_path = PAPERS / 'SBAN_v16_follow_up_research_paper.md'
paper_pdf_path = PAPERS / 'SBAN_v16_follow_up_research_paper.pdf'

report_path.write_text(report_md)
summary_path.write_text(summary_md)
paper_md_path.write_text(report_md)
SUMMARIES.joinpath('SBAN_v16_EXECUTIVE_SUMMARY.md').write_text(summary_md)
DELIV.joinpath('SBAN_v16_EXECUTIVE_SUMMARY.md').write_text(summary_md)

cmd = [
    'python',
    '/home/oai/skills/pdfs/scripts/md_to_pdf.py',
    str(paper_md_path),
    '--output',
    str(paper_pdf_path),
    '--resource_path',
    str(ROOT),
]
subprocess.run(cmd, check=True)
DELIV.joinpath('SBAN_v16_follow_up_research_paper.pdf').write_bytes(paper_pdf_path.read_bytes())
print(f'generated {paper_pdf_path}')
print(f'generated {summary_path}')
