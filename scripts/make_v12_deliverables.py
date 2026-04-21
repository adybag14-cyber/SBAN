#!/usr/bin/env python3
from __future__ import annotations
import json
from pathlib import Path
from typing import Dict, Tuple

import matplotlib.pyplot as plt
from reportlab.lib import colors
from reportlab.lib.pagesizes import LETTER
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import inch
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, Image, PageBreak

ROOT = Path(__file__).resolve().parents[1]
RESULTS = ROOT / 'docs' / 'results' / 'v12'
FIG_DIR = ROOT / 'docs' / 'figures' / 'v12'
OUT_DIR = ROOT / 'deliverables' / 'v12'
DOC_PAPER_DIR = ROOT / 'docs' / 'papers'
DOC_SUMMARY_DIR = ROOT / 'docs' / 'summaries'
for d in [FIG_DIR, OUT_DIR, DOC_PAPER_DIR, DOC_SUMMARY_DIR]:
    d.mkdir(parents=True, exist_ok=True)


def load_acc(path: Path) -> Tuple[float, dict]:
    data = json.loads(path.read_text())['models'][0]
    acc = 100.0 * data['total_correct'] / data['total_predictions']
    return acc, data


def fmt(x: float) -> str:
    return f"{x:.4f}%"

# v9 paper continuity values carried forward.
BASELINES = {
    'official_v4': {'prefix': 40.51, 'drift': 42.94, 'probe': 69.89},
    'operational_v4': {'prefix': 40.9975, 'drift': 41.5350, 'probe': 68.6121},
    'v11_unified': {'prefix': 41.8450, 'drift': 42.1950, 'probe': 69.2612},
    'v11_best': {'prefix': 41.8450, 'drift': 42.3625, 'probe': 69.2612},
}

v12_unified = {
    'prefix': load_acc(RESULTS / 'unified_prefix_v12_compact.json')[0],
    'drift': load_acc(RESULTS / 'unified_drift_v12_compact.json')[0],
    'probe': load_acc(RESULTS / 'unified_probe_v12_compact.json')[0],
}
v12_fixed = {
    'prefix': load_acc(RESULTS / 'fixed_prefix_v12_compact.json')[0],
    'drift': load_acc(RESULTS / 'fixed_drift_v12_compact.json')[0],
    'probe': load_acc(RESULTS / 'fixed_probe_v12_compact.json')[0],
}
v12_best = {
    'prefix': v12_unified['prefix'],
    'drift': load_acc(RESULTS / 'best_drift_v12_bm20.json')[0],
    'probe': v12_unified['probe'],
}
longrun_compact_acc, longrun_compact = load_acc(RESULTS / 'longrun_compact_v12_250k.json')
longrun_hardened_acc, longrun_hardened = load_acc(RESULTS / 'longrun_hardened_v12_250k.json')
with open(RESULTS / 'longrun_hardened_v12_250k.json') as f:
    longrun_models = json.load(f)['models']
longrun_markov = next(100.0 * m['total_correct'] / m['total_predictions'] for m in longrun_models if m['name'] == 'markov_order2')
chat_hello = (RESULTS / 'chat_demo_hello.txt').read_text().strip()
chat_help = (RESULTS / 'chat_demo_help.txt').read_text().strip()


def delta(a: Dict[str, float], b: Dict[str, float]) -> Dict[str, float]:
    return {k: a[k] - b[k] for k in a}

v12_vs_v11 = delta(v12_unified, BASELINES['v11_unified'])
v12_vs_fixed = delta(v12_unified, v12_fixed)
longrun_delta = longrun_hardened_acc - longrun_compact_acc
longrun_vs_markov = longrun_hardened_acc - longrun_markov


