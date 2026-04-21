#!/usr/bin/env python3
from __future__ import annotations

import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RESULTS = ROOT / 'docs' / 'results' / 'v13'
PAPERS = ROOT / 'docs' / 'papers'
SUMMARIES = ROOT / 'docs' / 'summaries'
DELIV = ROOT / 'deliverables' / 'v13'
PAPERS.mkdir(parents=True, exist_ok=True)
SUMMARIES.mkdir(parents=True, exist_ok=True)
DELIV.mkdir(parents=True, exist_ok=True)


def load_model(path: Path):
    data = json.loads(path.read_text())
    return data['models'][0], data['models'][1]


def acc(model):
    return 100.0 * model['total_correct'] / model['total_predictions']


def fmt(v: float) -> str:
    return f'{v:.4f}%'


def parse_summary(path: Path):
    text = path.read_text()
    m = re.search(r'summary turns=(\d+) anchored=(\d+) nonempty=(\d+)', text)
    if not m:
        raise ValueError(f'missing summary in {path}')
    return {'turns': int(m.group(1)), 'anchored': int(m.group(2)), 'nonempty': int(m.group(3)), 'text': text}


prefix_u, prefix_markov = load_model(RESULTS / 'unified_prefix_v13_compact.json')
drift_u, drift_markov = load_model(RESULTS / 'unified_drift_v13_compact.json')
probe_u, probe_markov = load_model(RESULTS / 'unified_probe_v13_compact.json')
prefix_f, _ = load_model(RESULTS / 'fixed_prefix_v13_compact.json')
drift_f, _ = load_model(RESULTS / 'fixed_drift_v13_compact.json')
probe_f, _ = load_model(RESULTS / 'fixed_probe_v13_compact.json')
drift_best, _ = load_model(RESULTS / 'best_drift_v13_profile.json')
long250_compact, long250_markov = load_model(RESULTS / 'longrun_compact_v13_250k.json')
long250_hard, _ = load_model(RESULTS / 'longrun_hardened_v13_250k.json')
long1m_compact, long1m_markov = load_model(RESULTS / 'longrun_compact_v13_1m.json')
long1m_hard, _ = load_model(RESULTS / 'longrun_hardened_v13_1m.json')
chat_anchor = parse_summary(RESULTS / 'chat_eval_anchor.txt')
chat_free = parse_summary(RESULTS / 'chat_eval_free.txt')
chat_demo_hello = (RESULTS / 'chat_demo_hello.txt').read_text().strip()
chat_demo_limits = (RESULTS / 'chat_demo_limits.txt').read_text().strip()

unified = {'prefix': acc(prefix_u), 'drift': acc(drift_u), 'probe': acc(probe_u)}
fixed = {'prefix': acc(prefix_f), 'drift': acc(drift_f), 'probe': acc(probe_f)}
best = {'prefix': acc(prefix_u), 'drift': acc(drift_best), 'probe': acc(probe_u)}

vs_fixed = {k: unified[k] - fixed[k] for k in unified}
long250_compact_acc = acc(long250_compact)
long250_hard_acc = acc(long250_hard)
long250_markov_acc = acc(long250_markov)
long1m_compact_acc = acc(long1m_compact)
long1m_hard_acc = acc(long1m_hard)
long1m_markov_acc = acc(long1m_markov)

sample_anchor = '\n'.join(chat_anchor['text'].splitlines()[:12])
sample_free = '\n'.join(chat_free['text'].splitlines()[:12])

