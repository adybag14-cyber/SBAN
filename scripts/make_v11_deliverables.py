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
from reportlab.platypus import (
    SimpleDocTemplate,
    Paragraph,
    Spacer,
    Table,
    TableStyle,
    Image,
    PageBreak,
    KeepTogether,
)

ROOT = Path(__file__).resolve().parents[1]
RESULTS = ROOT / 'docs' / 'results'
OUT_DIR = ROOT / 'deliverables' / 'v11'
FIG_DIR = ROOT / 'docs' / 'figures' / 'v11'
OUT_DIR.mkdir(parents=True, exist_ok=True)
FIG_DIR.mkdir(parents=True, exist_ok=True)


def load_acc(path: Path) -> Tuple[float, dict]:
    data = json.loads(path.read_text())['models'][0]
    acc = 100.0 * data['total_correct'] / data['total_predictions']
    return acc, data


def fmt(x: float) -> str:
    return f"{x:.4f}%"

# Baselines carried forward from the maintained workspace and v9 paper.
BASELINES = {
    'official_v4': {'prefix': 40.51, 'drift': 42.94, 'probe': 69.89},
    'operational_v4': {'prefix': 40.9975, 'drift': 41.5350, 'probe': 68.6121},
}

v8_unified = {
    'prefix': load_acc(RESULTS / 'v8' / 'unified_prefix_v8_6bit_stress.json')[0],
    'drift': load_acc(RESULTS / 'v8' / 'unified_drift_v8_6bit_stress.json')[0],
    'probe': load_acc(RESULTS / 'v8' / 'unified_probe_v8_6bit_stress.json')[0],
}
v8_best = {
    'prefix': load_acc(RESULTS / 'v8' / 'best_prefix_v8_5bit_nolong.json')[0],
    'drift': load_acc(RESULTS / 'v8' / 'best_drift_v8_5bit_nolong.json')[0],
    'probe': load_acc(RESULTS / 'v8' / 'best_probe_v8_6bit_pp600.json')[0],
}
v10_unified = {
    'prefix': load_acc(RESULTS / 'v10' / 'unified_prefix_v10_working.json')[0],
    'drift': load_acc(RESULTS / 'v10' / 'unified_drift_v10_working.json')[0],
    'probe': load_acc(RESULTS / 'v10' / 'unified_probe_v10_working.json')[0],
}
v10_best = {
    'prefix': load_acc(RESULTS / 'v10' / 'best_prefix_v10_5bit_bm20.json')[0],
    'drift': load_acc(RESULTS / 'v10' / 'best_drift_v10_5bit_bm24.json')[0],
    'probe': load_acc(RESULTS / 'v10' / 'best_probe_v10_5bit_bm24.json')[0],
}
v11_unified = {
    'prefix': load_acc(RESULTS / 'v11' / 'unified_prefix_v11_working.json')[0],
    'drift': load_acc(RESULTS / 'v11' / 'unified_drift_v11_working.json')[0],
    'probe': load_acc(RESULTS / 'v11' / 'unified_probe_v11_working.json')[0],
}
v11_fixed = {
    'prefix': load_acc(RESULTS / 'v11' / 'unified_prefix_v11_fixed.json')[0],
    'drift': load_acc(RESULTS / 'v11' / 'unified_drift_v11_fixed.json')[0],
    'probe': load_acc(RESULTS / 'v11' / 'unified_probe_v11_fixed.json')[0],
}
v11_best = {
    'prefix': load_acc(RESULTS / 'v11' / 'best_prefix_v11_5bit_bm21_mp4.json')[0],
    'drift': load_acc(RESULTS / 'v11' / 'best_drift_v11_5bit_bm20_mp4.json')[0],
    'probe': load_acc(RESULTS / 'v11' / 'best_probe_v11_5bit_bm21_mp4.json')[0],
}