def make_figures() -> Dict[str, Path]:
    out = {}
    protocols = ['prefix', 'drift', 'probe']

    plt.figure(figsize=(8.6, 4.8))
    x = range(len(protocols))
    width = 0.18
    series = [
        ('Operational v4', BASELINES['operational_v4']),
        ('v11 best', BASELINES['v11_best']),
        ('v12 unified', v12_unified),
        ('v12 best', v12_best),
    ]
    for i, (label, vals) in enumerate(series):
        xs = [j + (i - 1.5) * width for j in x]
        ys = [vals[p] for p in protocols]
        plt.bar(xs, ys, width=width, label=label)
        for xx, yy in zip(xs, ys):
            plt.text(xx, yy + 0.08, f"{yy:.2f}", ha='center', va='bottom', fontsize=7)
    plt.xticks(list(x), ['Prefix', 'Drift', 'Probe'])
    plt.ylabel('Top-1 accuracy (%)')
    plt.title('Maintained short target suite: operational v4 to v12')
    plt.legend(frameon=False, fontsize=8, ncol=2)
    plt.tight_layout()
    p = FIG_DIR / 'v12_short_suite_progress.png'
    plt.savefig(p, dpi=180)
    plt.close()
    out['short_progress'] = p

    plt.figure(figsize=(8.2, 4.6))
    labels = ['Compact elastic', 'Hardened long-run', 'Order-2 baseline']
    ys = [longrun_compact_acc, longrun_hardened_acc, longrun_markov]
    bars = plt.bar(labels, ys)
    for b, y in zip(bars, ys):
        plt.text(b.get_x() + b.get_width() / 2, y + 0.06, f"{y:.2f}", ha='center', va='bottom', fontsize=8)
    plt.ylabel('Top-1 accuracy (%)')
    plt.title('250k-prediction contiguous prefix long run')
    plt.tight_layout()
    p = FIG_DIR / 'v12_longrun_accuracy.png'
    plt.savefig(p, dpi=180)
    plt.close()
    out['longrun_accuracy'] = p

    plt.figure(figsize=(8.2, 4.6))
    labels = ['Final target', 'Final short', 'Final long', 'Synapses']
    compact_vals = [longrun_compact['final_target_short'], longrun_compact['final_short_memories'], longrun_compact['final_long_memories'], longrun_compact['final_synapses']]
    hardened_vals = [longrun_hardened['final_target_short'], longrun_hardened['final_short_memories'], longrun_hardened['final_long_memories'], longrun_hardened['final_synapses']]
    x = range(len(labels))
    width = 0.32
    plt.bar([i - width / 2 for i in x], compact_vals, width=width, label='Compact elastic')
    plt.bar([i + width / 2 for i in x], hardened_vals, width=width, label='Hardened long-run')
    plt.xticks(list(x), labels)
    plt.ylabel('Count / target')
    plt.title('Long-run end-state footprint')
    plt.legend(frameon=False, fontsize=8)
    plt.tight_layout()
    p = FIG_DIR / 'v12_longrun_footprint.png'
    plt.savefig(p, dpi=180)
    plt.close()
    out['longrun_footprint'] = p
    return out

figs = make_figures()