report_md = f'''# SBAN v13 Report

## Release intent

SBAN v13 pushes the post-v12 line in a more practical direction. The work focused on three connected goals:

1. **keep the strong compact elastic maintained-suite operating point alive**,  
2. **run a genuinely longer stress exposure at one million predictions**, and  
3. **replace the weak free-form reply path with a more coherent request-response subsystem**.

The result is not a headline short-suite breakthrough. It is a **harder, more honest, more operational** SBAN release.

## What changed in v13

### 1. Carry-quality scoring

Carry selection now includes an explicit **win-loss quality term**. This is a small architectural change, but it makes the carry set less indifferent to memories that have recently been wrong too often.

### 2. Prompt-anchor dialogue subsystem

The old byte-generation demo could run, but it tended to collapse into repetitive fragments under a range of prompts. v13 adds a **prompt-anchor dialogue adapter**:

- parse a dialogue seed corpus into user/assistant pairs,
- score the nearest prompt anchor by lexical overlap,
- answer through the matched response when the anchor is confident,
- fall back to free byte-generation only when no anchor is found.

This is a pragmatic systems fix. It makes the runtime more usable as a real working demo without pretending that open-ended byte-generation alone is already a full conversational model.

### 3. Multi-prompt chat evaluation

The repo now includes a dedicated prompt set and a `chat-eval` command. That gives the runtime a repeatable way to test coherence over a range of questions instead of a single smoke prompt.

### 4. Very-long-run stress harness

v13 adds a **1,000,000-prediction prefix stress run** on top of the earlier 250k run. This is the first release in the current line that directly shows what happens when the system is pushed much farther into sustained exposure.

## Main v13 results

### Maintained short target suite

Unified compact profile:

- Prefix: **{fmt(unified['prefix'])}**
- Drift: **{fmt(unified['drift'])}**
- Probe: **{fmt(unified['probe'])}**

Best specialized profile in this release layer:

- Drift: **{fmt(best['drift'])}**

### Unified compact profile versus matched fixed-capacity comparator

- Prefix delta: **{vs_fixed['prefix']:+.4f} pp**
- Drift delta: **{vs_fixed['drift']:+.4f} pp**
- Probe delta: **{vs_fixed['probe']:+.4f} pp**

The maintained short suite therefore stays at the strong v12 level rather than materially moving beyond it.

### Long-run results

| Protocol | Compact elastic | Hardened long-run | Order-2 baseline | Hardened delta vs compact |
|---|---:|---:|---:|---:|
| 250k prefix stress | {fmt(long250_compact_acc)} | {fmt(long250_hard_acc)} | {fmt(long250_markov_acc)} | {long250_hard_acc - long250_compact_acc:+.4f} pp |
| 1M prefix stress | {fmt(long1m_compact_acc)} | {fmt(long1m_hard_acc)} | {fmt(long1m_markov_acc)} | {long1m_hard_acc - long1m_compact_acc:+.4f} pp |

On both long-horizon runs, the **fixed-capacity long-term-enabled hardened profile** stays ahead of the compact short-suite profile. The gains are modest, but they are real:

- **+{(long250_hard_acc - long250_compact_acc):.4f} pp** on 250k
- **+{(long1m_hard_acc - long1m_compact_acc):.4f} pp** on 1M

At the same time, the 1M result makes the real limitation impossible to hide: SBAN still trails the order-2 baseline badly on very long exposure.

### Interactive reply evaluation

Anchor-mode chat evaluation:

- turns: **{chat_anchor['turns']}**
- anchored matches: **{chat_anchor['anchored']}**
- non-empty replies: **{chat_anchor['nonempty']}**

Free-mode chat evaluation:

- turns: **{chat_free['turns']}**
- anchored matches: **{chat_free['anchored']}**
- non-empty replies: **{chat_free['nonempty']}**

What matters is the qualitative gap. The old free mode still degenerates into repeated fragments such as `You are you ok`, while the new anchor mode answers the full prompt set coherently.

Example anchor-mode excerpt:

```text
{sample_anchor}
```

Example free-mode excerpt:

```text
{sample_free}
```

Bundled single-turn demo outputs:

```text
{chat_demo_hello}
```

```text
{chat_demo_limits}
```

## Operational interpretation

v13 should be read as a **systems-hardening and usability release**.

The short benchmark story is nearly unchanged from v12. The meaningful improvement is elsewhere:

- the runtime now has a repeatable **multi-prompt reply evaluation**,
- the interactive path is **coherent across a range of requests** instead of collapsing to one generic answer,
- and the release includes a real **1M-prediction stress result** rather than stopping at 250k.

That is important because it makes SBAN more credible as a working experimental system even without a new short-suite headline.

## Known limitations

1. v13 does **not materially improve the maintained short suite over v12**.  
2. The 1M long-run result still stays far below the order-2 baseline.  
3. The interactive improvement comes from a **retrieval-assisted prompt-anchor layer**, not from a solved open-ended generative dialogue model.  
4. Bridge-heavy multi-region behavior is still not the main source of gain.  
5. The strongest current claims remain about runtime control, hardening, and usability rather than about reaching the architecture ceiling of SBAN.

## Recommended next work after v13

1. Add **checkpoint export and resume** so very long runs can be staged instead of always replayed from scratch.  
2. Expand the dialogue corpus and evaluate the reply subsystem with held-out prompts rather than only anchored in-domain questions.  
3. Search long-run profiles more aggressively, especially around long-term quality gates and memory budget schedules.  
4. Re-run the best compact and hardened profiles on the full original publication protocol.  
5. Revisit richer regional hierarchy only after a workload clearly shows it paying for itself.

## Bottom line

SBAN v13 proves something more operational than v12 did: the architecture can now be pushed through a **real million-prediction stress run** and can answer a **range of user-style requests coherently** through a reproducible, built-in subsystem. That is a serious usability gain. But the release also makes the central limitation clearer: SBAN still needs a much stronger long-horizon strategy before it can claim to be a genuinely competitive long-stream learner.
'''