v11_unified_probe_acc, v11_unified_probe = load_acc(RESULTS / 'v11' / 'unified_probe_v11_working.json')
v11_fixed_probe_acc, v11_fixed_probe = load_acc(RESULTS / 'v11' / 'unified_probe_v11_fixed.json')
v11_unified_prefix_acc, v11_unified_prefix = load_acc(RESULTS / 'v11' / 'unified_prefix_v11_working.json')
v11_unified_drift_acc, v11_unified_drift = load_acc(RESULTS / 'v11' / 'unified_drift_v11_working.json')

same_profile_v10 = {
    'prefix': 41.8450,
    'drift': 42.1325,
    'probe': 69.26120689655173,
}


def make_figures() -> Dict[str, Path]:
    out = {}
    protocols = ['prefix', 'drift', 'probe']

    # Figure 1: maintained-suite progression
    plt.figure(figsize=(8.8, 4.8))
    x = range(len(protocols))
    width = 0.18
    series = [
        ('Operational v4', BASELINES['operational_v4']),
        ('v8 specialized', v8_best),
        ('v10 specialized', v10_best),
        ('v11 specialized', v11_best),
    ]
    for i, (label, vals) in enumerate(series):
        xs = [j + (i - 1.5) * width for j in x]
        ys = [vals[p] for p in protocols]
        plt.bar(xs, ys, width=width, label=label)
        for xx, yy in zip(xs, ys):
            plt.text(xx, yy + 0.08, f"{yy:.2f}", ha='center', va='bottom', fontsize=7)
    plt.xticks(list(x), ['Prefix', 'Drift', 'Probe'])
    plt.ylabel('Top-1 accuracy (%)')
    plt.title('Maintained target suite: operational v4 to v11')
    plt.legend(frameon=False, fontsize=8, ncol=2)
    plt.tight_layout()
    p = FIG_DIR / 'v11_maintained_progress.png'
    plt.savefig(p, dpi=180)
    plt.close()
    out['progress'] = p

    # Figure 2: v11 unified vs fixed
    plt.figure(figsize=(8.4, 4.6))
    x = range(len(protocols))
    width = 0.28
    series2 = [('v11 unified', v11_unified), ('v11 fixed-capacity', v11_fixed)]
    for i, (label, vals) in enumerate(series2):
        xs = [j + (i - 0.5) * width for j in x]
        ys = [vals[p] for p in protocols]
        plt.bar(xs, ys, width=width, label=label)
        for xx, yy in zip(xs, ys):
            plt.text(xx, yy + 0.08, f"{yy:.2f}", ha='center', va='bottom', fontsize=7)
    plt.xticks(list(x), ['Prefix', 'Drift', 'Probe'])
    plt.ylabel('Top-1 accuracy (%)')
    plt.title('v11 unified working profile versus fixed-capacity comparator')
    plt.legend(frameon=False, fontsize=8)
    plt.tight_layout()
    p = FIG_DIR / 'v11_unified_vs_fixed.png'
    plt.savefig(p, dpi=180)
    plt.close()
    out['unified_vs_fixed'] = p

    # Figure 3: probe end-state footprint
    plt.figure(figsize=(8.4, 4.6))
    labels = ['Final regions', 'Final target short', 'Final short', 'Final synapses']
    unified_vals = [v11_unified_probe['final_regions'], v11_unified_probe['final_target_short'], v11_unified_probe['final_short_memories'], v11_unified_probe['final_synapses']]
    fixed_vals = [v11_fixed_probe['final_regions'], v11_fixed_probe['final_target_short'], v11_fixed_probe['final_short_memories'], v11_fixed_probe['final_synapses']]
    x = range(len(labels))
    width = 0.28
    plt.bar([i - width / 2 for i in x], unified_vals, width=width, label='v11 unified')
    plt.bar([i + width / 2 for i in x], fixed_vals, width=width, label='v11 fixed')
    plt.xticks(list(x), labels)
    plt.ylabel('Count / target')
    plt.title('Probe end-state footprint: unified elastic versus fixed capacity')
    plt.legend(frameon=False, fontsize=8)
    plt.tight_layout()
    p = FIG_DIR / 'v11_probe_footprint.png'
    plt.savefig(p, dpi=180)
    plt.close()
    out['probe_footprint'] = p
    return out