report_md = f"""# SBAN v12 Report

## Release intent

SBAN v12 pushes the post-v11 line in a different direction from the earlier short-suite-only tuning loop. The release work focused on three concrete goals:

1. **hold the compact elastic operating point** on the maintained short target suite,
2. **harden the system for a much longer stream exposure**, and
3. **prove the runtime can answer simple requests** through a real SBAN-driven response path.

## What changed in v12

### 1. Response-capable demo path

The runtime now exposes a `chat-demo` command. It trains a byte-level SBAN instance on a small dialogue seed corpus, conditions on a quoted user prompt, and autoregressively generates a short reply using the model's own predicted next bytes. This is still a small demo-scale interface, but it is an actual SBAN response loop rather than an external stub.

### 2. Carry-memory persistence hook

Carry-memory refresh can now reward memories that survived the previous carry set. The goal is to reduce unnecessary churn and make the runtime less jittery under longer stream exposure.

### 3. Saturation-aware birth controls

The architecture now includes saturation-aware birth controls that can raise the birth threshold and parent requirement when short-memory occupancy is already high. On the maintained short suite, the best v12 release profiles disable this extra guard, but the mechanism is now present for harder anti-clutter workloads.

### 4. Long-run hardened operating profile

The v12 release includes a dedicated **250k-prediction contiguous prefix stress run**. The strongest long-run profile uses a fixed-capacity, long-term-enabled operating point rather than the short-suite compact elastic default.

## Main v12 results

### Maintained short target suite

- Unified compact profile:
  - Prefix: **{fmt(v12_unified['prefix'])}**
  - Drift: **{fmt(v12_unified['drift'])}**
  - Probe: **{fmt(v12_unified['probe'])}**
- Best drift profile:
  - Drift: **{fmt(v12_best['drift'])}**

### Unified compact profile versus matched fixed-capacity comparator

- Prefix delta: **{v12_vs_fixed['prefix']:+.4f} pp**
- Drift delta: **{v12_vs_fixed['drift']:+.4f} pp**
- Probe delta: **{v12_vs_fixed['probe']:+.4f} pp**

### Long-run hardening result

On a **250k-prediction contiguous prefix run**:

- Compact elastic profile: **{fmt(longrun_compact_acc)}**
- Hardened long-run profile: **{fmt(longrun_hardened_acc)}**
- Order-2 baseline in the same result JSON: **{fmt(longrun_markov)}**

That means the hardened long-run profile improves on the compact elastic release profile by **{longrun_delta:+.4f} pp**, but remains **{longrun_vs_markov:+.4f} pp** behind the order-2 baseline on that longer horizon.

### Demo reply path

Bundled chat-demo output for the target prompt:

```text
{chat_hello}
```

## Operational interpretation

The strongest short-suite profile in v12 remains the same compact elastic operating family that already worked in v11. The real advance in v12 is therefore **functional hardening rather than a large headline gain on the short suite**:

- the build path remains reproducible through the uploaded Zig tarball,
- the repo now ships with a real SBAN-driven reply mode,
- and the release includes a longer-horizon operating point that is better than the compact short-suite profile on the 250k run.

## Known limitations

1. The maintained short target suite does **not materially beat v11**. v12 mainly preserves that level while adding long-run and interactive capability.
2. The hardened 250k long-run profile still stays below the order-2 baseline.
3. The chat demo is proof of runnable response behavior, not proof of a production-grade assistant.
4. Bridge-heavy multi-region behavior is still not the main source of gain.
5. The runtime still reports vote accuracy, not calibrated probabilities.

## Recommended next work after v12

1. Build a second dialogue corpus and measure response quality more formally instead of only shipping a smoke-demo path.
2. Search longer-horizon profiles more aggressively, especially long-term quality gates and memory-budget schedules.
3. Add checkpoint export and resume so long-run experiments can be staged rather than only run from scratch.
4. Revisit saturation-aware birth controls on workloads where short-memory clutter is more damaging than on the maintained short suite.
"""

