# SBAN v4 - Elastic Regional Synaptic Birth-Death Assembly Network

SBAN v4 is a non-transformer byte-level online learning prototype written in Zig. It extends the earlier SBAN work with:

- elastic runtime growth and shrink of the short-memory target,
- region-tagged sparse memory lanes,
- conservative bridge-memory scaffolding,
- continued local reputation, promotion, demotion, pruning, and slot recycling,
- a reproducible enwik8 and elasticity-probe evaluation pipeline.

## Headline results

- Best prefix model: **sban_v4_4bit = 40.51%**
- Best drift model: **sban_v4_6bit = 42.94%**
- 4-bit no-reputation penalty: **3.08 pp** on prefix and **3.20 pp** on drift
- Elasticity probe: target grows **2048 -> 8192** and shrinks to **4608**

## What changed in v4

### Elastic controller

The model can raise or lower its short-memory target during runtime based on surprise, birth pressure, and utilization.

### Region lanes

Memories carry a region identity. Output scores are accumulated in region-local buffers before merge, which is the main v4 move toward future parallel execution.

### Bridge memories

Cross-region conjunctions are allowed, but conservatively. The current bridge rule is a scaffold, not yet a final tuned subsystem.

### Stable sensory anchor

The implementation avoids region-hash drift by keeping the raw sensory path stable and letting regions emerge from memory overload instead.

## Rebuild

```bash
zig build test
zig build -Doptimize=ReleaseFast
python scripts/make_artifacts.py --zig /path/to/zig --dataset /path/to/enwik8.zip
```

## Main result files

- `docs/results/enwik_prefix_v4.json`
- `docs/results/enwik_drift_v4.json`
- `docs/results/enwik_prefix_ablation_v4.json`
- `docs/results/enwik_drift_ablation_v4.json`
- `docs/results/enwik_prefix_long_ablation_v4.json`
- `docs/results/elastic_probe_ablation_v4.json`
- `docs/results/v4_summary.json`
- `docs/research_paper.pdf`

## Scientific reading of the current artifact

The v4 scaffold clearly demonstrates dynamic runtime resizing and keeps competitive online accuracy on enwik8, but it is not yet a pure accuracy upgrade over v3.

- Best v4 prefix vs v3 best: **-0.05 pp**
- Best v4 drift vs v3 best: **-0.11 pp**
- v4 4-bit vs v3 4-bit: **-0.05 pp** on prefix and **-0.16 pp** on drift

The right interpretation is therefore: **v4 broadens the architecture and validates runtime elasticity**, while the next work should focus on bridge selection, region compaction, and controller optimization.