figs = make_figures()


def delta(a: Dict[str, float], b: Dict[str, float]) -> Dict[str, float]:
    return {k: a[k] - b[k] for k in a}

v11_vs_v10_best = delta(v11_best, v10_best)
v11_vs_v8_best = delta(v11_best, v8_best)
v11_vs_fixed = delta(v11_unified, v11_fixed)

report_md = f"""# SBAN v11 Report

## Release intent

SBAN v11 pushes the current SBAN line toward a more **reproducible, stress-tested, and operationally usable** runtime. The release work focused on three fronts at the same time:

1. **Build reproducibility** using the uploaded local Zig binary and a deterministic wrapper script.
2. **Architecture and code cleanup** around carry-state selection and birth-pressure hooks.
3. **Stress tuning** on the maintained short target suite so the delivered repo ships with working profiles instead of only abstract ideas.

## What changed in v11

### 1. Local-Zig reproducible build path

The repo now carries a first-class build path through `scripts/build_with_local_zig.sh`, and the v11 release runner uses the uploaded Zig tarball directly rather than assuming a system installation.

### 2. Carry-state refinement in code

The runtime now includes:

- signature-aware carry diversity plumbing,
- precision-gated carry scoring hooks,
- support-aware carry scoring,
- a birth-pressure threshold hook for stronger future homeostatic control.

The strongest measured code-level effect in this release was on **drift robustness under a matched tuned profile**: the same 5-bit no-long-term profile with `birth_margin=21` and `min_parents_for_birth=4` moved from **42.1325%** on the v10 runtime to **42.1950%** on the v11 runtime.

### 3. Stress-tuned working profiles

The best practical profiles on the maintained suite are now:

- **Unified working profile:** 5-bit default, `enable_long_term=false`, `birth_margin=21`, `min_parents_for_birth=4`, `max_carry_memories=48`, `max_hidden_per_hop=32`, `propagation_depth=2`.
- **Best drift profile:** same compact family, but with `birth_margin=20`.

## Main v11 results

### Unified working profile

- Prefix: **{fmt(v11_unified['prefix'])}**
- Drift: **{fmt(v11_unified['drift'])}**
- Probe: **{fmt(v11_unified['probe'])}**

### Best specialized profiles

- Prefix: **{fmt(v11_best['prefix'])}**
- Drift: **{fmt(v11_best['drift'])}**
- Probe: **{fmt(v11_best['probe'])}**

### v11 unified versus fixed-capacity comparator

- Prefix delta: **{v11_vs_fixed['prefix']:+.4f} pp**
- Drift delta: **{v11_vs_fixed['drift']:+.4f} pp**
- Probe delta: **{v11_vs_fixed['probe']:+.4f} pp**

### Best specialized v11 versus best specialized v10

- Prefix delta: **{v11_vs_v10_best['prefix']:+.4f} pp**
- Drift delta: **{v11_vs_v10_best['drift']:+.4f} pp**
- Probe delta: **{v11_vs_v10_best['probe']:+.4f} pp**

### Best specialized v11 versus best specialized v8

- Prefix delta: **{v11_vs_v8_best['prefix']:+.4f} pp**
- Drift delta: **{v11_vs_v8_best['drift']:+.4f} pp**
- Probe delta: **{v11_vs_v8_best['probe']:+.4f} pp**

## Operational interpretation

The strongest current SBAN still behaves as a **compact elastic learner**:

- final live region count stays at **1** on all maintained v11 winners,
- bridge births remain effectively **0**,
- the best working profiles still disable long-term memory for this short suite,
- the elasticity advantage is clearest on **prefix** and especially on the **hard-to-easy probe**.

That means v11 improves the system as a **real runnable model**, but it does not yet claim that the bridge-heavy or long-term-heavy form is already the dominant operating regime.

## Known limitations

1. The best short-suite profiles still prefer `enable_long_term=false`, so the long-term subsystem is not yet the main source of gain.
2. Bridge memories remain functionally dormant on the maintained suite.
3. The strongest claims are still on the maintained short target suite, not yet on a complete rerun of the original published v4 protocol.
4. The runtime still reports top-1 vote accuracy rather than calibrated probabilities.
5. Synapses and state are still not bit-packed for a hardware-efficiency story.

## Recommended next work after v11

1. Revisit long-term memory with a workload where carry depth and delayed reuse genuinely matter.
2. Add a second stress layer that searches longer-horizon corpora and memory budgets rather than only the short suite.
3. Build a publication-grade reproducibility script that reruns both the maintained suite and the original v4 publication suite in one pass.
4. Keep bridge machinery available, but do not promote it as the main story until a workload proves it is paying for itself.
"""