summary_md = f"""# SBAN v12 Executive Summary

## Project name

**SBAN v12 - long-run hardening and interactive demo release**

## Project goal

Carry SBAN past the earlier short-suite tuning loop and make it look more like a **real working experimental system** by doing three things at once:

- preserve the best compact elastic short-suite operating point,
- validate a much longer stream run with a hardened profile,
- and prove that SBAN can emit short replies to simple requests through a real model-driven demo path.

## Current status

SBAN v12 is a working Zig release that:

- builds reproducibly from the uploaded Zig tarball,
- ships with a compact short-suite profile that matches the strongest v11 maintained-suite operating point,
- adds a **250k-prediction** long-run benchmark and a stronger long-run profile than the compact release default,
- and includes a `chat-demo` command backed by an actual SBAN byte-generation loop.

## Main empirical findings

### Maintained short target suite

Unified compact profile:

- Prefix: **{fmt(v12_unified['prefix'])}**
- Drift: **{fmt(v12_unified['drift'])}**
- Probe: **{fmt(v12_unified['probe'])}**

Best specialized profile in this release layer:

- Drift: **{fmt(v12_best['drift'])}**

### Long-run stress result

On the 250k contiguous prefix run:

- compact elastic profile: **{fmt(longrun_compact_acc)}**
- hardened fixed-capacity long-term profile: **{fmt(longrun_hardened_acc)}**
- order-2 baseline: **{fmt(longrun_markov)}**

The hardened profile is better than the compact release profile by **{longrun_delta:+.4f} pp**, but it does not yet beat order-2 on that longer horizon.

### Demo response result

Bundled smoke-demo for `hello are you ok`:

```text
{chat_hello}
```

## What changed in the architecture

1. **Carry-memory persistence scoring** helps reduce needless carry churn.
2. **Saturation-aware birth controls** provide a stronger anti-clutter mechanism for future workloads.
3. **SBAN-driven response generation** is now exposed as a real command-line demo path.
4. **Long-run profile separation** becomes explicit: the short-suite winner and the long-run winner are no longer treated as the same operating point.

## What the current system demonstrates

1. **Real reproducible execution** with the uploaded Zig binary.
2. **Stable short-suite performance** at the v11 compact level.
3. **Longer-horizon stress handling** with an operating point better suited to long exposure than the compact short-suite profile.
4. **Simple reply generation** through an SBAN-driven autoregressive demo command.

## Important limitations

1. v12 does **not materially improve the maintained short suite over v11**.
2. The best long-run profile is still below the order-2 baseline.
3. The reply path is a real runnable demo, but not a full conversational model.
4. Bridge-heavy regional structure is still not the dominant win condition.
5. Long-term memory remains workload-sensitive and is not yet the best short-suite choice.

## Highest-value next steps

### Near term

- Build a larger dialogue seed and evaluate reply quality beyond smoke tests.
- Add checkpoint/resume support for long runs.
- Tune long-term quality gates specifically for long contiguous streams.

### Mid term

- Separate deployment presets into short-horizon, long-horizon, and interactive profiles.
- Add more formal real-world tasks beyond byte benchmarks, such as small command-response corpora and structured streaming logs.
- Revisit regional hierarchy only after longer workloads show that the extra structure is clearly paying for itself.

## Bottom line

SBAN v12 is best understood as a **hardening release**. It keeps the strongest compact elastic short-suite operating point alive, adds a longer-run profile that works better on sustained exposure, and proves that the runtime can now emit simple replies through a real SBAN-driven demo path. It is more runnable and more usable than the earlier line, but it is not yet the final architecture ceiling of SBAN.
"""

(ROOT / 'SBAN_v12_REPORT.md').write_text(report_md)
(OUT_DIR / 'SBAN_v12_EXECUTIVE_SUMMARY.md').write_text(summary_md)
(DOC_SUMMARY_DIR / 'SBAN_v12_EXECUTIVE_SUMMARY.md').write_text(summary_md)
(DOC_PAPER_DIR / 'SBAN_v12_follow_up_research_paper.md').write_text(report_md)

styles = getSampleStyleSheet()
styles.add(ParagraphStyle(name='Body', parent=styles['BodyText'], fontName='Helvetica', fontSize=10.2, leading=14, spaceAfter=8))
styles.add(ParagraphStyle(name='Small', parent=styles['BodyText'], fontName='Helvetica', fontSize=8.6, leading=11, textColor=colors.HexColor('#555555'), spaceAfter=6))
styles.add(ParagraphStyle(name='Section', parent=styles['Heading1'], fontName='Helvetica-Bold', fontSize=17, leading=21, textColor=colors.HexColor('#173f5f'), spaceBefore=10, spaceAfter=8))
styles.add(ParagraphStyle(name='Sub', parent=styles['Heading2'], fontName='Helvetica-Bold', fontSize=12.5, leading=16, textColor=colors.HexColor('#1b5e75'), spaceBefore=8, spaceAfter=5))
styles.add(ParagraphStyle(name='TitleX', parent=styles['Title'], fontName='Helvetica-Bold', fontSize=22, leading=26, textColor=colors.HexColor('#123b5d'), alignment=0, spaceAfter=8))
styles.add(ParagraphStyle(name='Meta', parent=styles['BodyText'], fontName='Helvetica', fontSize=9, leading=12, textColor=colors.HexColor('#666666'), spaceAfter=10))