summary_md = f'''# SBAN v13 Executive Summary

## Project name

**SBAN v13 - very-long-run hardening and anchored interactive runtime release**

## Project goal

Push SBAN further toward a **real working experimental system** by doing three things at the same time:

- preserve the best compact elastic maintained-suite operating point,
- validate a much longer **1,000,000-prediction** stream exposure,
- and replace the weak free-form reply loop with a more coherent request-response subsystem.

## Current status

SBAN v13 is a working Zig release that:

- builds reproducibly from the uploaded Zig tarball,
- keeps the strongest compact maintained-suite profile alive,
- adds a dedicated **prompt-anchor dialogue subsystem** and multi-prompt chat evaluation,
- includes both **250k** and **1M** long-run stress results,
- and makes the runtime more usable as a real model demo while staying honest about its limits.

## Main empirical findings

### Maintained short target suite

Unified compact profile:

- Prefix: **{fmt(unified['prefix'])}**
- Drift: **{fmt(unified['drift'])}**
- Probe: **{fmt(unified['probe'])}**

Best specialized result in this release layer:

- Drift: **{fmt(best['drift'])}**

### Very-long-run stress results

250k prefix stress:

- compact elastic: **{fmt(long250_compact_acc)}**
- hardened long-run: **{fmt(long250_hard_acc)}**
- order-2 baseline: **{fmt(long250_markov_acc)}**

1M prefix stress:

- compact elastic: **{fmt(long1m_compact_acc)}**
- hardened long-run: **{fmt(long1m_hard_acc)}**
- order-2 baseline: **{fmt(long1m_markov_acc)}**

The hardened profile beats the compact profile by **+{(long250_hard_acc - long250_compact_acc):.4f} pp** on 250k and **+{(long1m_hard_acc - long1m_compact_acc):.4f} pp** on 1M, but SBAN still remains well below order-2 on the 1M run.

### Interactive response results

Anchor-mode evaluation on the bundled prompt set:

- turns: **{chat_anchor['turns']}**
- coherent anchored replies: **{chat_anchor['anchored']} / {chat_anchor['turns']}**
- non-empty replies: **{chat_anchor['nonempty']} / {chat_anchor['turns']}**

The free-generation mode still collapses into repetitive fragments, while the anchored mode answers the full evaluation set coherently.

## What changed in the architecture

1. **Carry-quality scoring** now uses recent win-loss balance when refreshing carry memories.  
2. **Prompt-anchor dialogue matching** gives SBAN a more coherent interactive subsystem.  
3. **Multi-prompt chat evaluation** makes response quality testable instead of anecdotal.  
4. **1M-run stress harness** pushes the runtime much farther than the earlier 250k release.

## What the current system demonstrates

1. **Real reproducible execution** with the uploaded Zig binary.  
2. **Stable maintained-suite behavior** at the strong v12 level.  
3. **Very-long-run stress evidence** through a million-prediction release run.  
4. **Coherent short replies over a range of prompts** through a built-in anchored dialogue subsystem.

## Important limitations

1. v13 does **not materially improve the maintained short suite over v12**.  
2. The 1M long-run profile is still **far below** order-2.  
3. The interactive gain is **retrieval-assisted**, not proof of a solved generative conversational model.  
4. Bridge-heavy regional structure is still not the dominant source of gain.  
5. The architecture still needs a stronger long-horizon learning strategy.

## Highest-value next steps

### Near term

- Add checkpoint/resume for very long runs.  
- Expand the dialogue corpus and evaluate held-out prompts.  
- Search long-run profiles more aggressively around long-term quality controls.

### Mid term

- Re-run the best profiles on the full original publication protocol.  
- Add more realistic interactive workloads beyond anchored short replies.  
- Revisit richer regional hierarchy only after longer workloads justify it.

## Bottom line

SBAN v13 is best understood as a **serious hardening and usability release**. It proves that the runtime can survive a much longer stream exposure and can answer a range of short requests coherently through a reproducible built-in subsystem. The system is more real and more usable than the earlier line, but it is still not a finished long-horizon learning architecture.
'''

report_path = ROOT / 'SBAN_v13_REPORT.md'
summary_path = ROOT / 'SBAN_v13_EXECUTIVE_SUMMARY.md'
paper_md_path = PAPERS / 'SBAN_v13_follow_up_research_paper.md'
paper_pdf_path = PAPERS / 'SBAN_v13_follow_up_research_paper.pdf'

report_path.write_text(report_md)
summary_path.write_text(summary_md)
paper_md_path.write_text(report_md)
SUMMARIES.joinpath('SBAN_v13_EXECUTIVE_SUMMARY.md').write_text(summary_md)
DELIV.joinpath('SBAN_v13_EXECUTIVE_SUMMARY.md').write_text(summary_md)

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
DELIV.joinpath('SBAN_v13_follow_up_research_paper.pdf').write_bytes(paper_pdf_path.read_bytes())
print(f'generated {paper_pdf_path}')
print(f'generated {summary_path}')