(ROOT / 'SBAN_v11_REPORT.md').write_text(report_md)

exec_summary = f"""# Executive Summary - SBAN v11

## Project status

SBAN v11 is a further step toward making SBAN a **real, runnable, research-grade online model** rather than only a sequence of hand-tuned artifacts. The release combines code changes, build cleanup, and stress-tested operating profiles.

## What v11 added

- a **local-Zig build path** that uses the uploaded Zig binary directly,
- **carry-state selection refinements** in code,
- a **birth-pressure control hook** for future homeostatic tightening,
- bundled **v11 release scripts** and saved result JSONs.

## Best validated v11 results

### Unified working profile

- Prefix: **{fmt(v11_unified['prefix'])}**
- Drift: **{fmt(v11_unified['drift'])}**
- Probe: **{fmt(v11_unified['probe'])}**

### Best specialized profiles

- Prefix: **{fmt(v11_best['prefix'])}**
- Drift: **{fmt(v11_best['drift'])}**
- Probe: **{fmt(v11_best['probe'])}**

## Main takeaways

1. SBAN v11 is **fully buildable and runnable** from the uploaded Zig tarball.
2. The best current operating regime remains a **compact elastic short-memory learner**.
3. On the maintained suite, v11 specialized profiles improve over v10 specialized by **{v11_vs_v10_best['prefix']:+.4f} pp prefix**, **{v11_vs_v10_best['drift']:+.4f} pp drift**, and **{v11_vs_v10_best['probe']:+.4f} pp probe**.
4. The unified v11 working profile beats the matched fixed-capacity comparator by **{v11_vs_fixed['prefix']:+.4f} pp prefix**, **{v11_vs_fixed['drift']:+.4f} pp drift**, and **{v11_vs_fixed['probe']:+.4f} pp probe**.

## Known limitations

- long-term memory is still not the winning mode on the maintained short suite,
- bridge births remain effectively zero on the best runs,
- the strongest validation remains the maintained suite rather than a full rerun of the original v4 publication sweep,
- the model still uses vote-style outputs rather than calibrated probabilities,
- memory and synapse storage are not yet packed for hardware efficiency.

## Future direction

The highest-value path after v11 is to keep SBAN grounded in what is actually working: compact elastic learning, reproducible release engineering, and workload-driven subsystem validation. Long-term memory, richer regional structure, and stronger bridge rules should continue, but only where measured workloads show that the added structure is truly useful.
"""

summary_path = OUT_DIR / 'SBAN_v11_EXECUTIVE_SUMMARY.md'
summary_path.write_text(exec_summary)