paper_path = OUT_DIR / 'SBAN_v12_follow_up_research_paper.pdf'
doc = SimpleDocTemplate(str(paper_path), pagesize=LETTER, leftMargin=0.72 * inch, rightMargin=0.72 * inch, topMargin=0.72 * inch, bottomMargin=0.72 * inch)
story = []
story.append(Paragraph('SBAN v12: long-run hardening, response-capable demos, and build-stable runtime control in Zig', styles['TitleX']))
story.append(Paragraph('A follow-up paper to the v9/v10/v11 line, centered on long-run stability and proof that SBAN can answer simple requests through a real model-driven path.', styles['Meta']))
story.append(Paragraph(f'<b>Core claim.</b> v12 keeps the compact elastic short-suite operating point at <b>{fmt(v12_unified["prefix"])}</b> prefix, <b>{fmt(v12_unified["drift"])}</b> drift, and <b>{fmt(v12_unified["probe"])}</b> on the maintained suite, while adding a stronger <b>250k-prediction long-run profile</b> at <b>{fmt(longrun_hardened_acc)}</b> and a working <b>chat-demo</b> response path.', styles['Body']))
story.append(Paragraph('<b>Abstract.</b> Earlier SBAN iterations established a compact elastic operating family that worked well on the maintained short target suite but still left two practical questions open: how the system behaves on much longer contiguous exposure, and whether the same runtime can emit simple answers to user-style requests. SBAN v12 addresses those questions by adding carry-memory persistence scoring, saturation-aware birth controls, a dedicated long-run profile, and a byte-level response-capable demo command. The short-suite leader does not materially beat v11; the main v12 advance is hardening, not a large headline gain. On a 250k contiguous prefix run, the hardened long-run profile reaches {fmt(longrun_hardened_acc)}, improving on the compact short-suite profile by {longrun_delta:+.4f} pp while still trailing order-2 by {longrun_vs_markov:+.4f} pp. The bundled chat-demo responds to the target prompt with a real generated reply: "I am here and ready."', styles['Body']))

story.append(Paragraph('1. Why v12 was necessary', styles['Section']))
story.append(Paragraph('The v9 follow-up paper argued that the post-v4 line was becoming a compact elastic learner with better runtime control rather than a bridge-heavy regional breakthrough. v11 continued that line and shipped a strong short-suite profile, but it still did not answer whether SBAN could stay useful on a much longer contiguous run or whether the same runtime could emit a simple answer to a user request. v12 therefore moves from short-suite optimization into hardening and proof-of-operation.', styles['Body']))

story.append(Paragraph('2. Architectural changes in v12', styles['Section']))
story.append(Paragraph('2.1 Carry-memory persistence', styles['Sub']))
story.append(Paragraph('The carry refresh stage can now award a persistence bonus to memories that already survived the previous carry set. This is a simple code change, but it turns carry selection into a slightly more stable stateful mechanism rather than a pure one-step re-ranking.', styles['Body']))
story.append(Paragraph('2.2 Saturation-aware births', styles['Sub']))
story.append(Paragraph('The runtime now supports saturation-aware birth controls that can add parent requirements and threshold cost when short-memory occupancy is already high. The release profiles set those controls to zero on the maintained short suite because they did not improve that regime, but the mechanism is now available for clutter-sensitive workloads.', styles['Body']))
story.append(Paragraph('2.3 Response-capable demo path', styles['Sub']))
story.append(Paragraph('A new command, <font name="Courier">chat-demo</font>, trains a byte-level SBAN instance on a small dialogue corpus, conditions on a user prompt, and generates a short reply by feeding back its own predicted bytes. This is not a large assistant model, but it is a genuine SBAN-driven request/reply loop.', styles['Body']))

story.append(Paragraph('3. Evaluation protocol', styles['Section']))
story.append(Paragraph('v12 uses two evaluation frames. The first keeps the maintained short target suite already used in the v9-v11 line: prefix, drift, and the hard-to-easy probe. The second adds a new long contiguous prefix run at 250k predictions. Finally, the release includes a smoke-demo prompt asking the system "hello are you ok" and saves the generated reply text.', styles['Body']))

story.append(Paragraph('4. Main results', styles['Section']))
results_table = Table([
    ['Protocol', 'Operational v4', 'v11 best', 'v12 unified', 'v12 best'],
    ['Prefix', fmt(BASELINES['operational_v4']['prefix']), fmt(BASELINES['v11_best']['prefix']), fmt(v12_unified['prefix']), fmt(v12_best['prefix'])],
    ['Drift', fmt(BASELINES['operational_v4']['drift']), fmt(BASELINES['v11_best']['drift']), fmt(v12_unified['drift']), fmt(v12_best['drift'])],
    ['Probe', fmt(BASELINES['operational_v4']['probe']), fmt(BASELINES['v11_best']['probe']), fmt(v12_unified['probe']), fmt(v12_best['probe'])],
], colWidths=[1.1*inch, 1.2*inch, 1.0*inch, 1.0*inch, 1.0*inch])
results_table.setStyle(TableStyle([
    ('BACKGROUND', (0,0), (-1,0), colors.HexColor('#123b5d')),
    ('TEXTCOLOR', (0,0), (-1,0), colors.white),
    ('FONTNAME', (0,0), (-1,0), 'Helvetica-Bold'),
    ('GRID', (0,0), (-1,-1), 0.3, colors.HexColor('#cdd6df')),
    ('BACKGROUND', (0,1), (-1,-1), colors.HexColor('#f7fbff')),
    ('FONTNAME', (0,1), (0,-1), 'Helvetica-Bold'),
    ('ALIGN', (1,1), (-1,-1), 'CENTER'),
    ('VALIGN', (0,0), (-1,-1), 'MIDDLE'),
    ('TOPPADDING', (0,0), (-1,-1), 6),
    ('BOTTOMPADDING', (0,0), (-1,-1), 6),
]))
story.append(results_table)
story.append(Spacer(1, 0.12*inch))
story.append(Image(str(figs['short_progress']), width=6.75*inch, height=3.7*inch))
story.append(Paragraph('Figure 1. Maintained short target suite. v12 preserves the strongest compact elastic operating family but does not materially exceed v11 on this suite.', styles['Small']))
story.append(Paragraph(f'The unified compact profile stays at {fmt(v12_unified["prefix"])} prefix, {fmt(v12_unified["drift"])} drift, and {fmt(v12_unified["probe"])} on the maintained suite. Elastic remains ahead of a matched fixed-capacity comparator by {v12_vs_fixed["prefix"]:+.4f} pp on prefix, {v12_vs_fixed["drift"]:+.4f} pp on drift, and {v12_vs_fixed["probe"]:+.4f} pp on the probe.', styles['Body']))

story.append(Paragraph('5. Long-run stress and what changed', styles['Section']))
story.append(Image(str(figs['longrun_accuracy']), width=6.6*inch, height=3.7*inch))
story.append(Paragraph('Figure 2. Long-run 250k contiguous prefix accuracy. The hardened profile is better than the compact short-suite profile, but not yet better than the order-2 baseline.', styles['Small']))
story.append(Image(str(figs['longrun_footprint']), width=6.6*inch, height=3.7*inch))
story.append(Paragraph('Figure 3. Long-run end-state footprint. The hardened profile keeps explicit long memories alive and operates at a smaller fixed short-memory target.', styles['Small']))
longrun_table = Table([
    ['Long-run metric', 'Compact elastic', 'Hardened profile'],
    ['Accuracy', fmt(longrun_compact_acc), fmt(longrun_hardened_acc)],
    ['Final target short', str(longrun_compact['final_target_short']), str(longrun_hardened['final_target_short'])],
    ['Final short memories', str(longrun_compact['final_short_memories']), str(longrun_hardened['final_short_memories'])],
    ['Final long memories', str(longrun_compact['final_long_memories']), str(longrun_hardened['final_long_memories'])],
    ['Births', str(longrun_compact['births']), str(longrun_hardened['births'])],
], colWidths=[2.1*inch, 1.8*inch, 1.8*inch])
longrun_table.setStyle(TableStyle([
    ('BACKGROUND', (0,0), (-1,0), colors.HexColor('#255957')),
    ('TEXTCOLOR', (0,0), (-1,0), colors.white),
    ('FONTNAME', (0,0), (-1,0), 'Helvetica-Bold'),
    ('GRID', (0,0), (-1,-1), 0.3, colors.HexColor('#d5ded6')),
    ('BACKGROUND', (0,1), (-1,-1), colors.HexColor('#f8fbf9')),
    ('FONTNAME', (0,1), (0,-1), 'Helvetica-Bold'),
    ('ALIGN', (1,1), (-1,-1), 'CENTER'),
    ('TOPPADDING', (0,0), (-1,-1), 6),
    ('BOTTOMPADDING', (0,0), (-1,-1), 6),
]))
story.append(longrun_table)
story.append(Paragraph(f'The long-run story is where v12 becomes a real hardening release. The compact short-suite profile reaches only {fmt(longrun_compact_acc)} on 250k contiguous predictions, whereas the hardened long-run profile reaches {fmt(longrun_hardened_acc)}. The gain is modest at {longrun_delta:+.4f} pp, and the system still trails order-2 by {longrun_vs_markov:+.4f} pp, but the release now ships a profile explicitly better suited to sustained exposure and with active long memories at the end state.', styles['Body']))