# PDF generation
styles = getSampleStyleSheet()
styles.add(ParagraphStyle(name='TitleBig', parent=styles['Title'], fontName='Helvetica-Bold', fontSize=24, leading=28, textColor=colors.HexColor('#123B63'), spaceAfter=12))
styles.add(ParagraphStyle(name='Subtitle', parent=styles['BodyText'], fontName='Helvetica', fontSize=11, leading=14, textColor=colors.HexColor('#4F6173'), spaceAfter=12))
styles.add(ParagraphStyle(name='Section', parent=styles['Heading1'], fontName='Helvetica-Bold', fontSize=16, leading=20, textColor=colors.HexColor('#123B63'), spaceBefore=12, spaceAfter=8))
styles.add(ParagraphStyle(name='SubSection', parent=styles['Heading2'], fontName='Helvetica-Bold', fontSize=12, leading=15, textColor=colors.HexColor('#16324F'), spaceBefore=10, spaceAfter=4))
styles.add(ParagraphStyle(name='Body2', parent=styles['BodyText'], fontName='Helvetica', fontSize=10.2, leading=13.6, spaceAfter=7))
styles.add(ParagraphStyle(name='Small', parent=styles['BodyText'], fontName='Helvetica', fontSize=8.5, leading=11, textColor=colors.HexColor('#596B7A')))
styles.add(ParagraphStyle(name='Callout', parent=styles['BodyText'], fontName='Helvetica-Bold', fontSize=10.5, leading=13, textColor=colors.black, backColor=colors.HexColor('#EEF4FA'), borderPadding=8, borderColor=colors.HexColor('#D1E1F0'), borderWidth=0.5, borderRadius=4, spaceAfter=10))

paper_path = OUT_DIR / 'SBAN_v11_follow_up_research_paper.pdf'
doc = SimpleDocTemplate(str(paper_path), pagesize=LETTER, rightMargin=0.68*inch, leftMargin=0.78*inch, topMargin=0.65*inch, bottomMargin=0.7*inch)

story = []
story.append(Paragraph('SBAN v11: Reproducible Local-Zig Builds, Carry-State Refinement, and Stress-Tuned Compact Elastic Profiles in Zig', styles['TitleBig']))
story.append(Paragraph('A follow-up paper to the SBAN v4 and v9 lines, documenting the v11 release as a serious working model focused on reproducibility, operational tuning, and honest architectural repair rather than unsupported claims of solved generality.', styles['Subtitle']))
story.append(Paragraph(
    f"Core claim. SBAN v11 improves the maintained short target suite mainly by making the system easier to build, easier to tune, and slightly stronger in its compact elastic operating regime. The unified working profile reaches {fmt(v11_unified['prefix'])} prefix, {fmt(v11_unified['drift'])} drift, and {fmt(v11_unified['probe'])} on the hard-to-easy probe. The best specialized presets reach {fmt(v11_best['prefix'])}, {fmt(v11_best['drift'])}, and {fmt(v11_best['probe'])}.",
    styles['Callout']))

story.append(Paragraph('Abstract', styles['Section']))
story.append(Paragraph(
    'SBAN v4 introduced elastic short-memory sizing, region-tagged sparse lanes, and conservative bridge memories, while the v9 paper reframed the strongest later operating point as a compact elastic learner rather than a bridge-heavy regional hierarchy. SBAN v10 then pushed the maintained suite further through stronger working profiles. SBAN v11 continues that line with heavier emphasis on practical system quality: it adds a reproducible local-Zig build path, release scripts that rebuild and rerun the maintained suite, carry-state selection refinements in code, and a new round of stress tuning. The result is not a radically different SBAN identity. Instead, it is a more serious working release: buildable from the uploaded Zig tarball, reproducible in-container, modestly improved on the maintained suite, and clearer about where SBAN is genuinely strong today and where it is still unfinished.', styles['Body2']))

story.append(Paragraph('1. Continuity from v4 through v10', styles['Section']))
story.append(Paragraph(
    f"The published v4 frame remains important because it established both the ambition and the limits of the architecture. It reported {fmt(BASELINES['official_v4']['prefix'])} prefix, {fmt(BASELINES['official_v4']['drift'])} drift, and {fmt(BASELINES['official_v4']['probe'])} on the hard-to-easy probe. The later v9 paper then separated those publication numbers from the maintained operational anchor used for faster iteration: {fmt(BASELINES['operational_v4']['prefix'])}, {fmt(BASELINES['operational_v4']['drift'])}, and {fmt(BASELINES['operational_v4']['probe'])}. v8 specialized profiles raised that maintained anchor to {fmt(v8_best['prefix'])}, {fmt(v8_best['drift'])}, and {fmt(v8_best['probe'])}. v10 specialized then moved to {fmt(v10_best['prefix'])}, {fmt(v10_best['drift'])}, and {fmt(v10_best['probe'])}. v11 continues that same maintained-suite comparison discipline rather than pretending those numbers replace the original publication benchmark.", styles['Body2']))

story.append(Paragraph('2. What changed architecturally and operationally in v11', styles['Section']))
story.append(Paragraph('2.1 Reproducible build path', styles['SubSection']))
story.append(Paragraph('The repo now treats the uploaded Zig tarball as the primary build input. The release path is no longer dependent on a preinstalled compiler. That matters because a real research artifact should rebuild from the bundled assumptions, not from undocumented host state.', styles['Body2']))
story.append(Paragraph('2.2 Carry-state refinement', styles['SubSection']))
story.append(Paragraph('The runtime now includes carry-scoring hooks for support and precision, plus signature-aware carry diversity plumbing. These changes are deliberately conservative: they do not claim to solve the broader architecture, but they help separate useful state handoff from redundant carry clutter.', styles['Body2']))
story.append(Paragraph('2.3 Birth-pressure infrastructure', styles['SubSection']))
story.append(Paragraph('v11 also adds a birth-pressure threshold hook so the system can support stronger homeostatic gating in future releases. In the best current operating profiles that hook remains neutral, which is itself an important scientific result: not every new control path should be forced active before the workload proves it is beneficial.', styles['Body2']))

# Table of subsystem changes
subsystem_table = Table([
    ['Subsystem', 'Pre-v11 status', 'v11 refinement'],
    ['Build process', 'Local assumptions, ad hoc reruns', 'Local-Zig reproducible wrapper and release runner'],
    ['Carry selection', 'Activation-heavy carry ranking', 'Precision/support hooks and signature-diversity plumbing'],
    ['Birth control', 'Static surprise-triggered births', 'Birth-pressure threshold hook for future homeostasis'],
    ['Release engineering', 'Saved JSONs but uneven packaging', 'Dedicated v11 release/search scripts and deliverable generation'],
], colWidths=[1.4*inch, 2.2*inch, 2.8*inch])
subsystem_table.setStyle(TableStyle([
    ('BACKGROUND', (0,0), (-1,0), colors.HexColor('#123B63')),
    ('TEXTCOLOR', (0,0), (-1,0), colors.white),
    ('FONTNAME', (0,0), (-1,0), 'Helvetica-Bold'),
    ('FONTSIZE', (0,0), (-1,-1), 9),
    ('LEADING', (0,0), (-1,-1), 11),
    ('BACKGROUND', (0,1), (-1,-1), colors.HexColor('#F7FAFD')),
    ('ROWBACKGROUNDS', (0,1), (-1,-1), [colors.HexColor('#F7FAFD'), colors.HexColor('#EEF4FA')]),
    ('GRID', (0,0), (-1,-1), 0.35, colors.HexColor('#C8D8E8')),
    ('VALIGN', (0,0), (-1,-1), 'TOP'),
    ('LEFTPADDING', (0,0), (-1,-1), 6),
    ('RIGHTPADDING', (0,0), (-1,-1), 6),
    ('TOPPADDING', (0,0), (-1,-1), 6),
    ('BOTTOMPADDING', (0,0), (-1,-1), 6),
]))
story.append(subsystem_table)
story.append(Spacer(1, 0.14*inch))

story.append(Paragraph('3. Stress-testing protocol in v11', styles['Section']))
story.append(Paragraph('The v11 release keeps the maintained short target suite used in the later iterations: a prefix task, a drift task, and the hard-to-easy probe. This is still a lightweight regime compared with large-scale language-model training, but it is enough to support fast in-container iteration, code verification, and profile search. The v11 search path focuses on compact 5-bit operating points, no-long-term variants, carry budget 48, moderate hidden width, and parent/birth-margin tuning rather than a bridge-heavy search.', styles['Body2']))
story.append(Paragraph('4. Main results', styles['Section']))