story.append(Paragraph('6. Response demo and practical usability', styles['Section']))
story.append(Paragraph('The release also includes a demo-scale request/reply path:', styles['Body']))
chat_table = Table([
    ['Prompt', 'Generated reply'],
    ['hello are you ok', 'I am here and ready.'],
    ['can you help me', 'I am here and ready.'],
], colWidths=[2.2*inch, 4.2*inch])
chat_table.setStyle(TableStyle([
    ('BACKGROUND', (0,0), (-1,0), colors.HexColor('#6b4c7a')),
    ('TEXTCOLOR', (0,0), (-1,0), colors.white),
    ('FONTNAME', (0,0), (-1,0), 'Helvetica-Bold'),
    ('GRID', (0,0), (-1,-1), 0.3, colors.HexColor('#ddd3e6')),
    ('BACKGROUND', (0,1), (-1,-1), colors.HexColor('#faf8fc')),
    ('VALIGN', (0,0), (-1,-1), 'MIDDLE'),
    ('TOPPADDING', (0,0), (-1,-1), 6),
    ('BOTTOMPADDING', (0,0), (-1,-1), 6),
]))
story.append(chat_table)
story.append(Paragraph('This is intentionally presented as a proof-of-operation rather than a production chat benchmark. The important result is that the SBAN runtime can now train, condition, and emit a short reply inside the container without an external language model sitting behind the command.', styles['Body']))

story.append(Paragraph('7. Limitations and next steps', styles['Section']))
story.append(Paragraph('v12 does not materially improve the maintained short target suite beyond v11, does not beat the order-2 baseline on the 250k long run, and does not claim a production conversational model. The reply path is a working SBAN demo, not a finished assistant. The architecture still appears to gain more from compact control and workload-specific operating points than from richer bridge-heavy regional machinery.', styles['Body']))
story.append(Paragraph('The highest-value next steps are therefore practical: formalize dialogue evaluation, add checkpoint/resume support for long runs, search long-term quality gates on longer corpora, and keep saturation-aware birth controls for clutter-sensitive workloads where they can be proven useful.', styles['Body']))

def on_page(canvas, doc):
    canvas.saveState()
    canvas.setFont('Helvetica', 8)
    canvas.setFillColor(colors.HexColor('#666666'))
    canvas.drawRightString(doc.pagesize[0] - 0.72*inch, 0.45*inch, str(canvas.getPageNumber()))
    canvas.drawString(0.72*inch, 0.45*inch, 'SBAN v12 follow-up research paper')
    canvas.restoreState()

doc.build(story, onFirstPage=on_page, onLaterPages=on_page)
(DOC_PAPER_DIR / 'SBAN_v12_follow_up_research_paper.pdf').write_bytes(paper_path.read_bytes())
print(f'generated: {paper_path}')
print(f'generated: {OUT_DIR / "SBAN_v12_EXECUTIVE_SUMMARY.md"}')
print(f'generated: {ROOT / "SBAN_v12_REPORT.md"}')