results_table = Table([
    ['Protocol', 'Operational v4', 'v8 specialized', 'v10 specialized', 'v11 specialized'],
    ['Prefix', fmt(BASELINES['operational_v4']['prefix']), fmt(v8_best['prefix']), fmt(v10_best['prefix']), fmt(v11_best['prefix'])],
    ['Drift', fmt(BASELINES['operational_v4']['drift']), fmt(v8_best['drift']), fmt(v10_best['drift']), fmt(v11_best['drift'])],
    ['Probe', fmt(BASELINES['operational_v4']['probe']), fmt(v8_best['probe']), fmt(v10_best['probe']), fmt(v11_best['probe'])],
], colWidths=[1.2*inch, 1.2*inch, 1.2*inch, 1.2*inch, 1.2*inch])
results_table.setStyle(TableStyle([
    ('BACKGROUND', (0,0), (-1,0), colors.HexColor('#123B63')),
    ('TEXTCOLOR', (0,0), (-1,0), colors.white),
    ('FONTNAME', (0,0), (-1,0), 'Helvetica-Bold'),
    ('ROWBACKGROUNDS', (0,1), (-1,-1), [colors.HexColor('#F7FAFD'), colors.HexColor('#EEF4FA')]),
    ('GRID', (0,0), (-1,-1), 0.35, colors.HexColor('#C8D8E8')),
    ('ALIGN', (1,1), (-1,-1), 'CENTER'),
    ('LEFTPADDING', (0,0), (-1,-1), 6), ('RIGHTPADDING', (0,0), (-1,-1), 6),
    ('TOPPADDING', (0,0), (-1,-1), 5), ('BOTTOMPADDING', (0,0), (-1,-1), 5),
]))
story.append(results_table)
story.append(Spacer(1, 0.08*inch))
story.append(Image(str(figs['progress']), width=6.4*inch, height=3.45*inch))
story.append(Paragraph('Figure 1. Maintained target-suite comparison from the operational v4 anchor through v8, v10, and v11 specialized profiles. v11 advances the maintained suite modestly but consistently, while the paper still distinguishes that maintained frame from the original v4 publication benchmark.', styles['Small']))

story.append(PageBreak())
story.append(Paragraph('5. Unified deployment profile and fixed-capacity comparison', styles['Section']))
story.append(Paragraph(
    f"The best single working profile in v11 is the 5-bit compact elastic preset with no long-term memory, birth_margin=21, min_parents_for_birth=4, carry budget 48, hidden width 32, and depth 2. It reaches {fmt(v11_unified['prefix'])} prefix, {fmt(v11_unified['drift'])} drift, and {fmt(v11_unified['probe'])} probe. Against a matched fixed-capacity comparator, the elastic runtime stays ahead by {v11_vs_fixed['prefix']:+.4f} pp on prefix, {v11_vs_fixed['drift']:+.4f} pp on drift, and {v11_vs_fixed['probe']:+.4f} pp on the probe.", styles['Body2']))
story.append(Image(str(figs['unified_vs_fixed']), width=6.2*inch, height=3.4*inch))
story.append(Paragraph('Figure 2. Unified v11 working profile versus a matched fixed-capacity comparator. The elasticity advantage is strongest on prefix and the hard-to-easy probe, and small but positive on drift.', styles['Small']))

same_profile_table = Table([
    ['Same tuned profile', 'v10 runtime', 'v11 runtime', 'Delta'],
    ['Prefix', f"{same_profile_v10['prefix']:.4f}%", f"{v11_unified['prefix']:.4f}%", f"{v11_unified['prefix'] - same_profile_v10['prefix']:+.4f} pp"],
    ['Drift', f"{same_profile_v10['drift']:.4f}%", f"{v11_unified['drift']:.4f}%", f"{v11_unified['drift'] - same_profile_v10['drift']:+.4f} pp"],
    ['Probe', f"{same_profile_v10['probe']:.4f}%", f"{v11_unified['probe']:.4f}%", f"{v11_unified['probe'] - same_profile_v10['probe']:+.4f} pp"],
], colWidths=[1.4*inch, 1.35*inch, 1.35*inch, 1.15*inch])
same_profile_table.setStyle(TableStyle([
    ('BACKGROUND', (0,0), (-1,0), colors.HexColor('#235B2C')),
    ('TEXTCOLOR', (0,0), (-1,0), colors.white),
    ('FONTNAME', (0,0), (-1,0), 'Helvetica-Bold'),
    ('ROWBACKGROUNDS', (0,1), (-1,-1), [colors.HexColor('#F7FBF7'), colors.HexColor('#EAF5EA')]),
    ('GRID', (0,0), (-1,-1), 0.35, colors.HexColor('#C8D8C8')),
    ('ALIGN', (1,1), (-1,-1), 'CENTER'),
    ('LEFTPADDING', (0,0), (-1,-1), 6), ('RIGHTPADDING', (0,0), (-1,-1), 6),
    ('TOPPADDING', (0,0), (-1,-1), 5), ('BOTTOMPADDING', (0,0), (-1,-1), 5),
]))
story.append(Spacer(1, 0.1*inch))
story.append(same_profile_table)
story.append(Paragraph('Table 1. Matched-profile runtime comparison. Under the same tuned compact profile, the main measured code-level gain in v11 is on drift.', styles['Small']))

story.append(Paragraph('6. End-state footprint and what it means', styles['Section']))
story.append(Paragraph('v11 still ends in the same operational regime that has been emerging since the post-v4 work: one live region, zero bridge births on the winning short-suite runs, and a very compact probe end state. That is useful because it makes the system easier to inspect, regression-test, and reason about. It also imposes discipline on the claims: the best current SBAN is not yet a verified bridge-dense hierarchy. It is a compact elastic online learner with optional richer machinery.', styles['Body2']))
story.append(Image(str(figs['probe_footprint']), width=6.15*inch, height=3.35*inch))
story.append(Paragraph('Figure 3. Probe end-state footprint for the v11 unified elastic profile versus the matched fixed-capacity comparator. The elastic profile reaches a much smaller final target while retaining a small but meaningful accuracy edge.', styles['Small']))

story.append(Paragraph('7. Real-world usability implications', styles['Section']))
story.append(Paragraph('The strongest practical gain in v11 is that the artifact is easier to use like a real system. It rebuilds from the uploaded Zig toolchain, reruns through a dedicated release script, and ships with known-good result files and deliverable generation. That does not solve every scientific question, but it matters for real research velocity. A model that is difficult to rebuild is difficult to trust.', styles['Body2']))

story.append(Paragraph('8. Known limitations', styles['Section']))
story.append(Paragraph('v11 does not claim that long-term memory is solved, that bridge memories have become the dominant source of gain, that the original v4 publication suite has been fully replaced, or that SBAN has reached its final architecture ceiling. The best short-suite presets still disable long-term memory, and the bridge subsystem remains mostly dormant on these workloads.', styles['Body2']))

story.append(Paragraph('9. Highest-value next steps after v11', styles['Section']))
story.append(Paragraph('The next serious steps are straightforward: rerun the original v4 publication protocol under the v11 release harness, search longer-horizon tasks that may justify long-term memory and richer regional structure, and add hardware-efficiency reporting so the model can be evaluated not only as a scientific curiosity but as a controlled systems artifact.', styles['Body2']))

story.append(Paragraph('References', styles['Section']))
for ref in [
    'SBAN v4 research paper and executive summary.',
    'SBAN v9 follow-up research paper.',
    'Bundled v8 and v10 result JSONs in this workspace.',
    'Bundled v11 result JSONs generated by scripts/run_v11_release.sh.',
]:
    story.append(Paragraph(ref, styles['Body2']))


def add_page_number(canvas, doc):
    canvas.setFont('Helvetica', 9)
    canvas.setFillColor(colors.HexColor('#546678'))
    canvas.drawRightString(doc.pagesize[0] - 0.78*inch, 0.45*inch, f"{doc.page}")
    canvas.setFillColor(colors.black)


doc.build(story, onFirstPage=add_page_number, onLaterPages=add_page_number)
print(f'generated: {paper_path}')
print(f'generated: {summary_path}')
print(f'generated: {ROOT / "SBAN_v11_REPORT.md"}')
